import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - 智能体事件协议（与 docs/DESIGN.md §2.4 对齐，Windows 端同构）

enum AgentEvent {
    case status(AgentState)
    case delta(String)
    case tool(name: String, detail: String)
    case approvalRequest(title: String, summary: String, risk: String)
    case error(String)
    case alt(String)                       // A/B 双回复的方案 B
    case products([ProductCard])           // 商品网格
    case slides([Slide])                   // 幻灯片
    case ageVerificationRequired           // 需要年龄验证
    case done(creditsUsed: Double)
}

/// 可插拔后端：内置本地离线引擎；接入真实云端时实现本协议
/// （OAuth → 会话引导 → SSE 流式 → TTS，端点见设计文档 §1.2）
@MainActor
protocol AgentBackend: AnyObject {
    var name: String { get }
    func streamChat(userText: String, attachments: [Attachment], connectors: [Connector]) -> AsyncThrowingStream<AgentEvent, Error>
    func transcribe(url: URL) async -> String?
}

// MARK: - 本地离线引擎 v2
// 会话门控 + 额度扣减 + 六种角色 + 工具（找文件/记笔记/提醒/日程/邮件/浏览器任务）
// + 连接器门控 + 高危动作审批。与 Windows 端 LocalAgentBackend 同一协议语义。

@MainActor
final class LocalAgentBackend: AgentBackend {
    private weak var store: AppStore?
    private weak var auth: AuthService?

    static let costPerTurn = 0.5

    init(store: AppStore?, auth: AuthService?) {
        self.store = store
        self.auth = auth
    }

    var name: String { "本地引擎（离线）· 会话已加密" }

