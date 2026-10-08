import SwiftUI
import UniformTypeIdentifiers

@main struct MeetingFollowupApp: App {
    @StateObject private var store = MeetingStore()
    var body: some Scene { WindowGroup { RootView().environmentObject(store).tint(.teal) } }
}

struct RootView: View {
    @EnvironmentObject var store: MeetingStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var importing = false
    @State private var search = ""
    var body: some View {
        TabView {
            NavigationStack {
                List {
                    if store.meetings.isEmpty {
                        ContentUnavailableView("把沟通变成下一步", systemImage: "waveform.badge.plus",
                            description: Text("在语音备忘录中将录音保存到「文件」，再导入这里。"))
                    }
                    ForEach($store.meetings) { $meeting in
                        if search.isEmpty || (meeting.title + meeting.customer).localizedCaseInsensitiveContains(search) {
                            NavigationLink {
                                MeetingView(meeting: $meeting)
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(meeting.title).font(.headline)
                                    Text(meeting.customer.isEmpty ? "未填写客户" : meeting.customer).foregroundStyle(.secondary)
                                    HStack {
                                        Text(meeting.created, style: .date)
                                        Spacer()
                                        Text(meeting.transcript.isEmpty ? "待转录" : "已有文字稿")
                                    }.font(.caption).foregroundStyle(.secondary)
                                }.padding(.vertical, 6)
                            }
                            .swipeActions { Button("删除", role: .destructive) { store.delete(meeting.id) }.disabled(store.processingIDs.contains(meeting.id)) }
                        }
                    }
                }
                .navigationTitle("会议")
                .searchable(text: $search, prompt: "搜索会议或客户")
                .toolbar { Button { importing = true } label: { Label("导入录音", systemImage: "plus") }.disabled(!store.writable) }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.audio, .movie]) { result in
                    switch result {
                    case .success(let url): store.importAudio(url)
                    case .failure(let error): store.error = error.localizedDescription
                    }
                }
            }.tabItem { Label("会议", systemImage: "waveform") }
            NavigationStack {
                List {
                    ForEach($store.meetings) { $meeting in
                        if !meeting.tasks.isEmpty {
                            Section(meeting.customer.isEmpty ? meeting.title : meeting.customer) {
                                ForEach($meeting.tasks) { $task in
                                    NavigationLink { TaskEditor(task: $task).onDisappear { store.save() } } label: {
                                        VStack(alignment: .leading, spacing: 5) {
                                            Label(task.title, systemImage: task.completed ? "checkmark.circle.fill" : "circle")
                                            Text(task.confirmed ? (task.due.isEmpty ? "未设置截止时间" : task.due) : "AI 建议 · 待确认")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }.navigationTitle("跟进事项")
            }.tabItem { Label("跟进", systemImage: "checklist") }
            SettingsView().tabItem { Label("设置", systemImage: "gearshape") }
        }
        .onChange(of: store.meetings) { store.save() }
        .onChange(of: scenePhase) { if scenePhase != .active { store.save() } }
        .alert("提示", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("知道了") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }
}

struct PlainTextDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        text = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? ""
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
}

struct MeetingView: View {
    @Binding var meeting: Meeting
    @EnvironmentObject var store: MeetingStore
    @AppStorage("gatewayAddress") private var address = ""
    @State private var busy = false
    @State private var operation = ""
    @State private var consent = false
    @State private var exporting = false
    @State private var exportContent = ""
    @StateObject private var player = RecordingPlayer()
    @State private var failure: String?
    @State private var processingMessage = "处理中，请保持 App 在前台…"
    var body: some View {
        Form {
            Section("会议信息") {
                TextField("会议名称", text: $meeting.title)
                TextField("客户名称", text: $meeting.customer)
            }
            Section("原始录音") { RecordingControls(player: player) }
            Section {
                Button(meeting.transcript.isEmpty ? "开始英文转录" : "重新转录（覆盖文字稿）") { operation = "transcribe"; consent = true }
                if let checkpoint = meeting.transcriptionCheckpoint {
                    Text("上次转录已完成 \(checkpoint.completedParts)/\(checkpoint.totalParts) 段，重试会接着处理。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("丢弃未完成的转录", role: .destructive) { meeting.transcriptionCheckpoint = nil; store.save() }
                }
                if busy { ProgressView(processingMessage) }
                Text("录音会在手机上分段转换后上传至你配置的服务及 Groq。请保持 App 在前台。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("英文文字稿 · 可修改") {
                TextEditor(text: $meeting.transcript).frame(minHeight: 180)
                if !meeting.segments.isEmpty {
                    DisclosureGroup("查看原始带时间点转录") {
                        ForEach(meeting.segments) { segment in
                            VStack(alignment: .leading) {
                                Button { player.seek(segment.start, play: true) } label: {
                                    Label(segment.time, systemImage: "play.circle").font(.caption.monospacedDigit())
                                }.buttonStyle(.borderless).accessibilityLabel("从 \(segment.time) 回听")
                                Text(segment.text).font(.callout)
                            }
                        }
                    }
                }
                Button("导出文字稿 TXT") { exportContent = meeting.exportText; exporting = true }.disabled(meeting.transcript.isEmpty)
                Button("生成中文纪要") { operation = "summarize"; consent = true }.disabled(meeting.transcript.isEmpty)
            }
            if !meeting.overview.isEmpty {
                Section("中文纪要 · 可修改") {
                    if meeting.summaryIsStale { Text("文字稿已修改，现有纪要可能需要更新。").foregroundStyle(.orange) }
                    Text("会议摘要").font(.caption)
                    TextEditor(text: $meeting.overview).frame(minHeight: 90)
                    Text("客户需求").font(.caption)
                    TextEditor(text: $meeting.requirements).frame(minHeight: 90)
                    Text("已定事项").font(.caption)
                    TextEditor(text: $meeting.decisions).frame(minHeight: 90)
                    Text("待确认问题").font(.caption)
                    TextEditor(text: $meeting.openQuestions).frame(minHeight: 90)
                    Button("导出纪要和跟进事项 TXT") { exportContent = meeting.exportSummary; exporting = true }
                }
            }
            Section("跟进事项") {
                ForEach($meeting.tasks) { $task in
                    NavigationLink { TaskEditor(task: $task) } label: {
                        VStack(alignment: .leading) {
                            Text(task.title.isEmpty ? "新跟进事项" : task.title)
                            Text(task.confirmed ? (task.completed ? "已完成" : "待办") : "待人工确认").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.onDelete { meeting.tasks.remove(atOffsets: $0); store.save() }
                Button("手动添加") { meeting.tasks.append(FollowUp(confirmed: true)); store.save() }
            }
        }
        .disabled(busy)
        .navigationTitle("会议详情")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(busy)
        .onAppear { player.load(store.folder.appendingPathComponent(meeting.audioFile)) }
        .onDisappear { player.stop(); store.save() }
        .fileExporter(isPresented: $exporting, document: PlainTextDocument(text: exportContent), contentType: .plainText,
                      defaultFilename: "会议文字稿") { result in
            if case .failure(let error) = result { failure = error.localizedDescription }
        }
        .confirmationDialog("确认上传处理", isPresented: $consent, titleVisibility: .visible) {
            Button("上传并处理") { Task { await process() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text(operation == "transcribe" ? "录音将上传至配置的网关及 Groq。重新转录会覆盖你修改的文字稿，请先导出需要保留的内容。" : "文字稿将上传至配置的网关及 Groq 生成纪要。原纪要会被替换；已有跟进事项保留。请核对 AI 结果。")
        }
        .alert("处理未完成", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("知道了") { failure = nil }
        } message: { Text(failure ?? "") }
    }

    @MainActor private func process() async {
        let meetingID = meeting.id
        guard !store.processingIDs.contains(meetingID) else { return }
        store.processingIDs.insert(meetingID)
        busy = true
        defer { busy = false; store.processingIDs.remove(meetingID) }
        do {
            let gateway = Gateway(address: address)
            if operation == "transcribe" {
                let audio = store.folder.appendingPathComponent(meeting.audioFile)
                processingMessage = "正在检查录音…"
                let duration = try await AudioPreparation.duration(of: audio)
                let total = Int(ceil(duration / AudioPreparation.partDuration))
                var checkpoint = meeting.transcriptionCheckpoint ?? TranscriptionCheckpoint(totalParts: total)
                guard checkpoint.totalParts == total, checkpoint.completedParts >= 0, checkpoint.completedParts <= total else {
                    throw AppError.message("录音与上次进度不匹配，请丢弃未完成转录后重试。")
                }
                for part in checkpoint.completedParts..<total {
                    let offset = Double(part) * AudioPreparation.partDuration
                    processingMessage = "正在转换第 \(part + 1)/\(total) 段…"
                    let prepared = try await AudioPreparation.exportPart(from: audio, start: offset,
                        duration: min(AudioPreparation.partDuration, duration - offset))
                    defer { try? FileManager.default.removeItem(at: prepared) }
                    processingMessage = "正在转录第 \(part + 1)/\(total) 段，请保持前台…"
                    let response: TranscriptResponse = try await gateway.request("transcribe", data: Data(contentsOf: prepared), ext: "m4a")
                    checkpoint.text += (checkpoint.text.isEmpty ? "" : "\n\n") + response.text
                    checkpoint.segments += response.segments.map { segment in
                        Segment(start: segment.start + offset, end: segment.end + offset, text: segment.text)
                    }
                    checkpoint.completedParts = part + 1
                    meeting.transcriptionCheckpoint = checkpoint
                    guard store.save() else {
                        throw AppError.message("转录进度无法保存，处理已停止。请检查手机存储空间后重试。")
                    }
                }
                meeting.transcript = checkpoint.text
                meeting.segments = checkpoint.segments
                meeting.transcriptionCheckpoint = nil
            } else {
                processingMessage = "正在生成中文纪要…"
                let source = meeting.transcript
                let response: SummaryResponse = try await gateway.request("summarize", data: JSONEncoder().encode(["text": source]))
                meeting.overview = response.overview
                meeting.requirements = response.requirements
                meeting.decisions = response.decisions
                meeting.openQuestions = response.open_questions
                meeting.summarySource = source
                for task in response.tasks where !meeting.tasks.contains(where: { $0.title == task.title && $0.evidence == task.evidence }) {
                    meeting.tasks.append(FollowUp(title: task.title, owner: task.owner, due: task.due, evidence: task.evidence))
                }
            }
            store.save()
        } catch { failure = error.localizedDescription }
    }
}

struct TaskEditor: View {
    @Binding var task: FollowUp
    var body: some View {
        Form {
            TextField("要跟进什么？", text: $task.title, axis: .vertical)
            TextField("负责人（未明确可留空）", text: $task.owner)
            TextField("截止时间（未明确可留空）", text: $task.due)
            if !task.evidence.isEmpty { Section("原文依据 · 请核对") { Text(task.evidence).textSelection(.enabled) } }
            Toggle("已人工确认", isOn: $task.confirmed)
            Toggle("已完成", isOn: $task.completed).disabled(!task.confirmed || task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }.navigationTitle("跟进事项")
            .onChange(of: task.confirmed) { if !task.confirmed { task.completed = false } }
            .onChange(of: task.title) { if task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { task.completed = false } }
    }
}

struct SettingsView: View {
    @AppStorage("gatewayAddress") private var address = ""
    @State private var token = ""
    @State private var status = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("开发服务连接") {
                    TextField("HTTPS 服务地址", text: $address).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    SecureField("服务访问令牌（不是 Groq API Key）", text: $token)
                    Button("保存访问令牌") {
                        do { try CredentialStore.write(token); status = "已保存到设备钥匙串" }
                        catch { status = error.localizedDescription }
                    }
                    if !status.isEmpty { Text(status).font(.caption) }
                }
                Section("关于当前版本") {
                    Text("开发中版本。录音和记录保存在此设备；点击处理后，相关内容会发送至配置的服务及 Groq。请在获得录音许可后使用。")
                    Text("目前以英文录音为输入，中文纪要为输出。AI 可能误识别数字、名字或承诺，请回查原始录音。")
                }
            }.navigationTitle("设置").onAppear { token = CredentialStore.read() }
        }
    }
}
