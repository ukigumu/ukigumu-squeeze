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
            return makeMedia(input, root: root).map { [$0] } ?? []
        }

        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: input,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var items: [DiscoveredImage] = []
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
            if let item = makeMedia(url, root: root) { items.append(item) }
        }
        return items
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

    private func makeMedia(_ url: URL, root: URL) -> DiscoveredImage? {
        if let videoFormat = VideoContainerSniffer.format(of: url) {
            return makeItem(url, root: root, format: videoFormat)
        }
        if let image = makeImage(url, root: root) {
            return image
        }
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
           let videoFormat = videoFormat(for: type, pathExtension: url.pathExtension) {
            return makeItem(url, root: root, format: videoFormat)
        }
        return nil
    }

    private func makeImage(_ url: URL, root: URL) -> DiscoveredImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let type = CGImageSourceGetType(source),
              let format = imageFormat(for: type as String) else { return nil }
        return makeItem(url, root: root, format: MediaFormat(format))
    }

    private func makeItem(_ url: URL, root: URL, format: MediaFormat) -> DiscoveredImage {
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

    private func videoFormat(for type: UTType, pathExtension: String) -> MediaFormat? {
        if type.conforms(to: .image) || type.conforms(to: .audio) { return nil }
        if type.identifier == "com.apple.m4v-video" || pathExtension.lowercased() == "m4v" && type.conforms(to: .movie) {
            return .m4v
        }
        if type.conforms(to: .mpeg4Movie) { return pathExtension.lowercased() == "m4v" ? .m4v : .mp4 }
        if type.conforms(to: .quickTimeMovie) { return .mov }
        if type.identifier == "public.avi" { return .avi }
        if type.conforms(to: .mpeg) || type.identifier == "public.mpeg-2-video" { return .mpeg }
        if type.conforms(to: .movie) || type.conforms(to: .audiovisualContent) {
            return MediaFormat.from(extension: pathExtension) ?? .mp4
        }
        return MediaFormat.from(extension: pathExtension).flatMap { $0.kind == .video ? $0 : nil }
    }
}

public enum VideoContainerSniffer: Sendable {
    public static func format(of url: URL) -> MediaFormat? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 16), !header.isEmpty else { return nil }
        return format(header: header, pathExtension: url.pathExtension)
    }

    public static func format(header: Data, pathExtension: String = "") -> MediaFormat? {
        if header.count >= 12 {
            let boxType = header.subdata(in: 4..<8)
            if boxType == Data("ftyp".utf8) {
                let brand = String(data: header.subdata(in: 8..<12), encoding: .ascii) ?? ""
                if brand.hasPrefix("M4A") { return nil }
                if brand.hasPrefix("qt") { return .mov }
                if brand.hasPrefix("M4V") { return .m4v }
                return pathExtension.lowercased() == "m4v" ? .m4v : .mp4
            }
        }
        if header.count >= 12,
           header.starts(with: Data("RIFF".utf8)),
           header.subdata(in: 8..<12) == Data("AVI ".utf8) {
            return .avi
        }
        if header.count >= 4,
           header[0] == 0, header[1] == 0, header[2] == 1,
           header[3] == 0xBA || header[3] == 0xB3 {
            return .mpeg
        }
        return nil
    }
}
