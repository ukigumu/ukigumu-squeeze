import ImageIO
import XCTest

final class UkigumuSqueezeEndToEndTests: UkigumuSqueezeUITestCase {
    func testCompressionWithoutDestination() throws {
        let source = try copyFixture("Sources/Synthetic/gradient.png", named: "nested/photo.png")
        launch(inputs: [temporaryRoot])
        compressAndWait(expectedCount: 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testWebPWithoutDestination() throws {
        let source = try copyFixture("Sources/Synthetic/gradient.png", named: "photo.png")
        launch(inputs: [source], format: "webp")
        compressAndWait(expectedCount: 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: temporaryRoot.appending(path: "photo.webp").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: temporaryRoot.appending(path: "original/photo.png").path))
    }

    func testProcessingWithDestination() throws {
        let source = try copyFixture("Sources/Synthetic/gradient.png")
        let destination = try makeDestination()
        launch(inputs: [source], destination: destination)
        compressAndWait(expectedCount: 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appending(path: "gradient.png").path))
    }

    func testJPEGToWebP() throws {
        try assertConversion("Sources/Synthetic/solid.jpg", format: "webp", output: "solid.webp")
    }

    func testPNGToAVIF() throws {
        try assertConversion("Sources/Synthetic/transparent.png", format: "avif", output: "transparent.avif")
    }

    func testHEICToJPEG() throws {
        try assertConversion("Sources/HEIC/colors.heic", format: "jpeg", output: "colors.jpg")
    }

    func testTIFFToPNG() throws {
        try assertConversion("Sources/TIFF/simple.tiff", format: "png", output: "simple.png")
    }

    func testWebPToJPEG() throws {
        try assertConversion("Sources/WebP/official-test.webp", format: "jpeg", output: "official-test.jpg")
    }

    func testAVIFToPNG() throws {
        try assertConversion("Sources/AVIF/alpha.avif", format: "png", output: "alpha.png")
    }

    func testCancellation() throws {
        var inputs: [URL] = []
        for index in 0..<80 {
            inputs.append(try copyFixture("Metadata/exif-xmp-icc.jpg", named: "many/\(index).jpg"))
        }
        let destination = try makeDestination()
        launch(inputs: [temporaryRoot.appending(path: "many")], destination: destination, format: "webp")
        app.buttons["compressButton"].click()
        XCTAssertTrue(app.buttons["cancelButton"].waitForExistence(timeout: 2))
        app.buttons["cancelButton"].click()
        let predicate = NSPredicate { _, _ in
            FileManager.default.fileExists(atPath: self.completionSentinel.path)
        }
        XCTAssertEqual(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: app)], timeout: 20),
            .completed
        )
    }

    func testPartialErrors() throws {
        _ = try copyFixture("Sources/Synthetic/gradient.png", named: "mixed/valid.png")
        _ = try copyFixture("Corrupt/truncated.jpg", named: "mixed/broken.jpg")
        let destination = try makeDestination()
        launch(inputs: [temporaryRoot.appending(path: "mixed")], destination: destination, format: "jpeg")
        compressAndWait(expectedCount: 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appending(path: "valid.jpg").path))
    }

    func testPreserveMetadata() throws {
        let output = try metadataConversion(preserve: true)
        let properties = imageProperties(output)
        XCTAssertNotNil(properties[kCGImagePropertyExifDictionary])
    }

    func testRemoveMetadata() throws {
        let output = try metadataConversion(preserve: false)
        let properties = imageProperties(output)
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        XCTAssertNil(exif?[kCGImagePropertyExifDateTimeOriginal])
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
        XCTAssertNil(properties[kCGImagePropertyIPTCDictionary])
    }

    func testJSONExport() throws {
        let source = try copyFixture("Sources/Synthetic/gradient.png")
        let destination = try makeDestination()
        launch(inputs: [source], destination: destination, exportJSON: true)
        compressAndWait(expectedCount: 1)
        let json = destination.appending(path: "ukigumu-squeeze-metadata.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: json.path))
        XCTAssertFalse(try String(contentsOf: json, encoding: .utf8).contains(temporaryRoot.path))
    }

    func testExistingDestinationIsOverwritten() throws {
        let source = try copyFixture("Sources/Synthetic/gradient.png")
        let destination = try makeDestination()
        try Data("occupied".utf8).write(to: destination.appending(path: "gradient.png"))
        launch(inputs: [source], destination: destination)
        compressAndWait(expectedCount: 1)
        XCTAssertNotEqual(try Data(contentsOf: destination.appending(path: "gradient.png")), Data("occupied".utf8))
    }

    private func assertConversion(_ fixture: String, format: String, output: String) throws {
        let source = try copyFixture(fixture)
        let destination = try makeDestination()
        launch(inputs: [source], destination: destination, format: format)
        compressAndWait(expectedCount: 1)
        let outputURL = destination.appending(path: output)
        XCTAssertNotNil(CGImageSourceCreateWithURL(outputURL as CFURL, nil))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    private func metadataConversion(preserve: Bool) throws -> URL {
        let source = try copyFixture("Metadata/exif-xmp-icc.jpg")
        let destination = try makeDestination()
        launch(inputs: [source], destination: destination, format: "jpeg", preserveMetadata: preserve)
        compressAndWait(expectedCount: 1)
        return destination.appending(path: "exif-xmp-icc.jpg")
    }

    private func imageProperties(_ url: URL) -> [CFString: Any] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return [:] }
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
    }
}
