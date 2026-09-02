import Foundation

public struct PlannedOutput: Sendable {
    public let image: DiscoveredImage
    public let outputURL: URL
    public let backupURL: URL?
    public let relativeOutputPath: String
    public let finalFormat: ImageFormat
}

public struct OutputPlanner: Sendable {
    public init() {}

    public func plan(images: [DiscoveredImage], options: ProcessingOptions) throws -> [PlannedOutput] {
        var claimed = Set<String>()
        return try images.map { image in
            let finalFormat = options.outputFormat.imageFormat ?? image.format
            let relativeOutput = outputPath(for: image, format: finalFormat, converting: options.outputFormat != .original)
            let outputRoot = options.destinationURL ?? image.rootURL
            let output = outputRoot.appending(path: relativeOutput)
            let key = output.standardizedFileURL.path.lowercased()
            guard claimed.insert(key).inserted else { throw UkigumuSqueezeError.collision(output) }

            let backup = options.destinationURL == nil
                ? image.rootURL.appending(path: "original").appending(path: image.relativePath)
                : nil
            return PlannedOutput(
                image: image,
                outputURL: output,
                backupURL: backup,
                relativeOutputPath: relativeOutput,
                finalFormat: finalFormat
            )
        }
    }

    public func validateOriginalFolders(for images: [DiscoveredImage]) throws {
        for root in Set(images.map(\.rootURL)) {
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey]
            ) else { continue }
            if let conflict = contents.first(where: {
                $0.lastPathComponent.lowercased() == "original" && $0.lastPathComponent != "original"
            }) {
                throw UkigumuSqueezeError.originalFolderConflict(conflict)
            }
        }
    }

    private func outputPath(for image: DiscoveredImage, format: ImageFormat, converting: Bool) -> String {
        guard converting else { return image.relativePath }
        let path = image.relativePath as NSString
        return path.deletingPathExtension + "." + format.preferredExtension
    }

}

public enum Savings {
    public static func bytes(original: Int64, final: Int64) -> Int64 { original - final }
    public static func percentage(original: Int64, final: Int64) -> Double {
        original == 0 ? 0 : Double(original - final) / Double(original) * 100
    }
}
