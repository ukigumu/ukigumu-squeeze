import AppKit
#if canImport(UkigumuSqueezeCore)
import UkigumuSqueezeCore
#endif
import Observation

@MainActor
@Observable
final class AppModel {
    var inputs: [URL] = []
    var items: [DiscoveredImage] = []
    var results: [UUID: ProcessingResult] = [:]
    var quality = 0.8
    var outputFormat = OutputFormat.original
    var preserveMetadata = true
    var exportJSON = false
    var resolutionMode = ResolutionMode.original
    var resolutionWidth = 1920
    var resolutionHeight = 1080
    var videoPreset = VideoPreset.fast1080p
    var videoResolutionCap = VideoResolutionCap.p1080
    var videoQualityLean = VideoQualityLean.balanced
    var itemProgress: [UUID: Double] = [:]
    var destinationURL: URL?
    var isProcessing = false
    var errorMessage: String?

    private let batchProcessor = BatchProcessor()
    private let bookmarkStore: SecurityScopedBookmarkStore
    private var activeBatchID: UUID?

    init(bookmarkStore: SecurityScopedBookmarkStore = SecurityScopedBookmarkStore()) {
        self.bookmarkStore = bookmarkStore
        let environment = ProcessInfo.processInfo.environment
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            inputs = environment["UKIGUMU_SQUEEZE_TEST_INPUTS"]?
                .split(separator: "\n")
                .map { URL(filePath: String($0)) } ?? []
            destinationURL = environment["UKIGUMU_SQUEEZE_TEST_DESTINATION"].map { URL(filePath: $0) }
            if let format = environment["UKIGUMU_SQUEEZE_TEST_FORMAT"].flatMap(OutputFormat.init(rawValue:)) {
                outputFormat = format
            }
            if let preset = environment["UKIGUMU_SQUEEZE_TEST_VIDEO_PRESET"].flatMap(VideoPreset.init(rawValue:)) {
                videoPreset = preset
            }
            if let cap = environment["UKIGUMU_SQUEEZE_TEST_VIDEO_CAP"].flatMap(VideoResolutionCap.init(rawValue:)) {
                videoResolutionCap = cap
            }
            if let lean = environment["UKIGUMU_SQUEEZE_TEST_VIDEO_LEAN"].flatMap(VideoQualityLean.init(rawValue:)) {
                videoQualityLean = lean
            }
            preserveMetadata = environment["UKIGUMU_SQUEEZE_TEST_PRESERVE_METADATA"] != "0"
            exportJSON = environment["UKIGUMU_SQUEEZE_TEST_EXPORT_JSON"] == "1"
        } else {
            inputs = bookmarkStore.restoreInputs()
            destinationURL = bookmarkStore.restoreDestination()
        }
        refresh()
    }

    var summary: BatchSummary {
        BatchSummary(results: Array(results.values))
    }

    var videoProfile: VideoEncodeProfile {
        videoPreset.profile(customCap: videoResolutionCap, customLean: videoQualityLean)
    }

    func result(for id: UUID) -> ProcessingResult? {
        results[id]
    }

    func itemStatus(for id: UUID) -> ItemStatus {
        if let result = results[id] { return result.status }
        if itemProgress[id] != nil { return .processing }
        return .pending
    }

    func statusTitle(for id: UUID) -> String {
        itemStatus(for: id).displayLabel()
    }

    func statusDetail(for id: UUID) -> String? {
        itemStatus(for: id).displayDetail(error: results[id]?.error)
    }

    func presentStatusDetail(for id: UUID) {
        if let detail = statusDetail(for: id) {
            errorMessage = detail
        }
    }

    func add(_ urls: [URL]) {
        let unique = urls.filter { candidate in
            !inputs.contains { $0.standardizedFileURL == candidate.standardizedFileURL }
        }
        inputs.append(contentsOf: unique)
        urls.forEach(bookmarkStore.access)
        do { try bookmarkStore.saveInputs(inputs) }
        catch { errorMessage = error.localizedDescription }
        adoptResolvedInputs()
        refresh()
    }

    func replaceInputs(with urls: [URL]) {
        if isProcessing {
            Task { await batchProcessor.cancel() }
        }
        activeBatchID = nil
        isProcessing = false
        errorMessage = nil
        inputs = urls.reduce(into: []) { unique, candidate in
            if !unique.contains(where: { $0.standardizedFileURL == candidate.standardizedFileURL }) {
                unique.append(candidate)
            }
        }
        urls.forEach(bookmarkStore.access)
        do { try bookmarkStore.saveInputs(inputs) }
        catch { errorMessage = error.localizedDescription }
        adoptResolvedInputs()
        refresh()
    }

    func chooseInputs() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        if panel.runModal() == .OK { add(panel.urls) }
    }

    func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        if panel.runModal() == .OK {
            destinationURL = panel.url
            panel.url.map(bookmarkStore.access)
            do { try bookmarkStore.saveDestination(panel.url) }
            catch { errorMessage = error.localizedDescription }
            destinationURL = bookmarkStore.resolveDestination(destinationURL)
            refresh()
        }
    }

    func clearDestination() {
        destinationURL = nil
        do { try bookmarkStore.saveDestination(nil) }
        catch { errorMessage = error.localizedDescription }
        refresh()
    }

    func refresh() {
        items = FileDiscovery().discover(at: inputs, excluding: destinationURL)
        results = [:]
        itemProgress = [:]
    }

    func compress() {
        guard !items.isEmpty, !isProcessing else { return }
        resolveSecurityScopedURLs()
        guard !items.isEmpty else { return }
        let batchID = UUID()
        activeBatchID = batchID
        isProcessing = true
        errorMessage = nil
        results = [:]
        itemProgress = [:]
        let options = ProcessingOptions(
            quality: quality,
            outputFormat: outputFormat,
            preserveMetadata: preserveMetadata,
            exportJSON: exportJSON,
            destinationURL: destinationURL,
            resolutionMode: resolutionMode,
            resolutionWidth: resolutionWidth,
            resolutionHeight: resolutionHeight,
            videoPreset: videoPreset,
            videoResolutionCap: videoResolutionCap,
            videoQualityLean: videoQualityLean
        )
        do {
            let planner = OutputPlanner()
            if destinationURL == nil { try planner.validateOriginalFolders(for: items) }
            let plans = try planner.plan(images: items, options: options)
            Task {
                let completed = await batchProcessor.process(
                    plans: plans,
                    options: options,
                    progress: { [weak self] result in
                        guard self?.activeBatchID == batchID else { return }
                        self?.results[result.id] = result
                    },
                    itemProgress: { [weak self] id, fraction in
                        guard self?.activeBatchID == batchID else { return }
                        self?.itemProgress[id] = fraction
                    }
                )
                guard self.activeBatchID == batchID else { return }
                if options.exportJSON {
                    do { try self.writeReports(completed, options: options) }
                    catch { self.errorMessage = error.localizedDescription }
                }
                self.activeBatchID = nil
                self.isProcessing = false
                if ProcessInfo.processInfo.arguments.contains("-ui-testing"),
                   let sentinel = ProcessInfo.processInfo.environment["UKIGUMU_SQUEEZE_TEST_SENTINEL"] {
                    try? Data("\(completed.count)".utf8).write(to: URL(filePath: sentinel), options: .atomic)
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            isProcessing = false
        }
    }

    func cancel() {
        Task { await batchProcessor.cancel() }
    }

    func revealResults() {
        let urls = destinationURL.map { [$0] } ?? Array(Set(items.map(\.rootURL)))
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    private func adoptResolvedInputs() {
        guard !isUITesting else { return }
        let resolved = bookmarkStore.resolveInputs(inputs)
        if !resolved.isEmpty {
            inputs = resolved
        }
    }

    private func resolveSecurityScopedURLs() {
        guard !isUITesting else {
            inputs.forEach(bookmarkStore.access)
            destinationURL.map(bookmarkStore.access)
            return
        }
        inputs = bookmarkStore.resolveInputs(inputs)
        destinationURL = bookmarkStore.resolveDestination(destinationURL)
        items = FileDiscovery().discover(at: inputs, excluding: destinationURL)
    }

    private var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-ui-testing")
    }

    private func writeReports(_ completed: [ProcessingResult], options: ProcessingOptions) throws {
        let roots = destinationURL.map { [$0] } ?? Array(Set(items.map(\.rootURL)))
        for root in roots {
            let relevant = destinationURL != nil
                ? completed
                : completed.filter { result in items.first(where: { $0.id == result.id })?.rootURL == root }
            try MetadataReport(results: relevant, options: options)
                .writeAtomically(to: root.appending(path: "ukigumu-squeeze-metadata.json"))
        }
    }
}
