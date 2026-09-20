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
        // Explicit returns: Swift 6 on Xcode 26 cannot infer implicit
        // member types after an earlier return in the same function.
        switch value.lowercased() {
        case "mp4": return .mp4
        case "mov", "qt": return .mov
        case "m4v": return .m4v
        case "avi": return .avi
        case "mpg", "mpeg", "mpe", "m2v": return .mpeg
        case "3gp", "3gpp": return .mp4
        default: return nil
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

    public func resolvedFormat(for source: MediaFormat, videoProfile: VideoEncodeProfile) -> MediaFormat {
        let resolved = resolvedFormat(for: source)
        guard source.kind == .video else { return resolved }
        return videoProfile.resolvedContainer(for: resolved)
    }
}

public enum VideoCodec: String, Codable, Sendable {
    case h264
    case hevc

    public var displayName: String {
        switch self {
        case .h264: "H.264"
        case .hevc: "HEVC"
        }
    }
}

public enum VideoResolutionCap: String, Codable, CaseIterable, Sendable {
    case p720
    case p1080
    case p1440
    case source

    public var title: String {
        switch self {
        case .p720: "720p"
        case .p1080: "1080p"
        case .p1440: "1440p"
        case .source: "Source"
        }
    }

    public var pixelSize: PixelSize? {
        switch self {
        case .p720: PixelSize(width: 1280, height: 720)
        case .p1080: PixelSize(width: 1920, height: 1080)
        case .p1440: PixelSize(width: 2560, height: 1440)
        case .source: nil
        }
    }
}

public enum VideoQualityLean: String, Codable, CaseIterable, Sendable {
    case smaller
    case balanced
    case higher

    public var title: String {
        switch self {
        case .smaller: "Smaller"
        case .balanced: "Balanced"
        case .higher: "Higher"
        }
    }
}

public struct VideoEncodeProfile: Sendable, Equatable {
    public let codec: VideoCodec
    public let audio: String
    public let cap: VideoResolutionCap
    public let lean: VideoQualityLean
    public let optimizeForSharing: Bool

    public init(
        codec: VideoCodec,
        audio: String = "AAC",
        cap: VideoResolutionCap,
        lean: VideoQualityLean,
        optimizeForSharing: Bool
    ) {
        self.codec = codec
        self.audio = audio
        self.cap = cap
        self.lean = lean
        self.optimizeForSharing = optimizeForSharing
    }

    public var recipe: String {
        let container = prefersMPEG4Container ? "MP4" : "MOV or MP4"
        return "\(codec.displayName) · \(audio) · \(cap.title) · \(container)"
    }

    /// H.264 system export presets are MPEG-4. Keep MOV only for HEVC.
    public var prefersMPEG4Container: Bool {
        codec == .h264
    }

    public func resolvedContainer(for requested: MediaFormat) -> MediaFormat {
        guard requested.kind == .video else { return requested }
        if prefersMPEG4Container {
            return .mp4
        }
        return requested.isWritableVideoContainer ? requested : .mp4
    }

    public func dimensions(sourceWidth: Int, sourceHeight: Int) -> PixelSize {
        guard let capSize = cap.pixelSize else {
            return PixelSize(width: max(1, sourceWidth), height: max(1, sourceHeight))
        }
        return ResolutionCalculator.dimensions(
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
            mode: .fit,
            width: capSize.width,
            height: capSize.height
        )
    }
}

public enum VideoPreset: String, Codable, CaseIterable, Sendable {
    case smallerFile
    case fast1080p
    case social
    case highQuality
    case custom

    public var title: String {
        switch self {
        case .smallerFile: "Smaller File"
        case .fast1080p: "Fast 1080p"
        case .social: "Social"
        case .highQuality: "High Quality"
        case .custom: "Custom"
        }
    }

    public var tradeoff: String {
        switch self {
        case .smallerFile: "Smallest size. Caps at 720p. Writes MP4."
        case .fast1080p: "Balanced size and quality. Caps at 1080p. Writes MP4."
        case .social: "Shareable MP4. Caps at 1080p."
        case .highQuality: "Best look. Keeps the source resolution."
        case .custom: "Pick a cap and a size versus quality lean."
        }
    }

    public func profile(
        customCap: VideoResolutionCap = .p1080,
        customLean: VideoQualityLean = .balanced
    ) -> VideoEncodeProfile {
        switch self {
        case .smallerFile:
            VideoEncodeProfile(codec: .h264, cap: .p720, lean: .smaller, optimizeForSharing: true)
        case .fast1080p:
            VideoEncodeProfile(codec: .h264, cap: .p1080, lean: .balanced, optimizeForSharing: true)
        case .social:
            VideoEncodeProfile(codec: .h264, cap: .p1080, lean: .smaller, optimizeForSharing: true)
        case .highQuality:
            VideoEncodeProfile(codec: .hevc, cap: .source, lean: .higher, optimizeForSharing: false)
        case .custom:
            VideoEncodeProfile(
                codec: customLean == .higher ? .hevc : .h264,
                cap: customCap,
                lean: customLean,
                optimizeForSharing: customLean == .smaller
            )
        }
    }

