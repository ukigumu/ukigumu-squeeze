import Foundation

public actor BatchProcessor {
    private var task: Task<[ProcessingResult], Never>?

    public init() {}

    public func process(
        plans: [PlannedOutput],
        options: ProcessingOptions,
        maximumConcurrentTasks: Int = max(2, min(ProcessInfo.processInfo.activeProcessorCount, 6)),
        progress: @escaping @MainActor @Sendable (ProcessingResult) -> Void
    ) async -> [ProcessingResult] {
        let processor = ImageProcessor()
        let operation = Task {
            await withTaskGroup(of: ProcessingResult.self, returning: [ProcessingResult].self) { group in
                var iterator = plans.makeIterator()
                var results: [ProcessingResult] = []
                for _ in 0..<min(maximumConcurrentTasks, plans.count) {
                    if let plan = iterator.next() {
                        group.addTask { await processor.process(plan, options: options) }
                    }
                }
                while let result = await group.next() {
                    results.append(result)
                    await progress(result)
                    if !Task.isCancelled, let plan = iterator.next() {
                        group.addTask { await processor.process(plan, options: options) }
                    }
                }
                return results.sorted {
                    $0.originalRelativePath.localizedStandardCompare($1.originalRelativePath) == .orderedAscending
                }
            }
        }
        task = operation
        let results = await operation.value
        task = nil
        return results
    }

    public func cancel() {
        task?.cancel()
    }
}
