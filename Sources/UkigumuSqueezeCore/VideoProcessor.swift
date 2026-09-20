@preconcurrency import AVFoundation
import Foundation
import UniformTypeIdentifiers

public enum VideoPresetSelector: Sendable {
    public static func preferredExportPresets(for profile: VideoEncodeProfile) -> [String] {
        switch (profile.codec, profile.lean) {
        case (.h264, .smaller):
            [
                AVAssetExportPresetLowQuality,
                AVAssetExportPreset640x480,
                AVAssetExportPreset960x540,
                AVAssetExportPreset1280x720,
                AVAssetExportPresetMediumQuality
            ]
        case (.h264, .balanced):
            [
                AVAssetExportPresetMediumQuality,
                AVAssetExportPreset1920x1080,
                AVAssetExportPreset1280x720,
                AVAssetExportPresetHighestQuality
            ]
        case (.hevc, _), (_, .higher):
            [
                AVAssetExportPresetHEVCHighestQuality,
                AVAssetExportPresetHighestQuality,
                AVAssetExportPreset1920x1080,
                AVAssetExportPresetMediumQuality
            ]
        }
    }

    public static func choose(profile: VideoEncodeProfile, compatible: [String]) -> String? {
        preferredExportPresets(for: profile)
            .first { compatible.contains($0) }
            ?? compatible.first {
                $0 != AVAssetExportPresetPassthrough && $0 != AVAssetExportPresetAppleM4A
            }
    }
}