    public func dimensions(
        sourceWidth: Int,
        sourceHeight: Int,
        customCap: VideoResolutionCap = .p1080,
        customLean: VideoQualityLean = .balanced
    ) -> PixelSize {
        profile(customCap: customCap, customLean: customLean)
            .dimensions(sourceWidth: sourceWidth, sourceHeight: sourceHeight)
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

    public func displayLabel() -> String {
        // Explicit returns: Swift 6 on Xcode 26 cannot treat a mixed
        // implicit/explicit switch as a single-expression String body.
        switch self {
        case .pending: return "Waiting"
        case .processing: return "Encoding"
        case .completed: return "Done"
        case .noImprovement: return "No change"
        case .cancelled: return "Cancelled"
        case .error: return "Error"
        }
    }

    /// Visible queue subtitle. Always non-empty for `.error` so the table never shows a bare Error row.
    public func displayDetail(error: String?) -> String? {
        guard self == .error else { return nil }
        let detail = error?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return detail.isEmpty ? "Export failed" : detail
    }
}

public enum ProcessingErrorMessage: Sendable {
    public static let sandboxBlocked =
        "macOS blocked access to this file. Re-choose the file or folder with Choose files…"

    public static func fromFailure(_ error: Error) -> String {
        let raw = rawMessage(error)
        if isPermissionFailure(error) {
            if raw.isEmpty || isOpaquePermissionMessage(raw) {
                return sandboxBlocked
            }
            if raw.contains(sandboxBlocked) {
                return raw
            }
            return "\(sandboxBlocked) \(raw)"
        }
        return raw.isEmpty ? "Video export failed" : raw
    }

    public static func isPermissionFailure(_ error: Error) -> Bool {
        if isPermissionNSError(error as NSError) { return true }
        if isOpaquePermissionMessage(rawMessage(error)) { return true }
        return false
    }

    private static func rawMessage(_ error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
           !description.isEmpty {
            return description
        }
        let nsError = error as NSError
        let candidates = [
            nsError.localizedFailureReason,
            nsError.localizedRecoverySuggestion,
            nsError.localizedDescription
        ]
        for candidate in candidates {
            let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            let nested = rawMessage(underlying)
            if !nested.isEmpty, nested != "Video export failed" {
                return nested
            }
        }
        return ""
    }

    private static func isPermissionNSError(_ error: NSError) -> Bool {
        if error.domain == NSCocoaErrorDomain,
           error.code == NSFileReadNoPermissionError || error.code == NSFileWriteNoPermissionError {
            return true
        }
        if error.domain == NSPOSIXErrorDomain, error.code == 1 || error.code == 13 {
            return true
        }
        if isOpaquePermissionMessage(error.localizedDescription)
            || isOpaquePermissionMessage(error.localizedFailureReason ?? "") {
            return true
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isPermissionNSError(underlying)
        }
        return false
    }

    private static func isOpaquePermissionMessage(_ message: String) -> Bool {
        let folded = message
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .lowercased()
        return folded.contains("don't have permission")
            || folded.contains("you do not have permission")
            || folded.contains("not permitted")
            || folded == "the operation couldn't be completed."
    }
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
    public var videoPreset: VideoPreset
    public var videoResolutionCap: VideoResolutionCap
    public var videoQualityLean: VideoQualityLean

    public init(
        quality: Double = 0.8,
        outputFormat: OutputFormat = .original,
        preserveMetadata: Bool = true,
        exportJSON: Bool = false,
        destinationURL: URL? = nil,
        resolutionMode: ResolutionMode = .original,
        resolutionWidth: Int = 1920,
        resolutionHeight: Int = 1080,
        videoPreset: VideoPreset = .fast1080p,
        videoResolutionCap: VideoResolutionCap = .p1080,
        videoQualityLean: VideoQualityLean = .balanced
    ) {
        self.quality = min(max(quality, 0), 1)
        self.outputFormat = outputFormat
        self.preserveMetadata = preserveMetadata
        self.exportJSON = exportJSON
        self.destinationURL = destinationURL
        self.resolutionMode = resolutionMode
        self.resolutionWidth = max(1, resolutionWidth)
        self.resolutionHeight = max(1, resolutionHeight)
        self.videoPreset = videoPreset
        self.videoResolutionCap = videoResolutionCap
        self.videoQualityLean = videoQualityLean
    }

    public var videoProfile: VideoEncodeProfile {
        videoPreset.profile(customCap: videoResolutionCap, customLean: videoQualityLean)
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

    public var statusTitle: String { status.displayLabel() }
    public var statusDetail: String? { status.displayDetail(error: error) }

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
    case videoExportIncompatible(MediaFormat)
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
        case .videoExportIncompatible(let format):
            "No compatible export preset can write \(format.rawValue.uppercased()). H.264 presets write MP4."
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
        let trimmed = error?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedError: String?
        switch status {
        case .error:
            resolvedError = (trimmed?.isEmpty == false) ? trimmed : ItemStatus.error.displayDetail(error: nil)
        default:
            resolvedError = (trimmed?.isEmpty == false) ? trimmed : nil
        }
        return ProcessingResult(
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
            error: resolvedError
        )
    }
}
