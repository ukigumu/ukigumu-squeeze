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
                throw GrumpySqueezeError.invalidImage(plan.image.sourceURL)
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
            let temporary = plan.outputURL.deletingLastPathComponent()
                .appending(path: ".grumpy-squeeze-\(UUID().uuidString).tmp")
            defer { try? fileManager.removeItem(at: temporary) }

            try fileManager.createDirectory(at: temporary.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encode(
                resizedImage, source: source,
                sourceProperties: properties,
                to: temporary,
                format: plan.finalFormat,
                quality: options.quality,
                preserveMetadata: options.preserveMetadata,
                resolutionMode: options.resolutionMode,
                resolutionWidth: options.resolutionWidth,
                resolutionHeight: options.resolutionHeight
            )
            let expectedPageCount = plan.finalFormat == .tiff ? CGImageSourceGetCount(source) : 1
            try validate(
                temporary, expectedFormat: plan.finalFormat,
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
                return result(
                    plan: plan, width: targetSize.width, height: targetSize.height,
                    finalBytes: plan.image.byteCount, metadataAvailable: metadataAvailable,
                    status: .noImprovement
                )
            }

            try commit(temporary: temporary, plan: plan)
            return result(
                plan: plan, width: targetSize.width, height: targetSize.height,
                finalBytes: encodedSize, metadataAvailable: metadataAvailable,
                status: .completed
            )
        } catch is CancellationError {
            return failure(plan: plan, status: .cancelled, error: nil)
        } catch {
            return failure(plan: plan, status: .error, error: error.localizedDescription)
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
            throw GrumpySqueezeError.outputFormatUnavailable(format)
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
                    throw GrumpySqueezeError.invalidImage(url)
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
            throw GrumpySqueezeError.validationFailed(url)
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
            throw GrumpySqueezeError.validationFailed(URL(filePath: "resized-image"))
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        guard let resized = context.makeImage() else {
            throw GrumpySqueezeError.validationFailed(URL(filePath: "resized-image"))
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
            throw GrumpySqueezeError.validationFailed(url)
        }
    }

    private func commit(temporary: URL, plan: PlannedOutput) throws {
        if let backup = plan.backupURL {
            try fileManager.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: backup.path) {
                try fileManager.removeItem(at: backup)
            }
            try fileManager.moveItem(at: plan.image.sourceURL, to: backup)
            do {
                if plan.outputURL != plan.image.sourceURL,
                   fileManager.fileExists(atPath: plan.outputURL.path) {
                    try fileManager.removeItem(at: plan.outputURL)
                }
                try fileManager.moveItem(at: temporary, to: plan.outputURL)
            } catch {
                try? fileManager.moveItem(at: backup, to: plan.image.sourceURL)
                throw error
            }
        } else {
            if fileManager.fileExists(atPath: plan.outputURL.path) {
                _ = try fileManager.replaceItemAt(plan.outputURL, withItemAt: temporary)
            } else {
                try fileManager.moveItem(at: temporary, to: plan.outputURL)
            }
        }
    }

    private func result(
        plan: PlannedOutput, width: Int, height: Int, finalBytes: Int64,
        metadataAvailable: Bool, status: ItemStatus
    ) -> ProcessingResult {
        ProcessingResult(
            id: plan.image.id,
            originalRelativePath: plan.image.relativePath,
            finalRelativePath: plan.relativeOutputPath,
            originalName: plan.image.sourceURL.lastPathComponent,
            finalName: plan.outputURL.lastPathComponent,
            originalFormat: plan.image.format,
            finalFormat: plan.finalFormat,
            width: width, height: height,
            originalBytes: plan.image.byteCount, finalBytes: finalBytes,
            metadataAvailable: metadataAvailable, status: status, error: nil
        )
    }

    private func failure(plan: PlannedOutput, status: ItemStatus, error: String?) -> ProcessingResult {
        ProcessingResult(
            id: plan.image.id,
            originalRelativePath: plan.image.relativePath,
            finalRelativePath: plan.relativeOutputPath,
            originalName: plan.image.sourceURL.lastPathComponent,
            finalName: plan.outputURL.lastPathComponent,
            originalFormat: plan.image.format, finalFormat: plan.finalFormat,
            width: 0, height: 0, originalBytes: plan.image.byteCount, finalBytes: 0,
            metadataAvailable: false, status: status, error: error
        )
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
