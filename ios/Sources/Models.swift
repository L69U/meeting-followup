import Foundation
import SwiftUI

struct Segment: Codable, Identifiable, Equatable {
    var id = UUID()
    var start: Double
    var end: Double
    var text: String
    enum CodingKeys: String, CodingKey { case start, end, text }
    var time: String { String(format: "%02d:%02d", Int(max(0, start)) / 60, Int(max(0, start)) % 60) }
}

struct FollowUp: Codable, Identifiable, Equatable {
    var id = UUID()
    var title = ""
    var owner = ""
    var due = ""
    var evidence = ""
    var confirmed = false
    var completed = false
}

struct Meeting: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var customer = ""
    var created = Date()
    var audioFile: String
    var transcript = ""
    var segments: [Segment] = []
    var overview = ""
    var requirements = ""
    var decisions = ""
    var openQuestions = ""
    var tasks: [FollowUp] = []
    var summarySource = ""
    var transcriptionCheckpoint: TranscriptionCheckpoint?
    var summaryIsStale: Bool { !summarySource.isEmpty && summarySource != transcript }
    var exportText: String {
        "\(title)\n客户：\(customer)\n\n\(transcript)"
    }
    var exportSummary: String {
        let items = tasks.map { task in
            let status = !task.confirmed ? "待人工确认" : (task.completed ? "已完成" : "待办")
            return "[\(status)] \(task.title)\n负责人：\(task.owner.isEmpty ? "未明确" : task.owner)\n截止：\(task.due.isEmpty ? "未明确" : task.due)\n原文依据：\(task.evidence)"
        }.joined(separator: "\n\n")
        let warning = summaryIsStale ? "注意：文字稿已修改，请重新核对此纪要。\n" : ""
        return "\(title)\n客户：\(customer)\n\(warning)\n会议摘要\n\(overview)\n\n客户需求\n\(requirements)\n\n已定事项\n\(decisions)\n\n待确认问题\n\(openQuestions)\n\n跟进事项\n\(items)"
    }
}

@MainActor final class MeetingStore: ObservableObject {
    @Published var meetings: [Meeting] = []
    @Published var error: String?
    @Published var processingIDs: Set<UUID> = []
    private(set) var writable = true
    let folder: URL
    private var index: URL { folder.appendingPathComponent("meetings.json") }

    init() {
        folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MeetingFollowup", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: index.path) {
                meetings = try JSONDecoder().decode([Meeting].self, from: Data(contentsOf: index))
            }
        } catch {
            writable = false
            self.error = "本地记录读取失败。原文件已保留，请勿继续导入以免覆盖。\n\(error.localizedDescription)"
        }
    }

    @discardableResult func save() -> Bool {
        guard writable else { return false }
        do {
            try JSONEncoder().encode(meetings).write(to: index, options: [.atomic, .completeFileProtection])
            return true
        } catch {
            self.error = "保存失败：\(error.localizedDescription)"
            return false
        }
    }

    func importAudio(_ url: URL) {
        guard writable else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let ext = url.pathExtension.lowercased()
            guard ["m4a", "mp3", "wav", "mp4", "aac", "aif", "aiff", "caf"].contains(ext) else {
                throw AppError.message("暂不支持这个文件格式。建议导入语音备忘录的 M4A 文件。")
            }
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0 && size <= 500 * 1024 * 1024 else {
                throw AppError.message("请选择 500 MB 以内的非空录音。转录时会自动转换成较小片段。")
            }
            let name = UUID().uuidString + "." + ext
            let destination = folder.appendingPathComponent(name)
            try FileManager.default.copyItem(at: url, to: destination)
            do {
                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: destination.path)
                let record = Meeting(title: url.deletingPathExtension().lastPathComponent, audioFile: name)
                meetings.insert(record, at: 0)
                if !save() {
                    meetings.removeAll { $0.id == record.id }
                    try? FileManager.default.removeItem(at: destination)
                }
            } catch {
                try? FileManager.default.removeItem(at: destination)
                throw error
            }
        } catch { self.error = error.localizedDescription }
    }

    func delete(_ id: UUID) {
        guard writable, let meeting = meetings.first(where: { $0.id == id }) else { return }
        guard !processingIDs.contains(id) else {
            error = "会议正在处理，请完成后再删除。"
            return
        }
        let previous = meetings
        meetings.removeAll { $0.id == id }
        guard save() else {
            meetings = previous
            return
        }
        do {
            let audio = folder.appendingPathComponent(meeting.audioFile)
            if FileManager.default.fileExists(atPath: audio.path) { try FileManager.default.removeItem(at: audio) }
        } catch {
            // Restore a visible record so the user can retry deleting its audio.
            meetings = previous
            save()
            self.error = "录音删除失败，记录已恢复供重试：\(error.localizedDescription)"
        }
    }
}

enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let value) = self { return value }; return nil }
}
