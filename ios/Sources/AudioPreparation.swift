import AVFoundation
import Foundation

/// Exports one short compressed upload at a time; preserves the original recording.
enum AudioPreparation {
    static let partDuration: Double = 300
    static let maxUploadBytes = 24 * 1024 * 1024

    static func duration(of url: URL) async throws -> Double {
        let asset = AVURLAsset(url: url)
        let time = try await asset.load(.duration)
        let seconds = time.seconds
        guard seconds.isFinite, seconds > 0, seconds <= 4 * 3600 else {
            throw AppError.message("录音时长无效或超过四小时，请分成多个会议导入。")
        }
        return seconds
    }

    static func exportPart(from url: URL, start: Double, duration: Double) async throws -> URL {
        let asset = AVURLAsset(url: url)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw AppError.message("无法转换此录音，请使用语音备忘录导出的 M4A 文件。")
        }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("meeting-" + UUID().uuidString + ".m4a")
        session.outputURL = output
        session.outputFileType = .m4a
        session.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                                       duration: CMTime(seconds: duration, preferredTimescale: 600))
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                session.exportAsynchronously {
                    if session.status == .completed { continuation.resume() }
                    else { continuation.resume(throwing: session.error ?? AppError.message("录音转换未完成，请重试。")) }
                }
            }
            let size = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0 && size <= maxUploadBytes else { throw AppError.message("转换后的片段仍然过大，未上传，请改用单声道录音。") }
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: output.path)
            return output
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }
    }
}

struct TranscriptionCheckpoint: Codable, Equatable {
    var completedParts = 0
    var totalParts: Int
    var text = ""
    var segments: [Segment] = []
}
