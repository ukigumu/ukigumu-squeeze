import Foundation
import ImageIO
import Testing
@testable import UkigumuSqueezeCore

@Suite("Core rules")
struct CoreTests {
    @Test("JPG and JPEG map to the same format")
    func jpegEquivalence() {
        #expect(ImageFormat.from(extension: "JPG") == .jpeg)
        #expect(ImageFormat.from(extension: "jpeg") == .jpeg)
    }

    @Test("Keep original preserves the exact extension")
    func exactExtension() throws {
        let image = fixture(relativePath: "Trips/beach.JPEG", format: .jpeg)
        let plan = try OutputPlanner().plan(images: [image], options: ProcessingOptions()).first
        #expect(plan?.relativeOutputPath == "Trips/beach.JPEG")
    }

    @Test("Conversion changes only the extension")
    func conversionExtension() throws {
        let image = fixture(relativePath: "Trips/my.photo.JPEG", format: .jpeg)
        let options = ProcessingOptions(outputFormat: .png)
        let plan = try OutputPlanner().plan(images: [image], options: options).first
        #expect(plan?.relativeOutputPath == "Trips/my.photo.png")
    }

    @Test("Conversion collisions are case insensitive")
    func collisions() {
        let first = fixture(relativePath: "photo.jpg", format: .jpeg)
        let second = fixture(relativePath: "PHOTO.png", format: .png)
        #expect(throws: UkigumuSqueezeError.self) {
            try OutputPlanner().plan(
                images: [first, second],
                options: ProcessingOptions(outputFormat: .webp, destinationURL: URL(filePath: "/tmp/output"))
            )
        }
    }

    @Test("Savings supports growth")
    func savings() {
        #expect(Savings.bytes(original: 100, final: 125) == -25)
        #expect(Savings.percentage(original: 100, final: 125) == -25)
    }

    @Test("Resolution presets preserve aspect ratio and never enlarge")
    func resolutionPresets() {
        #expect(ResolutionCalculator.dimensions(
            sourceWidth: 4000, sourceHeight: 3000,
            mode: .half, width: 1920, height: 1080
        ) == PixelSize(width: 2000, height: 1500))
        #expect(ResolutionCalculator.dimensions(
            sourceWidth: 4000, sourceHeight: 3000,
            mode: .customWidth, width: 1200, height: 1080
        ) == PixelSize(width: 1200, height: 900))
        #expect(ResolutionCalculator.dimensions(
            sourceWidth: 800, sourceHeight: 600,
            mode: .customWidth, width: 1920, height: 1080
        ) == PixelSize(width: 800, height: 600))
    }

    @Test("Fit and exact resolution modes calculate their expected bounds")
    func customResolutionModes() {
        #expect(ResolutionCalculator.dimensions(
            sourceWidth: 4000, sourceHeight: 3000,
            mode: .fit, width: 1000, height: 1000
        ) == PixelSize(width: 1000, height: 750))
        #expect(ResolutionCalculator.dimensions(
            sourceWidth: 4000, sourceHeight: 3000,
            mode: .exact, width: 1000, height: 500
        ) == PixelSize(width: 1000, height: 500))
    }

    @Test("Metadata JSON includes savings and no absolute source paths")
    func metadataJSON() throws {
        let result = ProcessingResult(
            id: UUID(),
            originalRelativePath: "nested/photo.png",
            finalRelativePath: "nested/photo.jpg",
            originalName: "photo.png",
            finalName: "photo.jpg",
            originalFormat: .png,
            finalFormat: .jpeg,
            width: 10,
            height: 10,
            originalBytes: 100,
            finalBytes: 75,
            metadataAvailable: true,
            status: .completed,
            error: nil
        )
        let data = try JSONEncoder().encode(MetadataReport(
            results: [result],
            options: ProcessingOptions(outputFormat: .jpeg),
            date: Date(timeIntervalSince1970: 0)
        ))
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("\"bytesSaved\":25"))
        #expect(json.contains("\"percentageSaved\":25"))
        #expect(!json.contains("/Users/"))
    }

    private func fixture(relativePath: String, format: ImageFormat) -> DiscoveredImage {
        let root = URL(filePath: "/tmp/source")
        return DiscoveredImage(
            sourceURL: root.appending(path: relativePath),
            rootURL: root,
            relativePath: relativePath,
            format: format,
            byteCount: 100
        )
    }
}

@Suite("Discovery")
struct DiscoveryTests {
    @Test("Recurses and excludes original, symlinks, temporaries and generated JSON")
    func exclusions() throws {
        let temporary = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try FileManager.default.createDirectory(at: temporary.appending(path: "nested"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: temporary.appending(path: "original"), withIntermediateDirectories: true)
        try makePNG(at: temporary.appending(path: "nested/valid.PNG"))
        try makePNG(at: temporary.appending(path: "original/ignored.png"))
        try Data("{}".utf8).write(to: temporary.appending(path: "ukigumu-squeeze-metadata.json"))
        try FileManager.default.createSymbolicLink(
            at: temporary.appending(path: "linked.png"),
            withDestinationURL: temporary.appending(path: "nested/valid.PNG")
        )

        let results = FileDiscovery().discover(at: [temporary])
        #expect(results.count == 1)
        #expect(results.first?.relativePath == "nested/valid.PNG")
        #expect(results.first?.format == .png)
    }

    private func makePNG(at url: URL) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let image = context.makeImage()!
        let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }
}

@Suite("Security-scoped bookmarks")
struct BookmarkTests {
    @Test("Selected roots and destination survive store recreation")
    func roundTrip() throws {
        let suiteName = "UkigumuSqueezeTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let firstStore = SecurityScopedBookmarkStore(defaults: defaults)

        try firstStore.saveInputs([root])
        try firstStore.saveDestination(root)
        let restoredStore = SecurityScopedBookmarkStore(defaults: defaults)

        #expect(restoredStore.restoreInputs().first?.standardizedFileURL == root.standardizedFileURL)
        #expect(restoredStore.restoreDestination()?.standardizedFileURL == root.standardizedFileURL)
    }
}
