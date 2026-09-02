import Foundation

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
