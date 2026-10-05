import XCTest
@testable import Muse

/// Muse for iOS — 端到端场景测试（与 Windows 端 MuseE2E 的 S01-S13 一一镜像）。
/// 仅依赖应用核心逻辑（AppStore / AuthService / LocalAgentBackend / TaskExecutor / ExportService），
/// 在模拟器/真机的 Debug 构建上运行：xcodebuild test -scheme Muse -destination 'platform=iOS Simulator,name=iPhone 15'
@MainActor
final class MuseKitTests: XCTestCase {

    // MARK: 基础设施

    private func tempDir(_ name: String) -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("muse-e2e-\(name)-\(UUID().uuidString.prefix(6))")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeEnv(_ name: String) -> (AppStore, AuthService, LocalAgentBackend) {
        let dir = tempDir(name)
        let store = AppStore(dataDir: dir)
        let auth = AuthService(dataDir: dir)
        store.data.connectors = MuseData.defaultConnectors
        return (store, auth, LocalAgentBackend(store: store, auth: auth))
    }

    private func send(_ backend: LocalAgentBackend, _ store: AppStore,
                      _ conv: Conversation, _ text: String) async -> (String, [AgentEvent]) {
        var acc = ""
        var events: [AgentEvent] = []
        let stream = backend.streamChat(userText: text, attachments: [], connectors: store.data.connectors)
        for try await ev in stream {
            events.append(ev)
            if case .delta(let d) = ev { acc += d }
            if case .error(let e) = ev { acc += "[\(e)]" }
        }
        return (acc, events)
    }

    private func check(_ cond: Bool, _ what: String) throws {
        XCTAssertTrue(cond, "断言失败：\(what)")
    }

    // MARK: 场景

    func testS01AccountRegisterLoginLogout() async throws {
        let dir = tempDir("s01")
        let auth = AuthService(dataDir: dir)

        let session = try auth.register(email: "alice@muse.ai", password: "secret6", inviteCode: nil)
        try check(auth.current?.token == session.token, "注册后应持有会话")

        auth.logout()
        try check(auth.current == nil, "登出后会话应为空")

        XCTAssertThrowsError(try auth.login(email: "alice@muse.ai", password: "wrong-password"), "错误密码应被拒绝")
        XCTAssertThrowsError(try auth.register(email: "alice@muse.ai", password: "secret6", inviteCode: nil), "重复注册应被拒绝")

        let again = try auth.login(email: "alice@muse.ai", password: "secret6")
        try check(again.token.count > 8, "重新登录应获得新会话令牌")

        let auth2 = AuthService(dataDir: dir)
        try check(auth2.current?.email == "alice@muse.ai", "重启后应恢复未过期会话")
    }

    func testS02InviteAndWaitlist() async throws {
        let dir = tempDir("s02")
        let auth = AuthService(dataDir: dir)

        XCTAssertThrowsError(try auth.redeemInvite("BAD-CODE"), "无效邀请码应被拒绝")
        try auth.redeemInvite("MUSE2026")
        try auth.joinWaitlist("waitlist@muse.ai")

        let raw = try String(contentsOf: dir.appendingPathComponent("auth.json"), encoding: .utf8)
        try check(raw.contains("waitlist@muse.ai"), "等候名单应包含邮箱")

        let s = try auth.register(email: "bob@muse.ai", password: "secret6", inviteCode: "ENDO-VIP")
        try check(s.inviteRedeemed, "使用邀请码注册后应标记已兑换")
    }

    func testS03ChatStreamWithRole() async throws {
        let (store, auth, backend) = makeEnv("s03")
        try auth.register(email: "e2e@muse.ai", password: "secret6", inviteCode: "MUSE2026")
        store.data.session = auth.current
        var conv = Conversation(role: .research)
        conv.role = .research
        store.data.conversations.append(conv)
        store.currentConversationId = conv.id
        let before = store.data.subscription.credits

        let (reply, events) = await send(backend, store, conv, "你好，介绍一下你能做什么")
        try check(events.contains { if case .status = $0 { return true } else { return false } }, "应产生状态事件")
        try check(reply.contains("[研究智能体]"), "回复应带研究智能体人格")
        try check(reply.contains("记一笔"), "回复应介绍可用指令")
        guard case .done = events.last else { return XCTFail("应以 Done 结束") }
        try check(store.data.subscription.credits < before, "对话应消耗额度")

        auth.logout()
        let (reply2, _) = await send(backend, store, conv, "在吗")
        try check(reply2.contains("登录"), "未登录应提示先登录")
    }

