import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct FileDiscovery: Sendable {
    public init() {}

    public func discover(at inputs: [URL], excluding destination: URL? = nil) -> [DiscoveredImage] {
        inputs.flatMap { discover(at: $0, excluding: destination) }
            .sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
    }

    private func discover(at input: URL, excluding destination: URL?) -> [DiscoveredImage] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: input.path, isDirectory: &isDirectory) else { return [] }
        let root = isDirectory.boolValue ? input : input.deletingLastPathComponent()
        if !isDirectory.boolValue {
            return makeImage(input, root: root).map { [$0] } ?? []
        }

        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: input,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var images: [DiscoveredImage] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: keys)
            if values?.isSymbolicLink == true {
                if values?.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            if values?.isDirectory == true {
                if shouldExcludeDirectory(url, destination: destination) { enumerator.skipDescendants() }
                continue
            }
            guard values?.isRegularFile == true, !isIgnoredFile(url) else { continue }
            if let image = makeImage(url, root: root) { images.append(image) }
        }
        return images
    }

    private func shouldExcludeDirectory(_ url: URL, destination: URL?) -> Bool {
        if url.lastPathComponent.lowercased() == "original" { return true }
        guard let destination else { return false }
        return url.standardizedFileURL.path == destination.standardizedFileURL.path
            || url.standardizedFileURL.path.hasPrefix(destination.standardizedFileURL.path + "/")
    }

    private func isIgnoredFile(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return name == "ukigumu-squeeze-metadata.json"
            || name.hasPrefix(".ukigumu-squeeze-")
            || name.hasSuffix(".tmp")
    }

    private func makeImage(_ url: URL, root: URL) -> DiscoveredImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let type = CGImageSourceGetType(source),
              let format = imageFormat(for: type as String) else { return nil }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        let relative = path.hasPrefix(rootPath + "/") ? String(path.dropFirst(rootPath.count + 1)) : url.lastPathComponent
        return DiscoveredImage(sourceURL: url, rootURL: root, relativePath: relative, format: format, byteCount: size)
    }

    private func imageFormat(for type: String) -> ImageFormat? {
        if UTType(type)?.conforms(to: .jpeg) == true { return .jpeg }
        if UTType(type)?.conforms(to: .png) == true { return .png }
        if UTType(type)?.conforms(to: .tiff) == true { return .tiff }
        if type == "org.webmproject.webp" { return .webp }
        if type == "public.avif" || type == "public.avci" { return .avif }
        if type == "public.heic" || type == "public.heif" || type == "public.heics" { return .heic }
        return nil
    }
}
