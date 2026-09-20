import Foundation

public actor BatchProcessor {
    private var task: Task<[ProcessingResult], Never>?

    public init() {}

    public func process(
        plans: [PlannedOutput],
        options: ProcessingOptions,
        maximumConcurrentTasks: Int = max(2, min(ProcessInfo.processInfo.activeProcessorCount, 6)),
        progress: @escaping @MainActor @Sendable (ProcessingResult) -> Void,
        itemProgress: (@MainActor @Sendable (UUID, Double) -> Void)? = nil
    ) async -> [ProcessingResult] {
        let imageProcessor = ImageProcessor()
        let videoProcessor = VideoProcessor()
        let concurrency = plans.contains(where: { $0.image.format.kind == .video })
            ? max(1, min(2, maximumConcurrentTasks))
            : maximumConcurrentTasks
        let operation = Task {
            await withTaskGroup(of: ProcessingResult.self, returning: [ProcessingResult].self) { group in
                var iterator = plans.makeIterator()
                var results: [ProcessingResult] = []
                for _ in 0..<min(concurrency, plans.count) {
                    if let plan = iterator.next() {
                        group.addTask {
                            await Self.process(
                                plan,
                                options: options,
                                imageProcessor: imageProcessor,
                                videoProcessor: videoProcessor,
                                itemProgress: itemProgress
                            )
                        }
                    }
                }
                while let result = await group.next() {
                    results.append(result)
                    await progress(result)
                    if !Task.isCancelled, let plan = iterator.next() {
                        group.addTask {
                            await Self.process(
                                plan,
                                options: options,
                                imageProcessor: imageProcessor,
                                videoProcessor: videoProcessor,
                                itemProgress: itemProgress
                            )
                        }
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

    nonisolated private static func process(
        _ plan: PlannedOutput,
        options: ProcessingOptions,
        imageProcessor: ImageProcessor,
        videoProcessor: VideoProcessor,
        itemProgress: (@MainActor @Sendable (UUID, Double) -> Void)?
    ) async -> ProcessingResult {
        await itemProgress?(plan.image.id, 0)
        let result: ProcessingResult
        if plan.image.format.kind == .video {
            result = await videoProcessor.process(plan, options: options) { fraction in
                Task { @MainActor in
                    itemProgress?(plan.image.id, fraction)
                }
            }
        } else {
            result = await imageProcessor.process(plan, options: options)
        }
        await itemProgress?(plan.image.id, 1)
        return result
    }
}