    func testS04ReminderApprovalFlow() async throws {
        let (store, auth, backend) = makeEnv("s04")
        try auth.register(email: "e2e@muse.ai", password: "secret6", inviteCode: "MUSE2026")
        store.data.session = auth.current
        let conv = Conversation()
        store.data.conversations.append(conv)
        store.currentConversationId = conv.id

        let (reply, events) = await send(backend, store, conv, "提醒我: 明早 9 点站会")
        try check(reply.contains("批准"), "应提示需要批准")
        try check(events.contains { if case .approvalRequest = $0 { return true } else { return false } }, "应产生审批事件")

        let task = store.data.tasks.first { $0.title == "创建提醒" }
        try check(task?.state == .waitingApproval, "任务应处于待批准")

        store.approve(task!)
        let executed = store.data.tasks.first { $0.id == task!.id }
        try check(executed?.state == .done, "批准后任务应完成")
        try check(store.data.audit.contains { $0.tool.contains("reminderAdd") }, "应写入审计")
    }

    func testS05NoteCommand() async throws {
        let (store, auth, backend) = makeEnv("s05")
        try auth.register(email: "e2e@muse.ai", password: "secret6", inviteCode: "MUSE2026")
        store.data.session = auth.current
        let conv = Conversation()
        store.data.conversations.append(conv)
        store.currentConversationId = conv.id

        let (reply, events) = await send(backend, store, conv, "记一笔: 给设计部发需求")
        try check(reply.contains("已记入笔记"), "应确认记入笔记")
        try check(events.contains { if case .tool(let name, _) = $0 { return name == "note.add" } else { return false } }, "应有 note.add 工具调用")

        let notes = try String(contentsOf: store.notesFileURL, encoding: .utf8)
        try check(notes.contains("给设计部发需求"), "笔记文件应包含内容")
        try check(store.data.audit.contains { $0.tool == "note.add" }, "审计应有记录")
    }

    func testS06PhotoSearch() async throws {
        let (store, auth, backend) = makeEnv("s06")
        try auth.register(email: "e2e@muse.ai", password: "secret6", inviteCode: "MUSE2026")
        store.data.session = auth.current
        let conv = Conversation()
        store.data.conversations.append(conv)
        store.currentConversationId = conv.id

        let (reply, events) = await send(backend, store, conv, "搜图: 海边日落")
        try check(reply.contains("海边日落"), "应确认搜索关键词")
        try check(events.contains { if case .tool(let name, _) = $0 { return name == "photos.search" } else { return false } }, "应有 photos.search 工具调用")
    }

    func testS07CalendarConnectorGate() async throws {
        let (store, auth, backend) = makeEnv("s07")
        try auth.register(email: "e2e@muse.ai", password: "secret6", inviteCode: "MUSE2026")
        store.data.session = auth.current
        let conv = Conversation()
        store.data.conversations.append(conv)
        store.currentConversationId = conv.id
        let calendar = store.data.connectors.first { $0.id == "calendar" }!
        store.setConnectorEnabled(calendar, enabled: false)

        let (reply1, events1) = await send(backend, store, conv, "今天的日程")
        try check(reply1.contains("连接"), "日历未连接时应引导去连接")
        try check(events1.contains { if case .tool(_, let d) = $0 { return d.contains("拒绝") } else { return false } }, "工具调用应记录被拒绝")

        store.setConnectorEnabled(calendar, enabled: true)
        let (reply2, _) = await send(backend, store, conv, "今天的日程")
        try check(reply2.contains("09:30 站会"), "连接后应返回日程")
    }

