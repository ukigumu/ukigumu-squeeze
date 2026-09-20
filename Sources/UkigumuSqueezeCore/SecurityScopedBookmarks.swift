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
        urls.forEach(begin)
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

public final class SecurityScopedBookmarkStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let inputKey = "securityScopedInputBookmarks"
    private let destinationKey = "securityScopedDestinationBookmark"
    private var accessedURLs: [URL] = []

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

    public func access(_ url: URL) {
        guard !accessedURLs.contains(where: { $0.standardizedFileURL == url.standardizedFileURL }) else { return }
        if url.startAccessingSecurityScopedResource() {
            accessedURLs.append(url)
        }
    }

    public func stopAccessingAll() {
        accessedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
        accessedURLs.removeAll()
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
