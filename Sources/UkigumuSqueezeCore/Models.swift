import Foundation

public enum MediaKind: String, Codable, Sendable {
    case image
    case video
}

public enum ImageFormat: String, Codable, CaseIterable, Sendable {
    case webp, jpeg, png, avif, heic, tiff

    public static func from(extension value: String) -> ImageFormat? {
        switch value.lowercased() {
        case "webp": .webp
        case "jpg", "jpeg": .jpeg
        case "png": .png
        case "avif": .avif
        case "heic", "heif": .heic
        case "tif", "tiff": .tiff
        default: nil
        }
    }

    public var preferredExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .tiff: "tiff"
        default: rawValue
        }
    }
}

public enum MediaFormat: String, Codable, CaseIterable, Sendable {
    case webp, jpeg, png, avif, heic, tiff
    case mp4, mov, m4v, avi, mpeg

    public init(_ format: ImageFormat) {
        self = MediaFormat(rawValue: format.rawValue)!
    }

    public static func from(extension value: String) -> MediaFormat? {
        if let image = ImageFormat.from(extension: value) {
            return MediaFormat(image)
        }
        switch value.lowercased() {
        case "mp4": .mp4
        case "mov", "qt": .mov
        case "m4v": .m4v
        case "avi": .avi
        case "mpg", "mpeg", "mpe", "m2v": .mpeg
        case "3gp", "3gpp": .mp4
        default: nil
        }
    }

    public var kind: MediaKind {
        imageFormat == nil ? .video : .image
    }

    public var imageFormat: ImageFormat? {
        ImageFormat(rawValue: rawValue)
    }

    public var preferredExtension: String {
        imageFormat?.preferredExtension ?? rawValue
    }

    public var isWritableVideoContainer: Bool {
        switch self {
        case .mp4, .mov, .m4v: true
        default: false
        }
    }

    /// Container we can actually write with AVFoundation.
    public var canonicalOutputFormat: MediaFormat {
        kind == .video && !isWritableVideoContainer ? .mp4 : self
    }
}

public enum OutputFormat: String, Codable, CaseIterable, Sendable {
    case original, webp, jpeg, png, avif, heic, tiff, mp4, mov

    public static let photoFormats: [OutputFormat] = [.webp, .jpeg, .png, .avif, .heic, .tiff]
    public static let videoFormats: [OutputFormat] = [.mp4, .mov]

    public var imageFormat: ImageFormat? {
        self == .original ? nil : ImageFormat(rawValue: rawValue)
    }

    public var mediaFormat: MediaFormat? {
        self == .original ? nil : MediaFormat(rawValue: rawValue)
    }

    public func resolvedFormat(for source: MediaFormat) -> MediaFormat {
        guard let selected = mediaFormat else {
            return source.canonicalOutputFormat
        }
        switch (source.kind, selected.kind) {
        case (.image, .image), (.video, .video):
            return selected
        case (.video, .image):
            return source.canonicalOutputFormat
        case (.image, .video):
            return source
        }
    }
}

public enum ResolutionMode: String, Codable, CaseIterable, Sendable {
    case original
    case percent90
    case percent75
    case half
    case third
    case quarter
    case customWidth
    case customHeight
    case fit
    case exact
}

public struct PixelSize: Equatable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public enum ResolutionCalculator {
    public static func dimensions(
        sourceWidth: Int,
        sourceHeight: Int,
        mode: ResolutionMode,
        width: Int,
        height: Int
    ) -> PixelSize {
        let source = PixelSize(width: max(1, sourceWidth), height: max(1, sourceHeight))
        switch mode {
        case .original:
            return source
        case .percent90:
            return scaled(source, by: 0.9)
        case .percent75:
            return scaled(source, by: 0.75)
        case .half:
            return scaled(source, by: 0.5)
        case .third:
            return scaled(source, by: 1.0 / 3.0)
        case .quarter:
            return scaled(source, by: 0.25)
        case .customWidth:
            return proportional(source, maximumWidth: width, maximumHeight: nil)
        case .customHeight:
            return proportional(source, maximumWidth: nil, maximumHeight: height)
        case .fit:
            return proportional(source, maximumWidth: width, maximumHeight: height)
        case .exact:
            return PixelSize(
                width: min(source.width, max(1, width)),
                height: min(source.height, max(1, height))
            )
        }
    }

    private static func scaled(_ source: PixelSize, by scale: Double) -> PixelSize {
        PixelSize(
            width: max(1, Int((Double(source.width) * scale).rounded())),
            height: max(1, Int((Double(source.height) * scale).rounded()))
        )
    }

    private static func proportional(
        _ source: PixelSize,
        maximumWidth: Int?,
        maximumHeight: Int?
    ) -> PixelSize {
        let widthScale = maximumWidth.map { Double(max(1, $0)) / Double(source.width) } ?? 1
        let heightScale = maximumHeight.map { Double(max(1, $0)) / Double(source.height) } ?? 1
        return scaled(source, by: min(1, min(widthScale, heightScale)))
    }
}

public enum ItemStatus: String, Codable, Sendable {
    case pending, processing, completed, noImprovement, cancelled, error
}

public struct DiscoveredImage: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let sourceURL: URL
    public let rootURL: URL
    public let relativePath: String
    public let format: MediaFormat
    public let byteCount: Int64

    public init(sourceURL: URL, rootURL: URL, relativePath: String, format: MediaFormat, byteCount: Int64) {
        self.id = UUID()
        self.sourceURL = sourceURL
        self.rootURL = rootURL
        self.relativePath = relativePath
        self.format = format
        self.byteCount = byteCount
    }
}

