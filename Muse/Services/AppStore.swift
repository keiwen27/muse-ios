import Foundation

/// 全局数据仓库：内存态 + Documents/muse.json 持久化
@MainActor
final class AppStore: ObservableObject {
    static let shared = AppStore()

    @Published var data: MuseData
    @Published var currentConversationId: UUID?
    /// 「附近： …」触发的地图查询（由 UI 层弹出地图）
    @Published var lastMapQuery: String?

    private let baseDir: URL

    /// dataDir 为 nil 时使用 Documents（E2E 可注入临时目录）
    init(dataDir: URL? = nil) {
        baseDir = dataDir ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = baseDir.appendingPathComponent("muse.json")
        if let raw = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(MuseData.self, from: raw) {
            data = decoded
        } else {
            data = MuseData()
            seedWelcome()
        }
        currentConversationId = data.conversations.first?.id
    }

    func save() {
        if let raw = try? JSONEncoder().encode(data) {
            try? raw.write(to: baseDir.appendingPathComponent("muse.json"), options: .atomic)
        }
    }

    var currentConversation: Conversation? {
        data.conversations.first { $0.id == currentConversationId }
    }

    func seedWelcome() {
        var hello = Conversation()
        hello.title = "世界，你好！"
        hello.messages = [Message(
            role: .agent,
            text: "你好！我是 Muse，你的个人 AI 智能体。\n\n我可以帮你：\n• 管理日历、邮件、提醒与笔记\n• 整理照片与通讯录\n• 帮你盯任务、跑浏览器自动化（涉及支付会请求批准）\n\n试试对我说：\n「提醒我: 明早 9 点站会」「记一笔: 给设计部发需求」「创建浏览器任务: 帮我比价降噪耳机」"
        )]
        data.conversations.insert(hello, at: 0)
        currentConversationId = hello.id
        save()
    }

    func log(_ tool: String, _ detail: String, verdict: String = "自动执行") {
        data.audit.insert(AuditEntry(tool: tool, detail: detail, verdict: verdict), at: 0)
        save()
    }

    // MARK: 额度

    func charge(_ amount: Double, _ note: String) {
        data.subscription.credits = max(0, data.subscription.credits - amount)
        data.subscription.transactions.insert(
            QuotaTransaction(kind: "消耗", credits: -amount, note: note), at: 0)
        save()
    }

    // MARK: 笔记

    func appendNote(_ text: String) {
        let url = baseDir.appendingPathComponent("notes.md")
        let line = "\n- \(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short)) \(text)"
        if let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.write(contentsOf: Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }

    var notesFileURL: URL { baseDir.appendingPathComponent("notes.md") }

    // MARK: 审批

    func approve(_ task: AgentTask) {
        guard let idx = data.tasks.firstIndex(where: { $0.id == task.id }) else { return }
        data.tasks[idx].state = .running
        let result = TaskExecutor.execute(&data.tasks[idx], data: data, baseDir: baseDir)
        data.audit.insert(AuditEntry(
            tool: "task.execute.\(data.tasks[idx].action.rawValue)",
            detail: "\(data.tasks[idx].summary) → \(result)",
            verdict: "已批准（用户确认）"), at: 0)
        save()
    }

    func cancel(_ task: AgentTask) {
        guard let idx = data.tasks.firstIndex(where: { $0.id == task.id }) else { return }
        data.tasks[idx].state = .cancelled
        log("task.cancel", task.summary, verdict: "已拒绝（用户确认）")
    }

    func advanceBrowserTask(_ task: AgentTask) {
        guard let idx = data.tasks.firstIndex(where: { $0.id == task.id }),
              data.tasks[idx].action == .browserTask,
              data.tasks[idx].state == .running, data.tasks[idx].progress < 100 else { return }
        let result = TaskExecutor.execute(&data.tasks[idx], data: data, baseDir: baseDir)
        data.audit.insert(AuditEntry(tool: "browser.task.advance", detail: result), at: 0)
        save()
    }

    func stopBrowserTask(_ task: AgentTask) {
        guard let idx = data.tasks.firstIndex(where: { $0.id == task.id }) else { return }
        data.tasks[idx].state = .cancelled
        log("browser.task.stop", task.summary, verdict: "已停止（用户接管）")
    }

    // MARK: 自定义连接器

    enum ConnectorAddResult { case ok(Connector), emptyName, duplicate, missingCredential }

    func addCustomConnector(name: String, kind: String,
                            clientId: String, clientSecret: String,
                            apiKey: String, baseUrl: String) -> ConnectorAddResult {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return .emptyName }
        guard !data.connectors.contains(where: { $0.name == name }) else { return .duplicate }
        if kind == "oauth" && (clientId.isEmpty || clientSecret.isEmpty) { return .missingCredential }
        if kind == "apikey" && apiKey.isEmpty { return .missingCredential }
        let conn = Connector(
            id: "custom-" + UUID().uuidString.prefix(8),
            name: name,
            connectorDescription: kind == "oauth" ? "自定义 OAuth 连接器 · \(baseUrl)" : "自定义 API Key 连接器 · \(baseUrl)",
            glyph: "⚿", kind: kind,
            clientId: clientId, clientSecret: clientSecret, apiKey: apiKey, baseUrl: baseUrl)
        data.connectors.append(conn)
        save()
        return .ok(conn)
    }

