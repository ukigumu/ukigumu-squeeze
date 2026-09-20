import Foundation

/// Holds `startAccessingSecurityScopedResource()` until `stop()` or deinit.
///
/// App Sandbox grants dropped or panel-chosen URLs only for as long as this
/// access stays alive. `AVAssetExportSession.exportAsynchronously` re-opens
/// the file later, so the token must outlive that callback, not just the
/// call that created `AVURLAsset`.
public final class SecurityScopedAccess: @unchecked Sendable {
    private var accessed: [URL] = []
    private var seen = Set<String>()
    private let lock = NSLock()

    public init(urls: [URL]) {
        for url in urls {
            _ = begin(url)
        }
    }

    deinit {
        stop()
    }

    /// Starts access on `url` if it is new. Uses the original URL object so
    /// the security-scope payload is not stripped by standardization.
    @discardableResult
    public func begin(_ url: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let key = url.standardizedFileURL.path
        guard seen.insert(key).inserted else { return accessed.contains { $0.standardizedFileURL.path == key } }
        guard url.startAccessingSecurityScopedResource() else { return false }
        accessed.append(url)
        return true
    }

    public var accessedURLs: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return accessed
    }

    public func covers(_ url: URL) -> Bool {
        SandboxAccessProbe.isCovered(url, by: accessedURLs)
    }

    public func stop() {
        lock.lock()
        let urls = accessed
        accessed.removeAll()
        seen.removeAll()
        lock.unlock()
        urls.forEach { $0.stopAccessingSecurityScopedResource() }
    }

    /// Source, folder root, destination, output parent, and `original/` paths
    /// that encode, temp write, commit, and backup all need to read or write.
    public static func urls(for plan: PlannedOutput, destination: URL?) -> [URL] {
        var collected = [
            plan.image.sourceURL,
            plan.image.rootURL,
            plan.outputURL,
            plan.outputURL.deletingLastPathComponent()
        ]
        if let destination {
            collected.append(destination)
        }
        if let backup = plan.backupURL {
            collected.append(backup)
            collected.append(backup.deletingLastPathComponent())
        }
        var unique: [URL] = []
        var keys = Set<String>()
        for url in collected {
            let key = url.standardizedFileURL.path
            if keys.insert(key).inserted {
                unique.append(url)
            }
        }
        return unique
    }
}

public enum FolderAccessPromptCopy: Sendable {
    public static let message = "Ukigumu Squeeze needs access to this folder to compress videos locally."
    public static let confirm = "Allow Access"
    public static let cancelled =
        "Folder access was cancelled. Ukigumu Squeeze needs access to this folder to compress videos locally. Choose the folder with Choose files… and try again."
}

public enum SandboxAccessProbe: Sendable {
    public static func isCovered(_ url: URL, by granted: [URL]) -> Bool {
        let path = url.standardizedFileURL.path
        return granted.contains { candidate in
            let grantedPath = candidate.standardizedFileURL.path
            return path == grantedPath || path.hasPrefix(grantedPath + "/")
        }
    }

    public static func requiredFolders(for plan: PlannedOutput, destination: URL?) -> [URL] {
        var folders = [plan.image.rootURL]
        if let destination {
            folders.append(destination)
        }
        var unique: [URL] = []
        var keys = Set<String>()
        for folder in folders {
            let key = folder.standardizedFileURL.path
            if keys.insert(key).inserted {
                unique.append(folder)
            }
        }
        return unique
    }

    /// Folders that still need a user grant. A dropped file covers that file
    /// for read, not its parent, so in-place encode still asks for the folder.
    public static func foldersNeedingGrant(
        plans: [PlannedOutput],
        destination: URL?,
        covered: [URL]
    ) -> [URL] {
        var needed: [URL] = []
        var keys = Set<String>()
        for plan in plans {
            let source = plan.image.sourceURL
            let root = plan.image.rootURL
            if !isCovered(source, by: covered), !isCovered(root, by: covered) {
                appendUnique(root, to: &needed, keys: &keys)
            }
            let writeFolder = destination ?? root
            if !isCovered(writeFolder, by: covered) {
                appendUnique(writeFolder, to: &needed, keys: &keys)
            }
        }
        return needed
    }

    public static func plans(
        _ plans: [PlannedOutput],
        requiring folder: URL,
        destination: URL?
    ) -> [PlannedOutput] {
        plans.filter { plan in
            requiredFolders(for: plan, destination: destination).contains {
                isCovered($0, by: [folder]) || isCovered(folder, by: [$0])
            }
        }
    }

    private static func appendUnique(_ url: URL, to urls: inout [URL], keys: inout Set<String>) {
        let key = url.standardizedFileURL.path
        if keys.insert(key).inserted {
            urls.append(url)
        }
    }
}

