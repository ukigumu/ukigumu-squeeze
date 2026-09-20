import Foundation
import ImageIO
import UniformTypeIdentifiers

public actor ImageProcessor {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func process(
        _ plan: PlannedOutput,
        options: ProcessingOptions
    ) async -> ProcessingResult {
        do {
            try Task.checkCancellation()
            guard let source = CGImageSourceCreateWithURL(plan.image.sourceURL as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw UkigumuSqueezeError.invalidImage(plan.image.sourceURL)
            }
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            let metadataAvailable = !(properties ?? [:]).isEmpty
            let targetSize = ResolutionCalculator.dimensions(
                sourceWidth: image.width,
                sourceHeight: image.height,
                mode: options.resolutionMode,
                width: options.resolutionWidth,
                height: options.resolutionHeight
            )
            let resizedImage = try resize(image, to: targetSize)
            guard let finalImageFormat = plan.finalFormat.imageFormat else {
                throw UkigumuSqueezeError.invalidImage(plan.image.sourceURL)
            }
            let temporary = TemporaryOutput.url(adjacentTo: plan.outputURL)
            defer { try? fileManager.removeItem(at: temporary) }

            try fileManager.createDirectory(at: temporary.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encode(
                resizedImage, source: source,
                sourceProperties: properties,
                to: temporary,
                format: finalImageFormat,
                quality: options.quality,
                preserveMetadata: options.preserveMetadata,
                resolutionMode: options.resolutionMode,
                resolutionWidth: options.resolutionWidth,
                resolutionHeight: options.resolutionHeight
            )
            let expectedPageCount = finalImageFormat == .tiff ? CGImageSourceGetCount(source) : 1
            try validate(
                temporary, expectedFormat: finalImageFormat,
                width: targetSize.width, height: targetSize.height, expectedPageCount: expectedPageCount
            )
            try Task.checkCancellation()
            let encodedSize = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(Int64.init) ?? 0

            if options.outputFormat == .original,
               options.resolutionMode == .original,
               encodedSize >= plan.image.byteCount {
                if options.destinationURL != nil {
                    try fileManager.copyItem(at: plan.image.sourceURL, to: plan.outputURL)
                }
                return ProcessingResult.success(
                    plan: plan, width: targetSize.width, height: targetSize.height,
                    finalBytes: plan.image.byteCount, metadataAvailable: metadataAvailable,
                    status: .noImprovement
                )
            }

            try OutputCommitter.commit(temporary: temporary, plan: plan, fileManager: fileManager)
            return ProcessingResult.success(
                plan: plan, width: targetSize.width, height: targetSize.height,
                finalBytes: encodedSize, metadataAvailable: metadataAvailable,
                status: .completed
            )
        } catch is CancellationError {
            return ProcessingResult.failure(plan: plan, status: .cancelled, error: nil)
        } catch {
            return ProcessingResult.failure(
                plan: plan,
                status: .error,
                error: ProcessingErrorMessage.fromFailure(error)
            )
        }
    }

    private func encode(
        _ image: CGImage,
        source: CGImageSource,
        sourceProperties: [CFString: Any]?,
        to url: URL,
        format: ImageFormat,
        quality: Double,
        preserveMetadata: Bool,
        resolutionMode: ResolutionMode,
        resolutionWidth: Int,
        resolutionHeight: Int
    ) throws {
        if format == .webp {
            try WebPEncoder.encode(image, quality: quality, to: url)
            return
        }
        let type = uti(for: format)
        let writableTypes = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        guard writableTypes.contains(type as String),
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL, type, format == .tiff ? CGImageSourceGetCount(source) : 1, nil
              ) else {
            throw UkigumuSqueezeError.outputFormatUnavailable(format)
        }
        var properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]
        if preserveMetadata, let sourceProperties {
            properties.merge(sourceProperties) { current, _ in current }
        }
        if format == .tiff {
            for index in 0..<CGImageSourceGetCount(source) {
                guard let page = CGImageSourceCreateImageAtIndex(source, index, nil) else {
                    throw UkigumuSqueezeError.invalidImage(url)
                }
                let pageSize = ResolutionCalculator.dimensions(
                    sourceWidth: page.width,
                    sourceHeight: page.height,
                    mode: resolutionMode,
                    width: resolutionWidth,
                    height: resolutionHeight
                )
                let resizedPage = try resize(page, to: pageSize)
                var pageProperties = properties
                if preserveMetadata,
                   let sourcePageProperties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] {
                    pageProperties.merge(sourcePageProperties) { current, _ in current }
                }
                CGImageDestinationAddImage(destination, resizedPage, pageProperties as CFDictionary)
            }
        } else {
            CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else {
            throw UkigumuSqueezeError.validationFailed(url)
        }
    }

    private func resize(_ image: CGImage, to size: PixelSize) throws -> CGImage {
        guard image.width != size.width || image.height != size.height else { return image }
        guard let context = CGContext(
            data: nil,
            width: size.width,
            height: size.height,
            bitsPerComponent: 8,
            bytesPerRow: size.width * 4,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw UkigumuSqueezeError.validationFailed(URL(filePath: "resized-image"))
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        guard let resized = context.makeImage() else {
            throw UkigumuSqueezeError.validationFailed(URL(filePath: "resized-image"))
        }
        return resized
    }

    private func validate(
        _ url: URL, expectedFormat: ImageFormat, width: Int, height: Int, expectedPageCount: Int
    ) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) == expectedPageCount,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width == width, image.height == height,
              let type = CGImageSourceGetType(source),
              type as String == uti(for: expectedFormat) as String
                || formatsEquivalent(type as String, expectedFormat) else {
            throw UkigumuSqueezeError.validationFailed(url)
        }
    }

    private func uti(for format: ImageFormat) -> CFString {
        switch format {
        case .webp: "org.webmproject.webp" as CFString
        case .jpeg: UTType.jpeg.identifier as CFString
        case .png: UTType.png.identifier as CFString
        case .avif: "public.avif" as CFString
        case .heic: UTType.heic.identifier as CFString
        case .tiff: UTType.tiff.identifier as CFString
        }
    }

    private func formatsEquivalent(_ type: String, _ format: ImageFormat) -> Bool {
        switch format {
        case .avif: type == "public.avif" || type == "public.avci"
        case .heic: type == "public.heic" || type == "public.heif"
        default: false
        }
    }
}