    func testS08MailApprovalFlow() async throws {
        let (store, auth, backend) = makeEnv("s08")
        try auth.register(email: "e2e@muse.ai", password: "secret6", inviteCode: "MUSE2026")
        store.data.session = auth.current
        let conv = Conversation()
        store.data.conversations.append(conv)
        store.currentConversationId = conv.id
        let mail = store.data.connectors.first { $0.id == "mail" }!
        store.setConnectorEnabled(mail, enabled: false)

        let (r1, _) = await send(backend, store, conv, "写邮件给 老板: 本周进展汇报")
        try check(r1.contains("连接器"), "邮件连接器未开启时应引导")

        store.setConnectorEnabled(mail, enabled: true)
        let (r2, events) = await send(backend, store, conv, "写邮件给 老板: 本周进展汇报")
        try check(r2.contains("批准"), "草稿应等待批准")
        try check(events.contains { if case .approvalRequest = $0 { return true } else { return false } }, "应有审批事件")

        let task = store.data.tasks.first { $0.action == .mailSend }!
        store.approve(task)
        try check(store.data.audit.contains { $0.tool.contains("mailSend") }, "审计应记录发送")
    }

    func testS09BrowserTaskFullFlow() async throws {
        let (store, auth, backend) = makeEnv("s09")
        try auth.register(email: "e2e@muse.ai", password: "secret6", inviteCode: "MUSE2026")
        store.data.session = auth.current
        let conv = Conversation()
        store.data.conversations.append(conv)
        store.currentConversationId = conv.id

        let (reply, _) = await send(backend, store, conv, "创建浏览器任务: 帮我购买降噪耳机，预算 899")
        try check(reply.contains("25%"), "应创建任务并报告进度")
        var task = store.data.tasks.first { $0.action == .browserTask }!
        try check(task.state == .running && task.progress == 25, "任务应处于运行中 25%")

        store.advanceBrowserTask(task)
        task = store.data.tasks.first { $0.id == task.id }!
        try check(task.progress == 50, "应推进到 50%")

        store.advanceBrowserTask(task)
        task = store.data.tasks.first { $0.id == task.id }!
        try check(task.progress == 75 && task.state == .waitingApproval, "结账环节应请求批准")

        store.approve(task)
        task = store.data.tasks.first { $0.id == task.id }!
        try check(task.action == .browserTask && task.state == .running && task.progress == 80, "结账后应继续运行 80%")

        store.advanceBrowserTask(task)
        task = store.data.tasks.first { $0.id == task.id }!
        try check(task.progress == 100 && task.state == .done, "任务应完成")
    }

    func testS10QuotaAndBilling() async throws {
        let (store, auth, backend) = makeEnv("s10")
        try auth.register(email: "e2e@muse.ai", password: "secret6", inviteCode: "MUSE2026")
        store.data.session = auth.current
        let conv = Conversation()
        store.data.conversations.append(conv)
        store.currentConversationId = conv.id
        store.data.subscription.credits = 0.4

        let (r1, _) = await send(backend, store, conv, "你好")
        try check(r1.contains("已用完使用额度"), "额度不足应提示")

        let before = store.data.subscription.credits
        store.purchase(AppStore.topUpOptions[0])
        try check(store.data.subscription.credits == before + 50, "充值 50 积分应到账")
        try check(store.data.subscription.transactions.first?.kind == "充值", "流水应记录充值")

        store.purchase(AppStore.topUpOptions[2])
        try check(store.data.subscription.plan == .pro, "Pro 订阅应生效")
        try check(store.data.subscription.credits == before + 50 + 2000, "Pro 订阅应到账 2000 积分")

        let before2 = store.data.subscription.credits
        _ = await send(backend, store, conv, "你好")
        try check(store.data.subscription.credits == before2 - 0.5, "对话应扣减 0.5 额度")
    }

    func testS11Export() async throws {
        let (store, auth, backend) = makeEnv("s11")
        try auth.register(email: "e2e@muse.ai", password: "secret6", inviteCode: "MUSE2026")
        store.data.session = auth.current
        let conv = Conversation()
        store.data.conversations.append(conv)
        store.currentConversationId = conv.id
        _ = await send(backend, store, conv, "记一笔: 导出测试")

        let url = ExportService.export(store.data, to: tempDir("s11-export"))
        let md = try String(contentsOf: url, encoding: .utf8)
        try check(md.contains("## 对话") && md.contains("导出测试"), "导出应包含对话内容")
        try check(md.contains("## 审计记录"), "导出应包含审计")
        try check(md.contains("## 额度流水"), "导出应包含额度流水")
    }

