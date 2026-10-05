import SwiftUI
import Combine
import UIKit

/// 对话视图模型：流式对话、附件、按住说话、语音通话、会话切换
@MainActor
final class ChatViewModel: ObservableObject {
    private let store: AppStore
    private let backend: AgentBackend
    private let speech = SpeechService()
    private var streamTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    @Published var draft = ""
    @Published var pendingAttachments: [Attachment] = []
    @Published var state: AgentState = .idle
    @Published var isBusy = false
    @Published var isRecording = false
    @Published var level: Double = 0
    @Published var lastVoiceError: String?
    @Published var showVoiceCall = false
    @Published var slidesToEdit: [Slide]?

    init(store: AppStore) {
        self.store = store
        self.backend = LocalAgentBackend(store: store, auth: AuthService.shared)
        if store.currentConversationId == nil, let first = store.data.conversations.first {
            store.currentConversationId = first.id
        }

        speech.onLevel = { [weak self] l in
            Task { @MainActor in self?.level = l }
        }

        store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var conversations: [Conversation] { store.data.conversations }

    var current: Conversation? { store.currentConversation }

    var stateText: String {
        switch state {
        case .thinking: return "正在思考…"
        case .working: return "正在工作…"
        case .making: return "正在制作…"
        case .waitingApproval: return "等待你的批准…"
        case .idle: return ""
        }
    }

    var showTyping: Bool { state != .idle }

    // MARK: 会话管理

    func newConversation() {
        let c = Conversation()
        store.data.conversations.insert(c, at: 0)
        store.currentConversationId = c.id
        store.save()
    }

    func switchTo(_ id: UUID) {
        store.currentConversationId = id
    }

    func delete(_ conv: Conversation) {
        store.data.conversations.removeAll { $0.id == conv.id }
        if store.currentConversationId == conv.id {
            store.currentConversationId = store.data.conversations.first?.id
        }
        if store.data.conversations.isEmpty { newConversation() }
        store.save()
    }

    // MARK: 会话操作（对齐原版：重命名 / 置顶 / 收藏 / 导出 Markdown）

    func renameCurrent(to title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, var conv = current else { return }
        conv.title = String(t.prefix(40))
        replace(conv)
    }

    func togglePin() {
        guard var conv = current else { return }
        conv.pinned.toggle()
        replace(conv)
        if conv.pinned {
            store.data.conversations.removeAll { $0.id == conv.id }
            store.data.conversations.insert(conv, at: 0)
            store.save()
        }
    }

    func toggleFavorite() {
        guard var conv = current else { return }
        conv.favorite.toggle()
        replace(conv)
    }

    var sortedConversations: [Conversation] {
        store.data.conversations.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            return a.updatedAt > b.updatedAt
        }
    }

    func setRole(_ role: AgentRole) {
        guard var conv = current else { return }
        conv.role = role
        if let idx = store.data.conversations.firstIndex(where: { $0.id == conv.id }) {
            store.data.conversations[idx] = conv
            store.save()
        }
    }

    // MARK: 发送

    func send() async {
        guard var conv = current else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = pendingAttachments
        guard !isBusy, !text.isEmpty || !attachments.isEmpty else { return }

        draft = ""
        pendingAttachments = []

        conv.messages.append(Message(role: .user, text: text, attachments: attachments))
        if conv.messages.count == 1 && conv.title == "新对话" {
            conv.title = text.count <= 18 ? text : String(text.prefix(18)) + "…"
        }
        var reply = Message(role: .agent)
        conv.messages.append(reply)
        replace(conv)
        let replyId = reply.id

        isBusy = true
        state = .thinking
        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                var acc = ""
                let stream = backend.streamChat(
                    userText: text, attachments: attachments,
                    connectors: store.data.connectors)
                for try await ev in stream {
                    switch ev {
                    case .status(let s):
                        state = s
                    case .delta(let d):
                        acc += d
                        state = .idle
                        updateMessage(id: replyId) { $0.text = acc }
                    case .tool(let name, let detail):
                        acc += "\n\n▸ 工具 \(name)：\(detail)"
                        updateMessage(id: replyId) { $0.text = acc }
                        store.log(name, detail)
                    case .approvalRequest(let title, let summary, let risk):
                        state = .waitingApproval
                        store.data.tasks.append(AgentTask(
                            title: title, summary: summary, risk: risk,
                            state: .waitingApproval))
                        store.save()
                    case .error(let message):
                        acc += "\n⚠ \(message)"
                        updateMessage(id: replyId) { $0.text = acc }
                    case .alt(let a):
                        updateMessage(id: replyId) { $0.altText = a }
                    case .products(let items):
                        updateMessage(id: replyId) { $0.products = items }
                    case .slides(let slides):
                        updateMessage(id: replyId) { $0.slides = slides }
                    case .ageVerificationRequired:
                        store.data.settings.ageGateActive = true
                        store.save()
                    case .done:
                        break
                    }
                }
                updateMessage(id: replyId) { $0.text = acc.isEmpty ? "（空回复）" : acc }
            } catch is CancellationError {
                // 用户停止
            } catch {
                updateMessage(id: replyId) { $0.text += "\n⚠ \(error.localizedDescription)" }
            }
            isBusy = false
            state = .idle
        }
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
    }

    private func replace(_ conv: Conversation) {
        if let idx = store.data.conversations.firstIndex(where: { $0.id == conv.id }) {
            store.data.conversations[idx] = conv
            store.data.conversations[idx].updatedAt = Date()
            store.save()
        }
    }

    private func updateMessage(id: UUID, mutate: (inout Message) -> Void) {
        guard var conv = current else { return }
        guard let idx = conv.messages.firstIndex(where: { $0.id == id }) else { return }
        mutate(&conv.messages[idx])
        replace(conv)
    }

    func openSlides(_ msg: Message) {
        guard !msg.slides.isEmpty else { return }
        slidesToEdit = msg.slides
        store.data.settings.slidesEditorActive = true
        store.save()
    }

    // MARK: A/B 偏好（对齐原版「两条回复已就绪，请选择你偏好的回复」）

    func preferVariant(_ msg: Message, _ variant: String) {
        updateMessage(id: msg.id) { $0.preferredVariant = variant }
        if variant == "A" { store.data.prefA += 1 } else { store.data.prefB += 1 }
        store.log("dual_reply.preference", "用户偏好 \(variant)", verdict: "反馈")
    }

    // MARK: 语音（按住说话）

    func voiceDown() {
        guard !isRecording else { return }
        Task {
            do {
                try await speech.start()
                isRecording = true
            } catch {
                lastVoiceError = error.localizedDescription
            }
        }
    }

    func voiceUp() {
        guard isRecording else { return }
        isRecording = false
        let url = speech.stop()
        level = 0
        guard let url else { return }

        Task {
            guard var conv = current else { return }
            conv.messages.append(Message(
                role: .user, text: "🎤 语音消息",
                attachments: [Attachment(name: url.lastPathComponent, kind: "音频", path: url.path)]))
            replace(conv)

            let transcript = await speech.transcribe(url: url)
            if let transcript {
                draft = transcript
                store.log("voice.transcribe", "已转写 \(url.lastPathComponent)")
            } else {
                let reply = Message(role: .agent, text: "已收到你的语音片段。\n设备端转写未开启或不可用（首次会请求“语音识别”权限）。你也可以直接打字，或输入「提醒我: …」等工具指令。")
                conv.messages.append(reply)
                replace(conv)
            }
        }
    }
}
