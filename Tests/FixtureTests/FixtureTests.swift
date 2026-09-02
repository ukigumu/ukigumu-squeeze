import CryptoKit
import Foundation
import ImageIO
import Testing
@testable import UkigumuSqueezeCore

@Suite("Approved fixture corpus")
struct FixtureTests {
    @Test("Manifest checksums match committed downloaded fixtures")
    func checksums() throws {
        let root = fixtureRoot
        let data = try Data(contentsOf: root.appending(path: "fixtures-manifest.json"))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let fixtures = try #require(object["downloadedFixtures"] as? [[String: Any]])
        #expect(!fixtures.isEmpty)
        for fixture in fixtures {
            let path = try #require(fixture["path"] as? String)
            let expected = try #require(fixture["sha256"] as? String)
            let bytes = try Data(contentsOf: root.appending(path: path))
            #expect(SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() == expected)
        }
    }

    @Test("All requested source formats are discovered by content")
    func formats() {
        let images = FileDiscovery().discover(at: [fixtureRoot.appending(path: "Sources")])
        let formats = Set(images.map(\.format))
        #expect(formats.isSuperset(of: [.webp, .jpeg, .png, .avif, .heic, .tiff]))
    }

    @Test("Corrupt fixtures do not stop discovery")
    func corrupt() {
        let results = FileDiscovery().discover(at: [fixtureRoot.appending(path: "Corrupt")])
        #expect(results.allSatisfy { $0.sourceURL.lastPathComponent == "truncated.jpg" })
        #expect(results.count <= 1)
    }

    @Test(arguments: [ImageFormat.avif, .heic])
    func nativeEncoderCapability(format: ImageFormat) throws {
        let writable = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        let identifier = format == .avif ? "public.avif" : "public.heic"
        #expect(writable.contains(identifier), "The current runtime must expose the \(format.rawValue) encoder")
    }

    private var fixtureRoot: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "TestFixtures")
    }
}