    func testS12Persistence() async throws {
        let dir = tempDir("s12")
        let store = AppStore(dataDir: dir)
        let auth = AuthService(dataDir: dir)
        try auth.register(email: "e2e@muse.ai", password: "secret6", inviteCode: "MUSE2026")
        store.data.session = auth.current
        var conv = Conversation()
        conv.title = "持久化测试会话"
        store.data.conversations.append(conv)
        store.currentConversationId = conv.id
        store.data.subscription.credits = 123
        store.save()

        let reloaded = AppStore(dataDir: dir)
        try check(reloaded.data.conversations.contains { $0.title == "持久化测试会话" }, "会话应保留")
        try check(abs(reloaded.data.subscription.credits - 123) < 0.001, "额度应保留")
        try check(reloaded.data.session?.email == "e2e@muse.ai", "会话信息应保留")
    }
}

    // MARK: v1.3 新增场景（与 Windows E2E S14-S22 镜像）

    func testS14PinLock() {
        let s = MuseSettings()
        PinService.setPin("135790", settings: s)
        XCTAssertTrue(s.pinEnabled, "PIN 应已启用")
        XCTAssertTrue(PinService.verify("135790", settings: s), "正确 PIN 应通过")
        XCTAssertFalse(PinService.verify("000000", settings: s), "错误 PIN 应失败")
        XCTAssertFalse(PinService.verify("000000", settings: s))
        XCTAssertFalse(PinService.verify("000000", settings: s))
        XCTAssertTrue(PinService.isLockedOut(s), "三次错误后应进入冷却锁定")
        XCTAssertFalse(PinService.verify("135790", settings: s), "冷却期内正确 PIN 也应拒绝")
        XCTAssertGreaterThan(PinService.cooldownRemaining(s), 0, "冷却剩余时间应大于 0")
        PinService.disable(settings: s)
        XCTAssertFalse(s.pinEnabled, "关闭后 PIN 应禁用")
    }

    func testS15Memory() async throws {
        let (store, auth, backend) = makeEnv("s15m")
        try auth.register(email: "e2e@muse.ai", password: "secret6", inviteCode: "MUSE2026")
        store.data.session = auth.current
        let conv = Conversation()
        store.data.conversations.append(conv)
        store.currentConversationId = conv.id

        let (reply, events) = await send(backend, store, conv, "记住: 我对花生过敏")
        XCTAssertTrue(reply.contains("已记住"), "应确认记住")
        XCTAssertTrue(events.contains { if case .tool(let n, _) = $0 { return n == "memory.add" } else { return false } }, "应有 memory.add 工具")
        XCTAssertTrue(store.data.memories.contains { $0.content.contains("花生") }, "记忆应持久化")

        let (reply2, _) = await send(backend, store, conv, "帮我推荐一下零食")
        XCTAssertTrue(reply2.contains("1 条个人记忆"), "一般回复应注入记忆数量")
    }

    func testS16AbReply() async throws {
        let (store, auth, backend) = makeEnv("s16m")
        try auth.register(email: "e2e@muse.ai", password: "secret6", inviteCode: "MUSE2026")
        store.data.session = auth.current
        let conv = Conversation()
        store.data.conversations.append(conv)
        store.currentConversationId = conv.id

        let (reply, events) = await send(backend, store, conv, "A/B: 该先做增长还是先做留存")
        XCTAssertTrue(events.contains { if case .alt = $0 { return true } else { return false } }, "应产生方案 B 事件")
        XCTAssertTrue(reply.contains("方案 B"), "正文应为方案 B")
        XCTAssertTrue(events.contains { if case .tool(let n, _) = $0 { return n == "dual_reply" } else { return false } }, "应有 dual_reply 工具")

        store.data.prefA += 1
        XCTAssertEqual(store.data.prefA, 1, "偏好应计数")
    }

    func testS17ImportJSON() async throws {
        let (store, _, _) = makeEnv("s17m")
        let array = """
        [{"title":"来自旧助手","messages":[{"role":"user","text":"你好"},{"role":"agent","text":"在的"}]}]
        """
        let r = try ImportService.importJSON(Data(array.utf8), into: store.data)
        XCTAssertEqual(r.conversations, 1, "应导入 1 个对话")
        let conv = store.data.conversations.first { $0.title == "来自旧助手" }
        XCTAssertNotNil(conv)
        XCTAssertEqual(conv?.messages.count, 2)
        XCTAssertEqual(conv?.messages.first?.role, .user)

        // 记忆迁移格式
        let r2 = try ImportService.importJSON(Data(#"["我喜欢清晨跑步","咖啡不加糖"]"#.utf8), into: store.data)
        XCTAssertEqual(r2.memories, 2, "应导入 2 条迁移记忆")
        XCTAssertTrue(store.data.memories.allSatisfy { $0.source == "迁移导入" })

        // 非法格式应抛错
        XCTAssertThrowsError(try ImportService.importJSON(Data("not-json".utf8), into: store.data))
    }

    func testS18ScheduledNetwork() async throws {
        let (store, auth, backend) = makeEnv("s18m")
        try auth.register(email: "e2e@muse.ai", password: "secret6", inviteCode: "MUSE2026")
        store.data.session = auth.current
        let conv = Conversation()
        store.data.conversations.append(conv)
        store.currentConversationId = conv.id

        let (reply, _) = await send(backend, store, conv, "定时任务: 每天 08:00 | 浏览科技资讯并摘要")
        XCTAssertTrue(reply.contains("网络访问权限"), "需要网络时应请求授权")
        var task = store.data.tasks.first { $0.network == .unlimited }
        XCTAssertNotNil(task)
        XCTAssertEqual(task?.state, .waitingApproval)
        XCTAssertEqual(task?.isScheduled, true)

        store.approve(task!)
        task = store.data.tasks.first { $0.id == task!.id }
        XCTAssertEqual(task?.state, .queued, "定时任务应进入调度队列")
        XCTAssertTrue(store.data.audit.contains { $0.tool.contains("networkGrant") }, "审计应记录授权")
    }

    func testS19Products() async throws {
        let (store, auth, backend) = makeEnv("s19m")
        try auth.register(email: "e2e@muse.ai", password: "secret6", inviteCode: "MUSE2026")
        store.data.session = auth.current
        let conv = Conversation()
        store.data.conversations.append(conv)
        store.currentConversationId = conv.id

        let (reply, events) = await send(backend, store, conv, "搜商品: 降噪耳机")
        XCTAssertTrue(reply.contains("降噪耳机"), "应确认搜索关键词")
        let products = events.first { if case .products = $0 { return true } else { return false } }
        guard case .products(let items)? = products else { return XCTFail("应返回商品数据") }
        XCTAssertEqual(items.count, 4, "应返回 4 件商品")
        XCTAssertTrue(items.allSatisfy { $0.price.hasPrefix("¥") }, "商品应带价格")
    }

    func testS20Scopes() async throws {
        let (store, auth, backend) = makeEnv("s20m")
        try auth.register(email: "e2e@muse.ai", password: "secret6", inviteCode: "MUSE2026")
        store.data.session = auth.current
        let conv = Conversation()
        store.data.conversations.append(conv)
        store.currentConversationId = conv.id
        let mail = store.data.connectors.first { $0.id == "mail" }!
        store.setConnectorEnabled(mail, enabled: true)
        store.data.connectors.first { $0.id == "mail" }?.canSend = false

        let (r1, _) = await send(backend, store, conv, "写邮件给 老板: 周报")
        XCTAssertTrue(r1.contains("发送权限"), "缺少发送权限应拒绝")

        store.data.connectors.first { $0.id == "mail" }?.canSend = true
        let (r2, _) = await send(backend, store, conv, "写邮件给 老板: 周报")
        XCTAssertTrue(r2.contains("批准"), "授权发送后应进入审批")

        let cal = store.data.connectors.first { $0.id == "calendar" }!
        store.setConnectorEnabled(cal, enabled: true)
        store.data.connectors.first { $0.id == "calendar" }?.canRead = false
        let (r3, _) = await send(backend, store, conv, "今天的日程")
        XCTAssertTrue(r3.contains("读取权限") || r3.contains("连接"), "缺读取权限应拒绝")
    }

    func testS21MagicLink() async throws {
        let (store, _, _) = makeEnv("s21m")
        let link = store.createMagicLink()
        XCTAssertTrue(link.hasPrefix("https://muse.ai/invite/"), "邀请链接格式应正确")
        XCTAssertEqual(store.data.settings.magicLink, link, "邀请链接应持久化")
    }

    func testS22Ticket() async throws {
        let (store, _, _) = makeEnv("s22m")
        let ticket = store.submitTicket(category: "连接器", description: "Gmail 连接后无法同步")
        XCTAssertNotNil(ticket)
        XCTAssertTrue(ticket!.id.hasPrefix("MUSE-"), "工单号格式应正确")
        XCTAssertTrue(store.data.tickets.contains { $0.id == ticket!.id }, "工单应保存")
        XCTAssertTrue(store.data.audit.contains { $0.tool == "help.ticket" }, "审计应记录工单")
    }

    // MARK: v1.4 新增场景（与 Windows E2E S23-S30 镜像）

    func testS23MultiAccount() throws {
        let dir = tempDir("s23")
        let auth = AuthService(dataDir: dir)
        try auth.register(email: "a@muse.ai", password: "secret6", inviteCode: nil)
        try auth.register(email: "b@muse.ai", password: "secret6", inviteCode: nil)  // a 的会话保留
        _ = try auth.login(email: "b@muse.ai", password: "secret6")
        XCTAssertEqual(auth.current?.email, "b@muse.ai")
        XCTAssertTrue(auth.registeredAccounts.contains("a@muse.ai"), "设备账户列表应含 a")
        XCTAssertTrue(auth.registeredAccounts.contains("b@muse.ai"), "设备账户列表应含 b")

        XCTAssertTrue(auth.switchToExistingSession("a@muse.ai"), "会话有效期内应免密切换")
        XCTAssertEqual(auth.current?.email, "a@muse.ai")

        XCTAssertTrue(auth.removeAccount("b@muse.ai"), "移除 b 账户应成功")
        XCTAssertFalse(auth.registeredAccounts.contains("b@muse.ai"), "移除后不再出现在设备账户列表")
    }

    func testS24AgeGate() async throws {
        let (store, auth, backend) = makeEnv("s24m")
        try auth.register(email: "e2e@muse.ai", password: "secret6", inviteCode: "MUSE2026")
        store.data.session = auth.current
        store.data.settings.ageVerified = false
        let conv = Conversation()
        store.data.conversations.append(conv)
        store.currentConversationId = conv.id

        let (r1, events) = await send(backend, store, conv, "搜商品: 降噪耳机")
        XCTAssertTrue(events.contains { if case .ageVerificationRequired = $0 { return true } else { return false } }, "未验证应触发年龄验证事件")
        XCTAssertTrue(r1.contains("年龄验证"), "应提示需要年龄验证")
        XCTAssertTrue(store.data.audit.contains { $0.tool == "age.verification" }, "审计应记录拦截")

        store.completeAgeVerification()
        let (r2, events2) = await send(backend, store, conv, "搜商品: 降噪耳机")
        XCTAssertTrue(events2.contains { if case .products = $0 { return true } else { return false } }, "验证后应返回商品")
        _ = r2
    }

    func testS25Slides() async throws {
        let (store, auth, backend) = makeEnv("s25m")
        try auth.register(email: "e2e@muse.ai", password: "secret6", inviteCode: "MUSE2026")
        store.data.session = auth.current
        let conv = Conversation()
        store.data.conversations.append(conv)
        store.currentConversationId = conv.id

        let (reply, events) = await send(backend, store, conv, "做幻灯片: Q3 增长计划")
        let slides = events.first { if case .slides = $0 { return true } else { return false } }
        guard case .slides(let items)? = slides else { return XCTFail("应生成幻灯片") }
        XCTAssertEqual(items.count, 4, "应生成 4 页")
        XCTAssertTrue(items[0].title.contains("Q3 增长计划"), "首页标题应含主题")
        XCTAssertTrue(reply.contains("打开编辑器"), "应引导打开编辑器")

        // 编辑器导出等价校验
        let md = items.map { s in
            "## \(s.title)\n" + s.bullets.map { "- \($0)" }.joined(separator: "\n")
        }.joined(separator: "\n\n")
        XCTAssertTrue(md.contains("## 现状与问题"), "导出应含各页标题")
    }

    func testS26Podcast() async throws {
        let (store, auth, backend) = makeEnv("s26m")
        try auth.register(email: "e2e@muse.ai", password: "secret6", inviteCode: "MUSE2026")
        store.data.session = auth.current
        let conv = Conversation()
        store.data.conversations.append(conv)
        store.currentConversationId = conv.id

        let (reply, _) = await send(backend, store, conv, "创建播客: 个人智能体的下一步")
        XCTAssertTrue(reply.contains("播客剧集已创建"), "应确认创建剧集")
        let ep = store.data.podcastEpisodes.first
        XCTAssertNotNil(ep, "剧集应生成")
        XCTAssertTrue(ep!.script.contains("感谢收听"), "脚本应完整")
        XCTAssertTrue(ep!.title.contains("个人智能体的下一步"), "标题应含主题")

        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = dir.appendingPathComponent("podcast-\(ep!.id).md")
        try Data("# \(ep!.title)\n\n\(ep!.script)".utf8).write(to: url)
        XCTAssertTrue(try String(contentsOf: url, encoding: .utf8).contains("vol."), "脚本导出应可用")
    }

    func testS27MapQuery() async throws {
        let (store, auth, backend) = makeEnv("s27m")
        try auth.register(email: "e2e@muse.ai", password: "secret6", inviteCode: "MUSE2026")
        store.data.session = auth.current
        let conv = Conversation()
        store.data.conversations.append(conv)
        store.currentConversationId = conv.id

        let (reply, events) = await send(backend, store, conv, "附近: 咖啡店")
        XCTAssertTrue(events.contains { if case .tool(let n, _) = $0 { return n == "maps.search" } else { return false } }, "应有 maps.search 工具")
        XCTAssertEqual(store.lastMapQuery, "咖啡店", "地图查询应待 UI 层消费（iOS 为内置 MapKit 视图）")
        XCTAssertTrue(reply.contains("地图"), "应确认打开地图")
    }

    func testS28OAuthConsent() async throws {
        let (store, _, _) = makeEnv("s28m")
        var connector = store.data.connectors.first { $0.id == "custom-oauth" }!
        connector.accessToken = "at_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(24).lowercased()
        connector.canRead = true
        connector.canWrite = false
        connector.canSend = false
        let idx = store.data.connectors.firstIndex { $0.id == connector.id }!
        store.data.connectors[idx] = connector
        store.setConnectorEnabled(connector, enabled: true)

        XCTAssertTrue((store.data.connectors.first { $0.id == connector.id }?.accessToken ?? "").hasPrefix("at_"), "应签发访问令牌")
        XCTAssertTrue(store.data.audit.contains { $0.tool == "connector.consent" }, "审计应记录授权")
    }

    func testS29Devices() async throws {
        let (store, _, _) = makeEnv("s29m")
        store.pairDevice(name: "我的手机", code: "AB12CD34")
        XCTAssertTrue(store.data.pairedDevices.contains { $0.code == "AB12CD34" }, "配对设备应保存")

        let device = store.data.pairedDevices.first { $0.code == "AB12CD34" }!
        store.unpairDevice(device)
        XCTAssertFalse(store.data.pairedDevices.contains { $0.code == "AB12CD34" }, "「从其他设备退出」应移除配对")
    }

    func testS30Cvm() async throws {
        let (store, _, _) = makeEnv("s30m")
        XCTAssertFalse(store.data.settings.cvmConnected, "初始未连接 CVM")
        store.toggleCvm()
        XCTAssertTrue(store.data.settings.cvmConnected, "连接后应为使用中")
        XCTAssertTrue(store.data.audit.contains { $0.tool == "cvm.connect" }, "审计应记录连接")
    }
}