public actor VideoProcessor {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func process(
        _ plan: PlannedOutput,
        options: ProcessingOptions,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async -> ProcessingResult {
        let sourceAccess = plan.image.sourceURL.startAccessingSecurityScopedResource()
        let rootAccess = plan.image.rootURL.startAccessingSecurityScopedResource()
        defer {
            if sourceAccess { plan.image.sourceURL.stopAccessingSecurityScopedResource() }
            if rootAccess { plan.image.rootURL.stopAccessingSecurityScopedResource() }
        }
        do {
            try Task.checkCancellation()
            progress?(0.02)
            let asset = AVURLAsset(url: plan.image.sourceURL)
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            guard let videoTrack = videoTracks.first else {
                throw UkigumuSqueezeError.invalidVideo(plan.image.sourceURL)
            }

            let naturalSize = try await videoTrack.load(.naturalSize)
            let transform = try await videoTrack.load(.preferredTransform)
            let duration = try await asset.load(.duration)
            let metadata = (try? await asset.load(.metadata)) ?? []
            let display = naturalSize.applying(transform)
            let sourceWidth = max(1, Int(abs(display.width).rounded()))
            let sourceHeight = max(1, Int(abs(display.height).rounded()))
            let profile = options.videoProfile
            let targetSize = evenPixelSize(
                profile.dimensions(sourceWidth: sourceWidth, sourceHeight: sourceHeight)
            )
            let resized = targetSize.width != sourceWidth || targetSize.height != sourceHeight

            let temporary = TemporaryOutput.url(
                adjacentTo: plan.outputURL,
                pathExtension: plan.finalFormat.preferredExtension
            )
            defer { try? fileManager.removeItem(at: temporary) }
            try fileManager.createDirectory(at: temporary.deletingLastPathComponent(), withIntermediateDirectories: true)
            try await export(
                asset: asset,
                videoTrack: videoTrack,
                duration: duration,
                preferredTransform: transform,
                naturalSize: naturalSize,
                to: temporary,
                format: plan.finalFormat,
                profile: profile,
                preserveMetadata: options.preserveMetadata,
                targetSize: targetSize,
                resized: resized,
                progress: progress
            )
            try await validate(temporary, expectedFormat: plan.finalFormat)
            try Task.checkCancellation()
            let encodedSize = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(Int64.init) ?? 0
            let outputSize = try await displaySize(of: temporary)

            if !resized, encodedSize >= plan.image.byteCount {
                if options.destinationURL != nil {
                    try fileManager.copyItem(at: plan.image.sourceURL, to: plan.outputURL)
                }
                progress?(1)
                return ProcessingResult.success(
                    plan: plan, width: sourceWidth, height: sourceHeight,
                    finalBytes: plan.image.byteCount, metadataAvailable: !metadata.isEmpty,
                    status: .noImprovement
                )
            }

            try OutputCommitter.commit(temporary: temporary, plan: plan, fileManager: fileManager)
            progress?(1)
            return ProcessingResult.success(
                plan: plan, width: outputSize.width, height: outputSize.height,
                finalBytes: encodedSize, metadataAvailable: !metadata.isEmpty,
                status: .completed
            )
        } catch is CancellationError {
            return ProcessingResult.failure(plan: plan, status: .cancelled, error: nil)
        } catch {
            return ProcessingResult.failure(
                plan: plan,
                status: .error,
                error: ProcessingErrorMessage.fromFailure(error)
            )
        }
    }

    private func export(
        asset: AVURLAsset,
        videoTrack: AVAssetTrack,
        duration: CMTime,
        preferredTransform: CGAffineTransform,
        naturalSize: CGSize,
        to url: URL,
        format: MediaFormat,
        profile: VideoEncodeProfile,
        preserveMetadata: Bool,
        targetSize: PixelSize,
        resized: Bool,
        progress: (@Sendable (Double) -> Void)?
    ) async throws {
        let compatible = AVAssetExportSession.exportPresets(compatibleWith: asset)
        var presets = VideoPresetSelector.preferredExportPresets(for: profile)
            .filter { compatible.contains($0) }
        if let fallback = VideoPresetSelector.choose(profile: profile, compatible: compatible),
           !presets.contains(fallback) {
            presets.append(fallback)
        }
        var lastError: Error = UkigumuSqueezeError.videoExportUnavailable
        var attempted = false
        let fileTypes = Self.fileTypes(for: format)

        for preset in presets {
            guard let probe = AVAssetExportSession(asset: asset, presetName: preset) else { continue }
            guard let fileType = await Self.selectFileType(
                probe: probe,
                asset: asset,
                preset: preset,
                preferred: fileTypes
            ) else {
                lastError = UkigumuSqueezeError.videoExportIncompatible(format)
                continue
            }
            let compositionPasses = resized ? [true] : [false, true]
            for useComposition in compositionPasses {
                guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { continue }
                if fileManager.fileExists(atPath: url.path) {
                    try fileManager.removeItem(at: url)
                }
                session.outputURL = url
                session.outputFileType = fileType
                session.shouldOptimizeForNetworkUse = profile.optimizeForSharing
                if !preserveMetadata {
                    session.metadataItemFilter = .forSharing()
                }
                if useComposition {
                    session.videoComposition = try await makeComposition(
                        videoTrack: videoTrack,
                        duration: duration,
                        preferredTransform: preferredTransform,
                        naturalSize: naturalSize,
                        targetSize: targetSize,
                        applyStandardDefinitionColor: profile.codec == .h264
                    )
                }

                attempted = true
                do {
                    try await export(session, to: url, progress: progress)
                    return
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    lastError = error
                }
            }
        }
        throw attempted ? lastError : UkigumuSqueezeError.videoExportIncompatible(format)
    }

    private func export(
        _ session: AVAssetExportSession,
        to url: URL,
        progress: (@Sendable (Double) -> Void)?
    ) async throws {
        try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        session.exportAsynchronously {
                            switch session.status {
                            case .completed:
                                continuation.resume()
                            case .cancelled:
                                continuation.resume(throwing: CancellationError())
                            case .failed:
                                continuation.resume(
                                    throwing: session.error ?? UkigumuSqueezeError.validationFailed(url)
                                )
                            default:
                                continuation.resume(throwing: UkigumuSqueezeError.validationFailed(url))
                            }
                        }
                    }
                }
                group.addTask {
                    while !Task.isCancelled {
                        progress?(Double(min(max(session.progress, 0), 0.99)))
                        try? await Task.sleep(nanoseconds: 150_000_000)
                    }
                }
                try await group.next()
                group.cancelAll()
            }
        } onCancel: {
            session.cancelExport()
        }
        progress?(1)
    }

    private func makeComposition(
        videoTrack: AVAssetTrack,
        duration: CMTime,
        preferredTransform: CGAffineTransform,
        naturalSize: CGSize,
        targetSize: PixelSize,
        applyStandardDefinitionColor: Bool
    ) async throws -> AVVideoComposition {
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration.isNumeric && duration.seconds > 0 ? duration : CMTime(seconds: 1, preferredTimescale: 600))
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        layer.setTransform(
            orientedTransform(preferred: preferredTransform, naturalSize: naturalSize, renderSize: targetSize),
            at: .zero
        )
        instruction.layerInstructions = [layer]

        let composition = AVMutableVideoComposition()
        composition.renderSize = CGSize(width: targetSize.width, height: targetSize.height)
        composition.renderScale = 1
        let frameRate = try await videoTrack.load(.nominalFrameRate)
        let fps = frameRate.isFinite && frameRate >= 1 ? frameRate : 30
        let timescale = Int32(min(max(fps.rounded(), 1), 240))
        composition.frameDuration = CMTime(value: 1, timescale: timescale)
        composition.instructions = [instruction]
        if applyStandardDefinitionColor {
            composition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
            composition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
            composition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
        }
        return composition
    }

    private func orientedTransform(
        preferred: CGAffineTransform,
        naturalSize: CGSize,
        renderSize: PixelSize
    ) -> CGAffineTransform {
        let mapped = CGRect(origin: .zero, size: naturalSize).applying(preferred)
        var transform = preferred
        transform.tx -= mapped.origin.x
        transform.ty -= mapped.origin.y
        let displayWidth = max(abs(mapped.width), 1)
        let displayHeight = max(abs(mapped.height), 1)
        return transform.concatenating(
            CGAffineTransform(
                scaleX: CGFloat(renderSize.width) / displayWidth,
                y: CGFloat(renderSize.height) / displayHeight
            )
        )
    }

    private func validate(_ url: URL, expectedFormat: MediaFormat) async throws {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard !tracks.isEmpty else {
            throw UkigumuSqueezeError.validationFailed(url)
        }
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            switch expectedFormat {
            case .mov:
                guard type.conforms(to: .quickTimeMovie) else {
                    throw UkigumuSqueezeError.validationFailed(url)
                }
            case .mp4, .m4v:
                guard type.conforms(to: .mpeg4Movie) || type.identifier == "com.apple.m4v-video" else {
                    throw UkigumuSqueezeError.validationFailed(url)
                }
            default:
                break
            }
        }
    }

    private func displaySize(of url: URL) async throws -> PixelSize {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw UkigumuSqueezeError.validationFailed(url)
        }
        let naturalSize = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let display = naturalSize.applying(transform)
        return PixelSize(
            width: max(1, Int(abs(display.width).rounded())),
            height: max(1, Int(abs(display.height).rounded()))
        )
    }

    private func evenPixelSize(_ size: PixelSize) -> PixelSize {
        PixelSize(
            width: max(2, size.width - size.width % 2),
            height: max(2, size.height - size.height % 2)
        )
    }

    private static func fileTypes(for format: MediaFormat) -> [AVFileType] {
        switch format {
        case .mov: return [.mov]
        case .m4v: return [.m4v, .mp4]
        default: return [.mp4, .m4v]
        }
    }

    private static func selectFileType(
        probe: AVAssetExportSession,
        asset: AVAsset,
        preset: String,
        preferred: [AVFileType]
    ) async -> AVFileType? {
        let supported = Set(probe.supportedFileTypes)
        var compatible: AVFileType?
        var listed: AVFileType?
        for fileType in preferred where supported.contains(fileType) {
            if listed == nil {
                listed = fileType
            }
            if await isCompatible(preset: preset, asset: asset, fileType: fileType) {
                compatible = fileType
                break
            }
        }
        return compatible ?? listed
    }

    private static func isCompatible(preset: String, asset: AVAsset, fileType: AVFileType) async -> Bool {
        await withCheckedContinuation { continuation in
            AVAssetExportSession.determineCompatibility(
                ofExportPreset: preset,
                with: asset,
                outputFileType: fileType
            ) { compatible in
                continuation.resume(returning: compatible)
            }
        }
    }
}