    // MARK: 连接器开关

    func setConnectorEnabled(_ connector: Connector, enabled: Bool) {
        guard let idx = data.connectors.firstIndex(where: { $0.id == connector.id }) else { return }
        data.connectors[idx].isEnabled = enabled
        if enabled {
            log("connector.connect", connector.name, verdict: "用户手动连接")
        }
        save()
    }

    func toggleConnectorScope(_ connector: Connector, scope: String) {
        guard let idx = data.connectors.firstIndex(where: { $0.id == connector.id }) else { return }
        switch scope {
        case "read": data.connectors[idx].canRead.toggle()
        case "write": data.connectors[idx].canWrite.toggle()
        case "send": data.connectors[idx].canSend.toggle()
        default: break
        }
        save()
    }

    func setAutoShare(_ connector: Connector, enabled: Bool) {
        guard let idx = data.connectors.firstIndex(where: { $0.id == connector.id }) else { return }
        data.connectors[idx].autoShare = enabled
        save()
    }

    // MARK: 订阅

    struct TopUpOption: Identifiable {
        let id = UUID()
        let title: String
        let price: String
        let credits: Double
        let plan: PlanKind?
    }
    static let topUpOptions: [TopUpOption] = [
        TopUpOption(title: "小包充值 · 50 积分", price: "¥6.80", credits: 50, plan: nil),
        TopUpOption(title: "标准充值 · 300 积分", price: "¥30.00", credits: 300, plan: nil),
        TopUpOption(title: "Pro 月度订阅 · 2000 积分/月", price: "¥68.00/月", credits: 2000, plan: .pro),
    ]

    func purchase(_ option: TopUpOption) {
        data.subscription.credits += option.credits
        if let plan = option.plan {
            data.subscription.plan = plan
            data.subscription.renewAt = Date().addingTimeInterval(30 * 86400)
        }
        data.subscription.transactions.insert(QuotaTransaction(
            kind: option.plan == nil ? "充值" : "订阅",
            credits: option.credits, note: option.title), at: 0)
        save()
    }

    // MARK: 记忆 / 工单 / 邀请 / 导入

    func addMemory(_ text: String) {
        let c = text.trimmingCharacters(in: .whitespaces)
        guard !c.isEmpty else { return }
        data.memories.append(MemoryItem(content: c, source: "用户告知"))
        save()
    }

    func deleteMemory(_ item: MemoryItem) {
        data.memories.removeAll { $0.id == item.id }
        save()
    }

    func submitTicket(category: String, description: String) -> SupportTicket? {
        guard !description.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let t = TicketService.submit(data, category: category, description: description)
        save()
        return t
    }

    func createMagicLink() -> String {
        var code = UUID().uuidString.prefix(8).lowercased()
        code = code.replacingOccurrences(of: "-", with: "m")
        let link = "https://muse.ai/invite/\(code)"
        data.settings.magicLink = link
        save()
        return link
    }

    // MARK: v4 播客/设备/年龄/账户

    func pairDevice(name: String, code: String) {
        data.pairedDevices.append(PairedDevice(name: name, code: code))
        save()
    }

    func unpairDevice(_ device: PairedDevice) {
        data.pairedDevices.removeAll { $0.id == device.id }
        save()
    }

    func toggleCvm() {
        data.settings.cvmConnected.toggle()
        log(data.settings.cvmConnected ? "cvm.connect" : "cvm.disconnect",
            data.settings.cvmConnected ? "CVM 已连接（持久虚拟机）" : "CVM 已断开")
    }

    func completeAgeVerification() {
        data.settings.ageVerified = true
        save()
    }

    // MARK: 重置

    func resetAll() {
        data = MuseData()
        seedWelcome()
        save()
    }
}

// MARK: - 批准队列执行器（与 Windows 端 TaskExecutor 同语义）

