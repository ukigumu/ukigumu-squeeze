@preconcurrency import AVFoundation
import Foundation
import UniformTypeIdentifiers

public enum VideoPresetSelector: Sendable {
    public static func preferredPresets(quality: Double, customSize: Bool) -> [String] {
        if customSize {
            return [
                AVAssetExportPresetHEVCHighestQuality,
                AVAssetExportPresetHighestQuality,
                AVAssetExportPreset1920x1080,
                AVAssetExportPreset1280x720,
                AVAssetExportPreset960x540,
                AVAssetExportPreset640x480,
                AVAssetExportPresetMediumQuality
            ]
        }
        switch quality {
        case ..<0.4:
            return [
                AVAssetExportPresetLowQuality,
                AVAssetExportPreset640x480,
                AVAssetExportPresetMediumQuality,
                AVAssetExportPresetHighestQuality
            ]
        case ..<0.75:
            return [
                AVAssetExportPresetMediumQuality,
                AVAssetExportPreset1280x720,
                AVAssetExportPresetHighestQuality
            ]
        default:
            return [
                AVAssetExportPresetHEVCHighestQuality,
                AVAssetExportPresetHighestQuality,
                AVAssetExportPreset1920x1080,
                AVAssetExportPresetMediumQuality
            ]
        }
    }

    public static func choose(quality: Double, customSize: Bool, compatible: [String]) -> String? {
        preferredPresets(quality: quality, customSize: customSize)
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
        options: ProcessingOptions
    ) async -> ProcessingResult {
        do {
            try Task.checkCancellation()
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
            let targetSize = evenPixelSize(
                ResolutionCalculator.dimensions(
                    sourceWidth: sourceWidth,
                    sourceHeight: sourceHeight,
                    mode: options.resolutionMode,
                    width: options.resolutionWidth,
                    height: options.resolutionHeight
                )
            )
            let customSize = targetSize.width != sourceWidth || targetSize.height != sourceHeight

            let temporary = TemporaryOutput.url(adjacentTo: plan.outputURL)
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
                quality: options.quality,
                preserveMetadata: options.preserveMetadata,
                targetSize: targetSize,
                customSize: customSize
            )
            try await validate(temporary, expectedFormat: plan.finalFormat)
            try Task.checkCancellation()
            let encodedSize = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(Int64.init) ?? 0
            let outputSize = try await displaySize(of: temporary)

            if options.outputFormat == .original,
               options.resolutionMode == .original,
               encodedSize >= plan.image.byteCount {
                if options.destinationURL != nil {
                    try fileManager.copyItem(at: plan.image.sourceURL, to: plan.outputURL)
                }
                return ProcessingResult.success(
                    plan: plan, width: sourceWidth, height: sourceHeight,
                    finalBytes: plan.image.byteCount, metadataAvailable: !metadata.isEmpty,
                    status: .noImprovement
                )
            }

            try OutputCommitter.commit(temporary: temporary, plan: plan, fileManager: fileManager)
            return ProcessingResult.success(
                plan: plan, width: outputSize.width, height: outputSize.height,
                finalBytes: encodedSize, metadataAvailable: !metadata.isEmpty,
                status: .completed
            )
        } catch is CancellationError {
            return ProcessingResult.failure(plan: plan, status: .cancelled, error: nil)
        } catch {
            return ProcessingResult.failure(plan: plan, status: .error, error: error.localizedDescription)
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
        quality: Double,
        preserveMetadata: Bool,
        targetSize: PixelSize,
        customSize: Bool
    ) async throws {
        let fileType = Self.fileType(for: format)
        let compatible = AVAssetExportSession.exportPresets(compatibleWith: asset)
        let presets = VideoPresetSelector.preferredPresets(quality: quality, customSize: customSize)
            .filter { compatible.contains($0) }
        var lastError: Error = UkigumuSqueezeError.videoExportUnavailable

        for preset in presets {
            guard let session = AVAssetExportSession(asset: asset, presetName: preset),
                  session.supportedFileTypes.contains(fileType) else { continue }
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            session.outputURL = url
            session.outputFileType = fileType
            session.shouldOptimizeForNetworkUse = true
            if !preserveMetadata {
                session.metadataItemFilter = .forSharing()
            }
            if customSize {
                session.videoComposition = try await makeComposition(
                    videoTrack: videoTrack,
                    duration: duration,
                    preferredTransform: preferredTransform,
                    naturalSize: naturalSize,
                    targetSize: targetSize
                )
            }

            do {
                try await export(session, to: url)
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private func export(_ session: AVAssetExportSession, to url: URL) async throws {
        try await withTaskCancellationHandler {
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
        } onCancel: {
            session.cancelExport()
        }
    }

    private func makeComposition(
        videoTrack: AVAssetTrack,
        duration: CMTime,
        preferredTransform: CGAffineTransform,
        naturalSize: CGSize,
        targetSize: PixelSize
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
        let frameRate = try await videoTrack.load(.nominalFrameRate)
        let timescale = Int32(max(1, frameRate.rounded()))
        composition.frameDuration = CMTime(value: 1, timescale: timescale)
        composition.instructions = [instruction]
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

    private static func fileType(for format: MediaFormat) -> AVFileType {
        switch format {
        case .mov: .mov
        case .m4v: .m4v
        default: .mp4
        }
    }
}