/// Asks at most once per folder root. A grant on a parent covers children.
/// A denial on a parent skips child prompts.
public actor FolderAccessDecisionCache {
    private enum Outcome {
        case granted(URL)
        case denied
    }

    private var outcomes: [String: Outcome] = [:]
    private var inflight: [String: Task<URL?, Never>] = [:]

    public init() {}

    public func decision(
        for folder: URL,
        prompt: @escaping @Sendable (URL) async -> URL?
    ) async -> URL? {
        let key = folder.standardizedFileURL.path
        if let granted = grantedCovering(key) {
            return granted
        }
        if deniedCovering(key) {
            return nil
        }
        if let task = inflight[key] {
            return await task.value
        }
        let task = Task {
            return await prompt(folder)
        }
        inflight[key] = task
        let result = await task.value
        if let result {
            outcomes[key] = Outcome.granted(result)
        } else {
            outcomes[key] = Outcome.denied
        }
        inflight[key] = nil
        return result
    }

    public func isDenied(_ folder: URL) -> Bool {
        return deniedCovering(folder.standardizedFileURL.path)
    }

    private func grantedCovering(_ path: String) -> URL? {
        for (grantedPath, outcome) in outcomes {
            if case .granted(let url) = outcome,
               path == grantedPath || path.hasPrefix(grantedPath + "/") {
                return url
            }
        }
        return nil
    }

    private func deniedCovering(_ path: String) -> Bool {
        return outcomes.contains { deniedPath, outcome in
            switch outcome {
            case .denied:
                return path == deniedPath || path.hasPrefix(deniedPath + "/")
            case .granted:
                return false
            }
        }
    }
}

public final class SecurityScopedBookmarkStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let inputKey = "securityScopedInputBookmarks"
    private let destinationKey = "securityScopedDestinationBookmark"
    private let grantedFolderKey = "securityScopedGrantedFolders"
    private var storedAccessedURLs: [URL] = []
    private let lock = NSLock()

    public var accessedURLs: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return storedAccessedURLs
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    deinit {
        stopAccessingAll()
    }

    public func saveInputs(_ urls: [URL]) throws {
        defaults.set(try urls.map(makeBookmark), forKey: inputKey)
    }

    public func saveDestination(_ url: URL?) throws {
        defaults.set(try url.map(makeBookmark), forKey: destinationKey)
    }

    public func restoreInputs() -> [URL] {
        let bookmarks = defaults.array(forKey: inputKey) as? [Data] ?? []
        return bookmarks.compactMap(resolveAndAccess)
    }

    public func restoreDestination() -> URL? {
        guard let bookmark = defaults.data(forKey: destinationKey) else { return nil }
        return resolveAndAccess(bookmark)
    }

    /// Resolves stored bookmarks (or starts access on the live URLs) so
    /// `AVURLAsset` and export see scoped file URLs, not path-only copies.
    public func resolveInputs(_ urls: [URL]) -> [URL] {
        let restored = restoreInputs()
        if !restored.isEmpty { return restored }
        urls.forEach(access)
        return urls
    }

    public func resolveDestination(_ url: URL?) -> URL? {
        if let restored = restoreDestination() { return restored }
        url.map(access)
        return url
    }

    public func restoreGrantedFolders() -> [URL] {
        let bookmarks = defaults.array(forKey: grantedFolderKey) as? [Data] ?? []
        return bookmarks.compactMap(resolveAndAccess)
    }

    public func rememberGrantedFolder(_ url: URL) throws {
        access(url)
        var folders = restoreGrantedFolders()
        if !folders.contains(where: { $0.standardizedFileURL.path == url.standardizedFileURL.path }) {
            folders.append(url)
        }
        defaults.set(try folders.map(makeBookmark), forKey: grantedFolderKey)
    }

    public func covers(_ url: URL) -> Bool {
        SandboxAccessProbe.isCovered(url, by: accessedURLs)
    }

    public func access(_ url: URL) {
        lock.lock()
        let already = storedAccessedURLs.contains { $0.standardizedFileURL == url.standardizedFileURL }
        lock.unlock()
        guard !already else { return }
        if url.startAccessingSecurityScopedResource() {
            lock.lock()
            storedAccessedURLs.append(url)
            lock.unlock()
        }
    }

    public func stopAccessingAll() {
        lock.lock()
        let urls = storedAccessedURLs
        storedAccessedURLs.removeAll()
        lock.unlock()
        urls.forEach { $0.stopAccessingSecurityScopedResource() }
    }

    private func makeBookmark(_ url: URL) throws -> Data {
        try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private func resolveAndAccess(_ data: Data) -> URL? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        access(url)
        if isStale {
            // The caller's next save refreshes stale bookmark data.
            return url
        }
        return url
    }
}