    func streamChat(userText: String, attachments: [Attachment], connectors: [Connector]) -> AsyncThrowingStream<AgentEvent, Error> {
        let text = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let store, let auth else {
            return AsyncThrowingStream { $0.finish() }
        }
        let role = store.currentConversation?.role ?? .general

        return AsyncThrowingStream { continuation in
            let task = Task {
                func yield(_ e: AgentEvent) { continuation.yield(e) }

                func fail(_ msg: String) {
                    yield(.error(msg))
                    continuation.finish()
                }

                do {
                    // —— 会话门控 ——
                    guard auth.current != nil else {
                        fail("请先登录 Muse 账户后再与智能体对话。")
                        return
                    }
                    // —— 额度门控 ——
                    guard store.data.subscription.credits >= LocalAgentBackend.costPerTurn else {
                        fail("已用完使用额度。你可以在「订阅」页充值或升级 Pro，充值后立即恢复服务。")
                        return
                    }

                    yield(.status(.thinking))
                    try await nap(300)

                    if !attachments.isEmpty {
                        yield(.tool(name: "file.read",
                                    detail: "已呈现 \(attachments.count) 个附件：" + attachments.map(\.name).joined(separator: "、")))
                    }

                    // —— 工具型指令 ——
                    if let target = Self.commandArg(in: text, prefixes: ["打开网页：", "打开网页:", "搜索网页：", "搜索网页:"]) {
                        yield(.tool(name: "browser.open", detail: target))
                        Self.openURL(target)
                        store.charge(0.1, "打开网页 \(target)")
                        yield(.delta("已在浏览器打开 \(target)。"))
                        yield(.done(creditsUsed: 0.1))
                        continuation.finish()
                        return
                    }

                    if let what = Self.commandArg(in: text, prefixes: ["提醒我：", "提醒我:"]) {
                        yield(.tool(name: "reminder.add", detail: what))
                        let task = AgentTask(title: "创建提醒", summary: what,
                                             risk: "low", state: .waitingApproval,
                                             action: .reminderAdd, actionPayload: what)
                        store.data.tasks.append(task)
                        store.save()
                        yield(.approvalRequest(title: task.title, summary: "创建提醒：「\(what)」", risk: "low"))
                        yield(.delta("已把「\(what)」加入提醒草稿——在「任务」页批准后生效。"))
                        store.charge(0.2, "创建提醒")
                        yield(.done(creditsUsed: 0.2))
                        continuation.finish()
                        return
                    }

                    if let what = Self.commandArg(in: text, prefixes: ["记一笔：", "记一笔:"]) {
                        yield(.tool(name: "note.add", detail: what))
                        store.appendNote(what)
                        store.log("note.add", what)
                        store.charge(0.1, "记笔记")
                        yield(.delta("已记入笔记：\(what)"))
                        yield(.done(creditsUsed: 0.1))
                        continuation.finish()
                        return
                    }

                    if let kw = Self.commandArg(in: text, prefixes: ["搜图：", "搜图:"]) {
                        yield(.tool(name: "photos.search", detail: kw))
                        yield(.delta("已在你授权的照片库中搜索「\(kw)」。接入 iCloud 照片连接器后，我可以直接整理相簿。"))
                        store.charge(0.2, "搜图")
                        yield(.done(creditsUsed: 0.2))
                        continuation.finish()
                        return
                    }

                    if Self.agendaPrefixes.contains(where: { text == $0 }) {
                        guard store.data.connectors.contains(where: { $0.id == "calendar" && $0.isEnabled && $0.canRead }) else {
                            yield(.tool(name: "calendar.read", detail: "被拒绝：日历连接器未连接"))
                            yield(.delta("我还没有日历的访问权限。请到「连接器」页连接「日历」后重试——我就能读取日程、帮你安排本周计划。"))
                            yield(.done(creditsUsed: 0.1))
                            continuation.finish()
                            return
                        }
                        let fmt = DateFormatter()
                        fmt.dateFormat = "M月d日"
                        yield(.tool(name: "calendar.read", detail: "3 个活动"))
                        yield(.delta("今天 \(fmt.string(from: Date())) 的日程：\n• 09:30 站会（30 分钟）\n• 14:00 设计评审（1 小时）\n• 17:30 与产品对齐下一版本范围"))
                        store.charge(0.2, "读取日程")
                        yield(.done(creditsUsed: 0.2))
                        continuation.finish()
                        return
                    }

                    if let parsed = Self.parseMail(text) {
                        let (to, body) = parsed
                        guard store.data.connectors.contains(where: { $0.id == "mail" && $0.isEnabled && $0.canSend }) else {
                            yield(.tool(name: "mail.draft", detail: "被拒绝：邮件连接器未连接"))
                            yield(.delta("发送邮件需要「邮件」连接器。请到「连接器」页开启后重试。"))
                            yield(.done(creditsUsed: 0.1))
                            continuation.finish()
                            return
                        }
                        let task = AgentTask(title: "发送邮件给 \(to)", summary: body, risk: "medium",
                                             state: .waitingApproval,
                                             action: .mailSend, actionPayload: "\(to)|\(body)")
                        store.data.tasks.append(task)
                        store.save()
                        yield(.tool(name: "mail.draft", detail: "收件人 \(to)"))
                        yield(.approvalRequest(title: task.title, summary: "发送邮件给 \(to)：\(body)", risk: "medium"))
                        yield(.delta("邮件草稿已就绪（收件人：\(to)）。发送前需要你在「任务」页批准。"))
                        store.charge(0.2, "邮件草稿")
                        yield(.done(creditsUsed: 0.2))
                        continuation.finish()
                        return
                    }

                    if let topic = Self.commandArg(in: text, prefixes: ["做幻灯片：", "做幻灯片:"]) {
                        yield(.status(.making))
                        try await nap(300)
                        let slides = [
                            Slide(title: topic, bullets: ["背景与目标", "我们想解决什么"]),
                            Slide(title: "现状与问题", bullets: ["当前做法的三个痛点", "量化影响"]),
                            Slide(title: "方案", bullets: ["分阶段落地路径", "关键里程碑"]),
                            Slide(title: "下一步", bullets: ["两周内可交付的第一版", "需要的信息与资源"]),
                        ]
                        yield(.tool(name: "slides.create", detail: "\(slides.count) 页"))
                        store.charge(0.5, "做幻灯片 \(topic)")
                        yield(.slides(slides))
                        yield(.delta("已生成《\(topic)》幻灯片（\(slides.count) 页）。点击气泡中的「打开编辑器」可修改内容并导出。"))
                        yield(.done(creditsUsed: 0.5))
                        continuation.finish()
                        return
                    }

                    if let topic = Self.commandArg(in: text, prefixes: ["创建播客：", "创建播客:"]) {
                        yield(.status(.making))
                        try await nap(300)
                        let script = "欢迎收听本期个人播客。今天我们聊聊「\(topic)」。\n" +
                            "首先，为什么现在值得关注这个话题？因为它正处在从概念走向日常的拐点。\n" +
                            "接着，我们看三个要点：第一，它改变的不只是工具，而是流程；第二，小步快跑比一步到位更可靠；第三，数据与隐私要提前设计。\n" +
                            "最后，留给大家一个思考题：如果明天就上手，你的第一步是什么？感谢收听，我们下期再见。"
                        let ep = PodcastEpisode(title: "vol.\(store.data.podcastEpisodes.count + 1) · \(topic)", script: script)
                        store.data.podcastEpisodes.insert(ep, at: 0)
                        store.save()
                        yield(.tool(name: "podcast.create", detail: ep.title))
                        store.charge(0.5, "创建播客 \(topic)")
                        yield(.delta("播客剧集已创建：\(ep.title)\n可在「设置 → 个人播客」中用系统语音试听或导出脚本。"))
                        yield(.done(creditsUsed: 0.5))
                        continuation.finish()
                        return
                    }

                    if let query = Self.commandArg(in: text, prefixes: ["附近：", "附近:", "导航：", "导航:"]) {
                        yield(.tool(name: "maps.search", detail: query))
                        store.lastMapQuery = query
                        yield(.delta("已在地图中打开「\(query)」的周边结果。"))
                        store.charge(0.1, "地图 \(query)")
                        yield(.done(creditsUsed: 0.1))
                        continuation.finish()
                        return
                    }

                    if let what = Self.commandArg(in: text, prefixes: ["记住：", "记住:", "记忆：", "记忆:"]) {
                        yield(.tool(name: "memory.add", detail: what))
                        store.data.memories.append(MemoryItem(content: what, source: "用户告知"))
                        store.save()
                        yield(.delta("已记住：「\(what)」。你可以在「设置 → 我的个人信息」中查看与管理记忆。"))
                        store.charge(0.1, "记忆")
                        yield(.done(creditsUsed: 0.1))
                        continuation.finish()
                        return
                    }

                    if let q = Self.commandArg(in: text, prefixes: ["A/B：", "A/B:"]) {
                        yield(.status(.working))
                        let a = "[\(role.displayName) · 方案 A] \(q)\n思路一：从成本最低路径切入，先验证核心假设，两周内出最小可用版本。"
                        let b = "[\(role.displayName) · 方案 B] \(q)\n思路二：从长期架构出发，先搭可扩展框架，牺牲短期速度换取后续迭代效率。"
                        yield(.tool(name: "dual_reply", detail: "已生成两条候选回复，请选择你偏好的回复"))
                        store.charge(0.4, "A/B 双回复")
                        yield(.alt(a))
                        yield(.delta(b))
                        yield(.done(creditsUsed: 0.4))
                        continuation.finish()
                        return
                    }

                    if let kw = Self.commandArg(in: text, prefixes: ["搜商品：", "搜商品:"]) {
                        if !store.data.settings.ageVerified {
                            yield(.tool(name: "age.verification", detail: "被拒绝：尚未完成年龄验证"))
                            store.data.audit.insert(AuditEntry(tool: "age.verification", detail: "购物请求被年龄验证拦截"), at: 0)
                            store.save()
                            yield(.ageVerificationRequired)
                            yield(.delta("购物与代买功能需要先完成年龄验证。请在弹出的验证页完成后再试。"))
                            yield(.done(creditsUsed: 0.0))
                            continuation.finish()
                            return
                        }
                        yield(.status(.working))
                        yield(.tool(name: "shopping.search", detail: kw))
                        yield(.delta("为你找到 4 件「\(kw)」相关商品："))
                        yield(.products([
                            ProductCard(name: "\(kw) · 标准版", price: "¥699", source: "示例商城"),
                            ProductCard(name: "\(kw) · 进阶版", price: "¥899", source: "示例商城"),
                            ProductCard(name: "\(kw) · 旗舰版", price: "¥1299", source: "品牌官网"),
                            ProductCard(name: "\(kw) · 历史低价（二手良品）", price: "¥459", source: "二手平台"),
                        ]))
                        store.charge(0.3, "搜商品 \(kw)")
                        yield(.done(creditsUsed: 0.3))
                        continuation.finish()
                        return
                    }

                    if let parsed = Self.parseSchedule(text) {
                        let (freq, time, what) = parsed
                        let needNetwork = what.contains("网页") || what.contains("浏览") || what.contains("资讯")
                        var task = AgentTask(title: "定时任务（\(freq) \(time)）", summary: what,
                                             risk: needNetwork ? "medium" : "low",
                                             isScheduled: true, scheduleHint: "\(freq) \(time)")
                        if needNetwork {
                            task.network = .unlimited
                            task.action = .networkGrant
                            task.state = .waitingApproval
                            store.data.tasks.append(task)
                            store.save()
                            yield(.tool(name: "schedule.create", detail: "\(freq) \(time) · \(what)"))
                            yield(.approvalRequest(title: "网络访问授权",
                                                   summary: "定时任务「\(what)」需要无限制网络访问权限（\(freq) \(time)）",
                                                   risk: "medium"))
                            yield(.delta("定时任务已创建（\(freq) \(time)）：\(what)\n它需要网络访问权限，请在「任务」页批准后生效。"))
                        } else {
                            task.state = .queued
                            store.data.tasks.append(task)
                            store.save()
                            yield(.tool(name: "schedule.create", detail: "\(freq) \(time) · \(what)"))
                            yield(.delta("定时任务已创建：\(freq) \(time) 执行「\(what)」。可在「任务」页修改或取消。"))
                        }
                        store.charge(0.2, "创建定时任务")
                        yield(.done(creditsUsed: 0.2))
                        continuation.finish()
                        return
                    }

                    if let goal = Self.commandArg(in: text, prefixes: ["创建浏览器任务：", "创建浏览器任务:"]) {
                        let needCheckout = goal.range(of: "购买|下单|结账|比价", options: .regularExpression) != nil
                        let wantUnlimited = goal.range(of: "无限制网络|任意网站", options: .regularExpression) != nil
                        var task = AgentTask(title: "浏览器任务", summary: goal,
                                             risk: needCheckout ? "high" : "low",
                                             action: .browserTask, actionPayload: goal, progress: 25)
                        if wantUnlimited {
                            task.network = .unlimited
                            task.action = .networkGrant
                            task.state = .waitingApproval
                            store.data.tasks.append(task)
                            store.save()
                            yield(.tool(name: "browser.task.create", detail: goal))
                            yield(.approvalRequest(title: "网络访问授权",
                                                   summary: "浏览器任务「\(goal)」想要无限制的网络访问权限",
                                                   risk: needCheckout ? "high" : "medium"))
                            yield(.delta("已创建浏览器任务：\(goal)\n该任务请求无限制网络访问——请在「任务」页批准后开始执行。"))
                            store.charge(0.3, "浏览器任务 \(goal)")
                            yield(.done(creditsUsed: 0.3))
                            continuation.finish()
                            return
                        }
                        if let dm = goal.range(of: "域名[:：]\\s*([a-z0-9.,，\\s]+)", options: .regularExpression) {
                            let domains = goal[dm].replacingOccurrences(of: "域名：", with: "")
                                .replacingOccurrences(of: "域名:", with: "")
                                .split(whereSeparator: { $0 == "," || $0 == "，" || $0 == " " })
                                .map(String.init).prefix(5).joined(separator: ",")
                            task.network = .domains
                            task.actionPayload = domains
                            task.summary = goal.replacingOccurrences(of: goal[dm], with: "").trimmingCharacters(in: .whitespaces)
                        }
                        task.state = .running
                        store.data.tasks.append(task)
                        store.save()
                        yield(.tool(name: "browser.task.create", detail: goal))
                        let net = task.network == .domains ? "网络：仅限 \(task.actionPayload ?? "")（域内访问无需授权）" : ""
                        yield(.delta("已创建浏览器任务（进度 25%）：\(task.summary)\n\(net)\n我会在远程浏览器里逐步执行。到「任务」页可实时查看、随时接管或停止。" +
                                     (needCheckout ? "涉及支付时，我会请求你的批准（一次性虚拟信用卡）。" : "")))
                        store.charge(0.3, "浏览器任务 \(goal)")
                        yield(.done(creditsUsed: 0.3))
                        continuation.finish()
                        return
                    }

                    // —— 一般对话（角色人格化） ——
                    try await nap(200)
                    yield(.status(.working))
                    let connected = connectors.filter(\.isEnabled).map(\.name)
                    let reply = Self.composeReply(text: text, connected: connected, role: role,
                                                  memoryCount: store.data.memories.count)
                    var chunk = ""
                    for ch in reply {
                        chunk.append(ch)
                        if chunk.count == 3 {
                            yield(.delta(chunk))
                            chunk = ""
                            try await nap(8)
                        }
                    }
                    if !chunk.isEmpty { yield(.delta(chunk)) }
                    store.charge(LocalAgentBackend.costPerTurn, "对话")
                    yield(.done(creditsUsed: LocalAgentBackend.costPerTurn))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// 离线无 ASR；接入云端后返回转写文本
    func transcribe(url: URL) async -> String? { nil }

    // MARK: helpers

    private static let agendaPrefixes = ["今天的日程", "今天的日程？", "本周的日程", "今日日程", "日程"]

    private func nap(_ ms: Int) async throws {
        if Task.isCancelled { throw CancellationError() }
        try await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
    }

    static func commandArg(in text: String, prefixes: [String]) -> String? {
        for p in prefixes where text.hasPrefix(p) {
            let arg = text.dropFirst(p.count).trimmingCharacters(in: .whitespaces)
            if !arg.isEmpty { return String(arg) }
        }
        return nil
    }

    static func parseSchedule(_ text: String) -> (String, String, String)? {
        guard text.hasPrefix("定时任务:") || text.hasPrefix("定时任务：") else { return nil }
        let rest = text.dropFirst(5).trimmingCharacters(in: .whitespaces)
        let parts = rest.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        let head = parts[0].trimmingCharacters(in: .whitespaces)
        let segs = head.split(separator: " ")
        guard segs.count == 2 else { return nil }
        let freq = String(segs[0]), time = String(segs[1])
        let what = parts[2].trimmingCharacters(in: .whitespaces)
        guard ["每天", "每周", "工作日"].contains(freq), time.contains(":") else { return nil }
        return (freq, time, what)
    }

    static func parseMail(_ text: String) -> (String, String)? {
        for marker in ["写邮件给", "发邮件给"] {
            guard text.hasPrefix(marker) else { continue }
            let rest = text.dropFirst(marker.count)
            guard let sep = rest.firstIndex(where: { $0 == ":" || $0 == "：" }) else { continue }
            let to = rest[..<sep].trimmingCharacters(in: .whitespaces)
            let body = rest[rest.index(after: sep)...].trimmingCharacters(in: .whitespaces)
            if !to.isEmpty && !body.isEmpty { return (to, body) }
        }
        return nil
    }

    private static func composeReply(text: String, connected: [String], role: AgentRole, memoryCount: Int = 0) -> String {
        let conn = connected.isEmpty
            ? "当前没有已连接的连接器——到「连接器」页把日历、邮件等接上，我能帮到更多。"
            : "我正通过这些连接器为你服务：\(connected.joined(separator: "、"))。"
        let core = text.isEmpty ? "我在。想从哪里开始？" : "收到：「\(text)」。"
        let memoryHint = memoryCount > 0 ? "\n（已结合你的 \(memoryCount) 条个人记忆）" : ""
        return "[\(role.displayName)] \(core)\(memoryHint)\n\n" +
            "\(role.persona)\n\n" +
            "我可以直接执行这些指令：\n" +
            "• 「记一笔: 内容」/「提醒我: 事项」——笔记与提醒\n" +
            "• 「搜图: 关键词」——检索你授权的照片\n" +
            "• 「今天的日程」「写邮件给 某人: 内容」「创建浏览器任务: 目标」——需对应连接器\n\n" + conn
    }

    private static func openURL(_ raw: String) {
        let s = raw.hasPrefix("http") ? raw : "https://" + raw
        guard let url = URL(string: s) else { return }
        #if canImport(UIKit)
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        #endif
    }
}
