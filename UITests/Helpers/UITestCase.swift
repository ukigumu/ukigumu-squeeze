import XCTest

class UkigumuSqueezeUITestCase: XCTestCase {
    var app: XCUIApplication!
    var temporaryRoot: URL!
    var completionSentinel: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        temporaryRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        completionSentinel = temporaryRoot.appending(path: ".completed")
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        if testRun?.hasSucceeded == false {
            let screenshot = XCUIScreen.main.screenshot()
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "\(name)-failure"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        app?.terminate()
        if let temporaryRoot { try? FileManager.default.removeItem(at: temporaryRoot) }
    }

    @discardableResult
    func copyFixture(_ relative: String, named name: String? = nil) throws -> URL {
        let source = repositoryRoot.appending(path: "TestFixtures").appending(path: relative)
        let destination = temporaryRoot.appending(path: name ?? source.lastPathComponent)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    func launch(
        inputs: [URL],
        destination: URL? = nil,
        format: String = "original",
        preserveMetadata: Bool = true,
        exportJSON: Bool = false
    ) {
        app.launchArguments = ["-ui-testing"]
        app.launchEnvironment = [
            "UKIGUMU_SQUEEZE_TEST_INPUTS": inputs.map(\.path).joined(separator: "\n"),
            "UKIGUMU_SQUEEZE_TEST_FORMAT": format,
            "UKIGUMU_SQUEEZE_TEST_PRESERVE_METADATA": preserveMetadata ? "1" : "0",
            "UKIGUMU_SQUEEZE_TEST_EXPORT_JSON": exportJSON ? "1" : "0",
            "UKIGUMU_SQUEEZE_TEST_SENTINEL": completionSentinel.path
        ]
        if let destination {
            app.launchEnvironment["UKIGUMU_SQUEEZE_TEST_DESTINATION"] = destination.path
        }
        app.launch()
        XCTAssertTrue(app.buttons["compressButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["compressButton"].isEnabled, "The injected fixtures were not discovered")
    }

    func compressAndWait(expectedCount: Int, timeout: TimeInterval = 20) {
        app.buttons["compressButton"].click()
        let predicate = NSPredicate { _, _ in
            guard let data = try? Data(contentsOf: self.completionSentinel),
                  let count = Int(String(decoding: data, as: UTF8.self)) else { return false }
            return count == expectedCount
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed)
    }

    func makeDestination() throws -> URL {
        let url = temporaryRoot.appending(path: "output")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    var repositoryRoot: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
