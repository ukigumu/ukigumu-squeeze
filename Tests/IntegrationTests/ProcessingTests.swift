import Foundation
import ImageIO
import Testing
@testable import UkigumuSqueezeCore

@Suite("Safe processing")
struct ProcessingTests {
    @Test("Without destination moves original and writes a valid replacement")
    func inPlaceProcessing() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "nested/photo.png")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try makePNG(at: source, width: 20, height: 12)
        let image = try #require(FileDiscovery().discover(at: [root]).first)
        let options = ProcessingOptions(quality: 0.5, outputFormat: .jpeg, preserveMetadata: false)
        let plan = try #require(OutputPlanner().plan(images: [image], options: options).first)

        let result = await ImageProcessor().process(plan, options: options)

        #expect(result.status == .completed)
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "original/nested/photo.png").path))
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "nested/photo.jpg").path))
        #expect(!FileManager.default.fileExists(atPath: source.path))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: source.deletingLastPathComponent().path)
        #expect(!leftovers.contains { $0.hasPrefix(".ukigumu-squeeze-") })
    }

    @Test("Destination leaves source untouched")
    func destinationProcessing() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let destination = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: destination)
        }
        let source = root.appending(path: "photo.png")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try makePNG(at: source, width: 10, height: 10)
        try Data("existing output".utf8).write(to: destination.appending(path: "photo.jpg"))
        let image = try #require(FileDiscovery().discover(at: [root]).first)
        let options = ProcessingOptions(outputFormat: .jpeg, destinationURL: destination)
        let plan = try #require(OutputPlanner().plan(images: [image], options: options).first)

        let result = await ImageProcessor().process(plan, options: options)

        #expect(result.status == .completed)
        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(FileManager.default.fileExists(atPath: destination.appending(path: "photo.jpg").path))
        #expect(try Data(contentsOf: destination.appending(path: "photo.jpg")) != Data("existing output".utf8))
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "original").path))
    }

    @Test("WebP conversion uses the bundled local encoder")
    func webPEncoding() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let destination = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try makePNG(at: root.appending(path: "photo.png"), width: 17, height: 13)
        let image = try #require(FileDiscovery().discover(at: [root]).first)
        let options = ProcessingOptions(outputFormat: .webp, destinationURL: destination)
        let plan = try #require(OutputPlanner().plan(images: [image], options: options).first)

        let result = await ImageProcessor().process(plan, options: options)
        let output = destination.appending(path: "photo.webp")
        let decoded = CGImageSourceCreateWithURL(output as CFURL, nil)

        #expect(result.status == .completed)
        #expect(CGImageSourceGetType(try #require(decoded)) as String? == "org.webmproject.webp")
    }

    @Test("Specific width resizes with automatic height")
    func automaticHeightResize() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let destination = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try makePNG(at: root.appending(path: "photo.png"), width: 400, height: 300)
        let image = try #require(FileDiscovery().discover(at: [root]).first)
        let options = ProcessingOptions(
            outputFormat: .webp,
            destinationURL: destination,
            resolutionMode: .customWidth,
            resolutionWidth: 120
        )
        let plan = try #require(OutputPlanner().plan(images: [image], options: options).first)

        let result = await ImageProcessor().process(plan, options: options)
        let output = try #require(CGImageSourceCreateWithURL(
            destination.appending(path: "photo.webp") as CFURL, nil
        ))
        let resized = try #require(CGImageSourceCreateImageAtIndex(output, 0, nil))

        #expect(result.status == .completed)
        #expect(result.width == 120)
        #expect(result.height == 90)
        #expect(resized.width == 120)
        #expect(resized.height == 90)
    }

    @Test("Existing WebP can be resized and encoded back to WebP")
    func webPToWebPResize() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let destination = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fixture = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "TestFixtures/Sources/WebP/official-test.webp")
        try FileManager.default.copyItem(at: fixture, to: root.appending(path: "photo.webp"))
        let image = try #require(FileDiscovery().discover(at: [root]).first)
        let options = ProcessingOptions(
            outputFormat: .webp,
            destinationURL: destination,
            resolutionMode: .fit,
            resolutionWidth: 64,
            resolutionHeight: 64
        )
        let plan = try #require(OutputPlanner().plan(images: [image], options: options).first)

        let result = await ImageProcessor().process(plan, options: options)

        #expect(result.status == .completed, "\(result.error ?? "Unknown processing error")")
        #expect(result.width == 64)
        #expect(result.height == 64)
    }

    @Test("Existing WebP can be resized in its original location")
    func inPlaceWebPResize() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fixture = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "TestFixtures/Sources/WebP/official-test.webp")
        try FileManager.default.copyItem(at: fixture, to: root.appending(path: "photo.webp"))
        try FileManager.default.createDirectory(
            at: root.appending(path: "original"),
            withIntermediateDirectories: true
        )
        try Data("previous backup".utf8).write(to: root.appending(path: "original/photo.webp"))
        let image = try #require(FileDiscovery().discover(at: [root]).first)
        let options = ProcessingOptions(
            resolutionMode: .fit,
            resolutionWidth: 64,
            resolutionHeight: 64
        )
        let plan = try #require(OutputPlanner().plan(images: [image], options: options).first)

        let result = await ImageProcessor().process(plan, options: options)

        #expect(result.status == .completed, "\(result.error ?? "Unknown processing error")")
        #expect(
            try Data(contentsOf: root.appending(path: "original/photo.webp"))
                == Data(contentsOf: fixture)
        )
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "photo.webp").path))
    }

    @Test("Multipage TIFF keeps every page when output remains TIFF")
    func multipageTIFF() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let destination = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appending(path: "pages.tiff")
        try makeTIFF(at: source, pageCount: 3)
        let image = try #require(FileDiscovery().discover(at: [root]).first)
        let options = ProcessingOptions(outputFormat: .tiff, destinationURL: destination)
        let plan = try #require(OutputPlanner().plan(images: [image], options: options).first)

        let result = await ImageProcessor().process(plan, options: options)
        let output = try #require(CGImageSourceCreateWithURL(
            destination.appending(path: "pages.tiff") as CFURL, nil
        ))

        #expect(result.status == .completed)
        #expect(CGImageSourceGetCount(output) == 3)
    }

    @Test("Destination leaves source video untouched")
    func destinationVideoProcessing() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let destination = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: videoFixture, to: root.appending(path: "clip.mp4"))
        let item = try #require(FileDiscovery().discover(at: [root]).first)
        #expect(item.format == .mp4)
        let options = ProcessingOptions(quality: 0.35, outputFormat: .mp4, destinationURL: destination)
        let plan = try #require(OutputPlanner().plan(images: [item], options: options).first)

        let result = await VideoProcessor().process(plan, options: options)

        #expect(result.status == .completed, "\(result.error ?? "Unknown processing error")")
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "clip.mp4").path))
        #expect(FileManager.default.fileExists(atPath: destination.appending(path: "clip.mp4").path))
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "original").path))
        #expect(result.finalFormat == .mp4)
        #expect(result.finalBytes > 0)
    }

    @Test("Without destination moves original video and writes a replacement")
    func inPlaceVideoProcessing() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appending(path: "nested/clip.mp4")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: videoFixture, to: source)
        let item = try #require(FileDiscovery().discover(at: [root]).first)
        let options = ProcessingOptions(quality: 0.35, outputFormat: .mp4)
        let plan = try #require(OutputPlanner().plan(images: [item], options: options).first)

        let result = await VideoProcessor().process(plan, options: options)

        #expect(result.status == .completed, "\(result.error ?? "Unknown processing error")")
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "original/nested/clip.mp4").path))
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "nested/clip.mp4").path))
        #expect(try Data(contentsOf: root.appending(path: "original/nested/clip.mp4")) == Data(contentsOf: videoFixture))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: source.deletingLastPathComponent().path)
        #expect(!leftovers.contains { $0.hasPrefix(".ukigumu-squeeze-") })
    }

    @Test("Mixed photo and video batch keeps each media on its path")
    func mixedBatch() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let destination = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try makePNG(at: root.appending(path: "photo.png"), width: 16, height: 12)
        try FileManager.default.copyItem(at: videoFixture, to: root.appending(path: "clip.mp4"))
        let items = FileDiscovery().discover(at: [root])
        #expect(items.count == 2)
        let options = ProcessingOptions(quality: 0.4, outputFormat: .jpeg, destinationURL: destination)
        let plans = try OutputPlanner().plan(images: items, options: options)

        let results = await BatchProcessor().process(plans: plans, options: options) { _ in }

        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.status == .completed }, results.map { $0.error ?? $0.status.rawValue }.joined())
        #expect(FileManager.default.fileExists(atPath: destination.appending(path: "photo.jpg").path))
        #expect(FileManager.default.fileExists(atPath: destination.appending(path: "clip.mp4").path))
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "photo.png").path))
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "clip.mp4").path))
    }

    @Test("Video can be resized with the same resolution controls as photos")
    func videoResize() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let destination = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: videoFixture, to: root.appending(path: "clip.mp4"))
        let item = try #require(FileDiscovery().discover(at: [root]).first)
        let options = ProcessingOptions(
            quality: 0.5,
            outputFormat: .mp4,
            destinationURL: destination,
            resolutionMode: .half
        )
        let plan = try #require(OutputPlanner().plan(images: [item], options: options).first)

        let result = await VideoProcessor().process(plan, options: options)

        #expect(result.status == .completed, "\(result.error ?? "Unknown processing error")")
        #expect(result.width == 64)
        #expect(result.height == 48)
    }

    private var videoFixture: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "TestFixtures/Sources/Video/solid.mp4")
    }

    private func makePNG(at url: URL, width: Int, height: Int) throws {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let image = context.makeImage()!
        let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }

    private func makeTIFF(at url: URL, pageCount: Int) throws {
        let destination = CGImageDestinationCreateWithURL(
            url as CFURL, "public.tiff" as CFString, pageCount, nil
        )!
        for index in 0..<pageCount {
            let context = CGContext(
                data: nil, width: 8 + index, height: 6 + index,
                bitsPerComponent: 8, bytesPerRow: (8 + index) * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        }
        #expect(CGImageDestinationFinalize(destination))
    }
}
