import Foundation

enum TemporaryOutput {
    static func url(adjacentTo outputURL: URL) -> URL {
        outputURL.deletingLastPathComponent()
            .appending(path: ".ukigumu-squeeze-\(UUID().uuidString).tmp")
    }
}

enum OutputCommitter {
    static func commit(temporary: URL, plan: PlannedOutput, fileManager: FileManager) throws {
        if let backup = plan.backupURL {
            try fileManager.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: backup.path) {
                try fileManager.removeItem(at: backup)
            }
            try fileManager.moveItem(at: plan.image.sourceURL, to: backup)
            do {
                if plan.outputURL != plan.image.sourceURL,
                   fileManager.fileExists(atPath: plan.outputURL.path) {
                    try fileManager.removeItem(at: plan.outputURL)
                }
                try fileManager.moveItem(at: temporary, to: plan.outputURL)
            } catch {
                try? fileManager.moveItem(at: backup, to: plan.image.sourceURL)
                throw error
            }
        } else {
            if fileManager.fileExists(atPath: plan.outputURL.path) {
                _ = try fileManager.replaceItemAt(plan.outputURL, withItemAt: temporary)
            } else {
                try fileManager.moveItem(at: temporary, to: plan.outputURL)
            }
        }
    }
}