enum TaskExecutor {
    /// 执行批准的任务（就地推进 task 状态/进度）；返回结果描述。
    @discardableResult
    static func execute(_ task: inout AgentTask, data: MuseData, baseDir: URL) -> String {
        switch task.action {
        case .reminderAdd:
            task.state = .done
            return "提醒「\(task.actionPayload ?? task.summary)」已生效"

        case .mailSend:
            let to = (task.actionPayload ?? "").split(separator: "|", maxSplits: 1).first.map(String.init) ?? ""
            task.state = .done
            return "邮件已发送给 \(to)（模拟发送，接入邮件连接器后走真实通道）"

        case .browserCheckout:
            task.action = .browserTask
            task.progress = 80
            task.state = .running
            return "结账已通过一次性虚拟信用卡完成（模拟）"

        case .fileWrite:
            let url = baseDir.appendingPathComponent("muse-output.md")
            let line = "\n\(Date()) \(task.summary)"
            try? Data(line.utf8).append(to: url)
            task.state = .done
            return "已写入 \(url.lastPathComponent)"

        case .networkGrant:
            task.network = .unlimited
            if task.title.hasPrefix("浏览器任务") {
                task.state = .running
                task.progress = 25
                return "网络访问已授权，浏览器任务开始执行（25%）"
            }
            task.state = .queued
            return "网络访问已授权，定时任务进入调度队列"

        case .browserTask:
            task.progress = min(100, task.progress + 25)
            if task.progress >= 100 {
                task.state = .done
                return "浏览器任务已完成"
            }
            if task.progress >= 75,
               task.summary.range(of: "购买|下单|结账|比价", options: .regularExpression) != nil {
                task.state = .waitingApproval
                task.action = .browserCheckout
                return "浏览器任务进行到结账环节，已请求批准（75%）"
            }
            return "浏览器任务推进至 \(task.progress)%"

        case .none:
            task.state = .done
            return "已确认。"
        }
    }
}

private extension Data {
    func append(to url: URL) {
        if let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.write(contentsOf: self)
            try? handle.close()
        } else {
            try? write(to: url)
        }
    }
}

// MARK: - 导出（对齐原版「下载你的智能体数据」）

enum ExportService {
    /// 单对话导出为 Markdown（对齐原版「下载为 Markdown 文件」）
    static func exportConversation(_ conv: Conversation, to dir: URL) -> URL {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd-HHmmss"
        let url = dir.appendingPathComponent("muse-chat-\(fmt.string(from: Date())).md")
        var lines: [String] = []
        lines.append("# \(conv.title)")
        lines.append("> 角色：\(conv.role.displayName) · 导出时间：\(fmt.string(from: Date()))")
        lines.append("")
        for m in conv.messages {
            let who = m.role == .user ? "我" : (m.role == .agent ? "Muse" : "系统")
            lines.append("**\(who)**：\(m.text.replacingOccurrences(of: "
", with: "  
"))")
            lines.append("")
        }
        try? Data(lines.joined(separator: "
").utf8).write(to: url)
        return url
    }

    static func export(_ data: MuseData, to dir: URL) -> URL {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd-HHmmss"
        let url = dir.appendingPathComponent("muse-export-\(fmt.string(from: Date())).md")

        var lines: [String] = []
        lines.append("# Muse 智能体数据导出")
        lines.append("")
        lines.append("> 账户：\(data.session?.email ?? "未登录")  ")
        lines.append("> 订阅：\(data.subscription.planText) · 剩余额度 \(String(format: "%.1f", data.subscription.credits))")
        lines.append("")
        lines.append("## 对话（\(data.conversations.count)）")
        for c in data.conversations {
            lines.append("### \(c.title)（\(c.role.displayName)）")
            for m in c.messages {
                let who = m.role == .user ? "我" : (m.role == .agent ? "Muse" : "系统")
                lines.append("- **\(who)**：\(m.text.replacingOccurrences(of: "\n", with: " "))")
            }
        }
        lines.append("")
        lines.append("## 任务（\(data.tasks.count)）")
        for t in data.tasks {
            lines.append("- [\(t.stateText)] \(t.title)：\(t.summary)（风险 \(t.risk)）")
        }
        lines.append("")
        lines.append("## 审计记录（\(data.audit.count)）")
        for a in data.audit {
            lines.append("- \(a.tool) · \(a.detail) · \(a.verdict)")
        }
        lines.append("")
        lines.append("## 额度流水（\(data.subscription.transactions.count)）")
        for t in data.subscription.transactions {
            lines.append("- \(t.kind) · \(t.credits) · \(t.note)")
        }

        let text = lines.joined(separator: "\n")
        try? Data(text.utf8).write(to: url)
        return url
    }
}