public struct ProcessingOptions: Sendable {
    public var quality: Double
    public var outputFormat: OutputFormat
    public var preserveMetadata: Bool
    public var exportJSON: Bool
    public var destinationURL: URL?
    public var resolutionMode: ResolutionMode
    public var resolutionWidth: Int
    public var resolutionHeight: Int

    public init(
        quality: Double = 0.8,
        outputFormat: OutputFormat = .original,
        preserveMetadata: Bool = true,
        exportJSON: Bool = false,
        destinationURL: URL? = nil,
        resolutionMode: ResolutionMode = .original,
        resolutionWidth: Int = 1920,
        resolutionHeight: Int = 1080
    ) {
        self.quality = min(max(quality, 0), 1)
        self.outputFormat = outputFormat
        self.preserveMetadata = preserveMetadata
        self.exportJSON = exportJSON
        self.destinationURL = destinationURL
        self.resolutionMode = resolutionMode
        self.resolutionWidth = max(1, resolutionWidth)
        self.resolutionHeight = max(1, resolutionHeight)
    }
}

public struct ProcessingResult: Identifiable, Encodable, Sendable {
    public let id: UUID
    public let originalRelativePath: String
    public let finalRelativePath: String
    public let originalName: String
    public let finalName: String
    public let originalFormat: MediaFormat
    public let finalFormat: MediaFormat
    public let width: Int
    public let height: Int
    public let originalBytes: Int64
    public let finalBytes: Int64
    public let metadataAvailable: Bool
    public let status: ItemStatus
    public let error: String?

    public var bytesSaved: Int64 { originalBytes - finalBytes }
    public var percentageSaved: Double {
        originalBytes == 0 ? 0 : Double(bytesSaved) / Double(originalBytes) * 100
    }

    enum CodingKeys: String, CodingKey {
        case originalRelativePath, finalRelativePath, originalName, finalName
        case originalFormat, finalFormat, width, height, originalBytes, finalBytes
        case bytesSaved, percentageSaved, metadataAvailable, status, error
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(originalRelativePath, forKey: .originalRelativePath)
        try container.encode(finalRelativePath, forKey: .finalRelativePath)
        try container.encode(originalName, forKey: .originalName)
        try container.encode(finalName, forKey: .finalName)
        try container.encode(originalFormat, forKey: .originalFormat)
        try container.encode(finalFormat, forKey: .finalFormat)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(originalBytes, forKey: .originalBytes)
        try container.encode(finalBytes, forKey: .finalBytes)
        try container.encode(bytesSaved, forKey: .bytesSaved)
        try container.encode(percentageSaved, forKey: .percentageSaved)
        try container.encode(metadataAvailable, forKey: .metadataAvailable)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(error, forKey: .error)
    }
}

public enum UkigumuSqueezeError: LocalizedError {
    case unsupportedFormat(URL)
    case invalidImage(URL)
    case invalidVideo(URL)
    case outputFormatUnavailable(ImageFormat)
    case videoExportUnavailable
    case collision(URL)
    case originalFolderConflict(URL)
    case validationFailed(URL)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let url): "Unsupported file format: \(url.lastPathComponent)"
        case .invalidImage(let url): "Invalid or corrupt image: \(url.lastPathComponent)"
        case .invalidVideo(let url): "Invalid or corrupt video: \(url.lastPathComponent)"
        case .outputFormatUnavailable(let format): "\(format.rawValue.uppercased()) encoding is unavailable on this macOS version"
        case .videoExportUnavailable: "No compatible local video export preset is available"
        case .collision(let url): "Output already exists: \(url.path)"
        case .originalFolderConflict(let url): "An Original folder conflicts with the required original folder: \(url.path)"
        case .validationFailed(let url): "The encoded file could not be validated: \(url.lastPathComponent)"
        }
    }
}

extension ProcessingResult {
    static func success(
        plan: PlannedOutput,
        width: Int,
        height: Int,
        finalBytes: Int64,
        metadataAvailable: Bool,
        status: ItemStatus
    ) -> ProcessingResult {
        ProcessingResult(
            id: plan.image.id,
            originalRelativePath: plan.image.relativePath,
            finalRelativePath: plan.relativeOutputPath,
            originalName: plan.image.sourceURL.lastPathComponent,
            finalName: plan.outputURL.lastPathComponent,
            originalFormat: plan.image.format,
            finalFormat: plan.finalFormat,
            width: width,
            height: height,
            originalBytes: plan.image.byteCount,
            finalBytes: finalBytes,
            metadataAvailable: metadataAvailable,
            status: status,
            error: nil
        )
    }

    static func failure(plan: PlannedOutput, status: ItemStatus, error: String?) -> ProcessingResult {
        ProcessingResult(
            id: plan.image.id,
            originalRelativePath: plan.image.relativePath,
            finalRelativePath: plan.relativeOutputPath,
            originalName: plan.image.sourceURL.lastPathComponent,
            finalName: plan.outputURL.lastPathComponent,
            originalFormat: plan.image.format,
            finalFormat: plan.finalFormat,
            width: 0,
            height: 0,
            originalBytes: plan.image.byteCount,
            finalBytes: 0,
            metadataAvailable: false,
            status: status,
            error: error
        )
    }
}
