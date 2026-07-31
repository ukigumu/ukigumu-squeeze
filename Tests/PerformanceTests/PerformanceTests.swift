import Foundation
import XCTest
@testable import GrumpySqueezeCore

final class PerformanceTests: XCTestCase {
    func testDiscoverFiveThousandFilesBaseline() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fixture = repositoryRoot.appending(path: "TestFixtures/Sources/Synthetic/gradient.png")
        let data = try Data(contentsOf: fixture)
        for index in 0..<5_000 {
            let directory = root.appending(path: "group-\(index % 50)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appending(path: "image-\(index).png"))
        }
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            XCTAssertEqual(FileDiscovery().discover(at: [root]).count, 5_000)
        }
    }

    func testDeterministicJSONBaseline() throws {
        let results = (0..<10_000).map { index in
            ProcessingResult(
                id: UUID(),
                originalRelativePath: "group/image-\(index).png",
                finalRelativePath: "group/image-\(index).webp",
                originalName: "image-\(index).png",
                finalName: "image-\(index).webp",
                originalFormat: .png,
                finalFormat: .webp,
                width: 100,
                height: 100,
                originalBytes: 1_000,
                finalBytes: 700,
                metadataAvailable: false,
                status: .completed,
                error: nil
            )
        }
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            _ = try? JSONEncoder().encode(MetadataReport(
                results: results,
                options: ProcessingOptions(outputFormat: .webp)
            ))
        }
    }

    func testBatchProcessingAndProgressBaseline() throws {
        let sourceRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: sourceRoot) }
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        let data = try Data(contentsOf: repositoryRoot.appending(path: "TestFixtures/Sources/Synthetic/gradient.png"))
        for index in 0..<100 {
            try data.write(to: sourceRoot.appending(path: "image-\(index).png"))
        }
        let images = FileDiscovery().discover(at: [sourceRoot])

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            let destination = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            let options = ProcessingOptions(outputFormat: .webp, destinationURL: destination)
            let plans = try! OutputPlanner().plan(images: images, options: options)
            let completed = expectation(description: "batch")
            let progress = ProgressCounter()
            Task {
                let results = await BatchProcessor().process(plans: plans, options: options) { _ in
                    progress.value += 1
                }
                let progressCount = await MainActor.run { progress.value }
                XCTAssertEqual(results.count, 100)
                XCTAssertEqual(progressCount, 100)
                completed.fulfill()
            }
            wait(for: [completed], timeout: 30)
            try? FileManager.default.removeItem(at: destination)
        }
    }

    private var repositoryRoot: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

@MainActor
private final class ProgressCounter {
    var value = 0
}
