import Foundation

public struct BatchSummary: Encodable, Sendable {
    public let total: Int
    public let completed: Int
    public let noImprovement: Int
    public let cancelled: Int
    public let errors: Int
    public let originalBytes: Int64
    public let finalBytes: Int64
    public var bytesSaved: Int64 { originalBytes - finalBytes }

    public init(results: [ProcessingResult]) {
        total = results.count
        completed = results.count { $0.status == .completed }
        noImprovement = results.count { $0.status == .noImprovement }
        cancelled = results.count { $0.status == .cancelled }
        errors = results.count { $0.status == .error }
        originalBytes = results.reduce(0) { $0 + $1.originalBytes }
        finalBytes = results.reduce(0) { $0 + $1.finalBytes }
    }

    enum CodingKeys: String, CodingKey {
        case total, completed, noImprovement, cancelled, errors
        case originalBytes, finalBytes, bytesSaved
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(total, forKey: .total)
        try container.encode(completed, forKey: .completed)
        try container.encode(noImprovement, forKey: .noImprovement)
        try container.encode(cancelled, forKey: .cancelled)
        try container.encode(errors, forKey: .errors)
        try container.encode(originalBytes, forKey: .originalBytes)
        try container.encode(finalBytes, forKey: .finalBytes)
        try container.encode(bytesSaved, forKey: .bytesSaved)
    }
}

public struct MetadataReport: Encodable, Sendable {
    public let schemaVersion: Int
    public let applicationVersion: String
    public let date: String
    public let quality: Double
    public let selectedFormat: OutputFormat
    public let resolutionMode: ResolutionMode
    public let resolutionWidth: Int
    public let resolutionHeight: Int
    public let metadataPolicy: String
    public let usesDestination: Bool
    public let summary: BatchSummary
    public let images: [ProcessingResult]

    public init(results: [ProcessingResult], options: ProcessingOptions, date: Date = Date()) {
        schemaVersion = 1
        applicationVersion = "1.0.0"
        self.date = ISO8601DateFormatter().string(from: date)
        quality = options.quality
        selectedFormat = options.outputFormat
        resolutionMode = options.resolutionMode
        resolutionWidth = options.resolutionWidth
        resolutionHeight = options.resolutionHeight
        metadataPolicy = options.preserveMetadata ? "preserve-compatible" : "remove"
        usesDestination = options.destinationURL != nil
        summary = BatchSummary(results: results)
        images = results.sorted { $0.originalRelativePath < $1.originalRelativePath }
    }

    public func writeAtomically(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        try data.write(to: url, options: .atomic)
    }
}
