import SwiftUI

struct SettingsScreen: View {
    @EnvironmentObject private var store: AppStore
    @State private var showResetConfirm = false
    @State private var exportURL: URL?
    @State private var showShareSheet = false
    @State private var exportMessage = ""
    @State private var showImporter = false

    // 记忆
    @State private var newMemory = ""
    // 工单
    @State private var ticketCategory = "功能问题"
    @State private var ticketDescription = ""
    @State private var ticketResult = ""
    // PIN
    @State private var newPin = ""
    @State private var pinResult = ""
    // 邀请
    @State private var magicLink = ""
    // 设备配对
    @State private var pairResult = ""
    // 账户切换
    @State private var accountResult = ""
    // OAuth 同意
    @State private var consentConnector: Connector?

    private let categories = ["功能问题", "账号与登录", "连接器", "隐私与安全", "其他"]

    var body: some View {
        NavigationView {
            Form {
                Section("账户") {
                    HStack {
                        Text(store.data.session?.email ?? "未登录")
                            .foregroundColor(Theme.textPrimary)
                        Spacer()
                        Text(store.data.subscription.planText)
                            .font(.caption)
                            .foregroundColor(Theme.accent2)
                    }
                    Button("退出登录") {
                        AuthService.shared.logout()
                        store.data.session = nil
                        store.save()
                    }
                    .foregroundColor(Theme.danger)
                }

                Section("本设备上的账户") {
                    ForEach(AuthService.shared.registeredAccounts, id: \.self) { email in
                        HStack {
                            Text(email)
                                .font(.footnote)
                                .foregroundColor(email == store.data.session?.email ? Theme.accent : Theme.textPrimary)
                            Spacer()
                            if email != store.data.session?.email {
                                Button("切换") {
                                    if AuthService.shared.switchToExistingSession(email) {
                                        store.data.session = AuthService.shared.current
                                        store.save()
                                        accountResult = "已切换到 \(email)"
                                    } else {
                                        accountResult = "「\(email)」的会话已过期，请退出登录后重新登录该账户。"
                                    }
                                }
                                .font(.caption)
                                .foregroundColor(Theme.accent)
                                Button("移除") {
                                    if AuthService.shared.removeAccount(email) {
                                        accountResult = "「\(email)」不会再显示在这台设备上。你随时可以重新登录这个账户。"
                                    }
                                }
                                .font(.caption)
                                .foregroundColor(Theme.danger)
                            }
                        }
                    }
                    if !accountResult.isEmpty {
                        Text(accountResult).font(.caption).foregroundColor(Theme.success)
                    }
                }

                Section("我的个人信息（记忆）") {
                    Text("Muse 会记住其中的持久信息；删除后即被遗忘。")
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                    ForEach(store.data.memories) { m in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.content).font(.footnote).foregroundColor(Theme.textPrimary)
                                Text(m.source).font(.caption2).foregroundColor(Theme.textSecondary)
                            }
                            Spacer()
                            Button("遗忘") { store.deleteMemory(m) }
                                .font(.caption)
                                .foregroundColor(Theme.danger)
                        }
                    }
                    HStack {
                        TextField("告诉我该记住的事", text: $newMemory)
                            .foregroundColor(Theme.textPrimary)
                        Button("记住") {
                            store.addMemory(newMemory)
                            newMemory = ""
                        }
                        .foregroundColor(Theme.accent)
                    }
                }

                Section("帮助与反馈") {
                    Picker("类别", selection: $ticketCategory) {
                        ForEach(categories, id: \.self) { Text($0) }
                    }
                    TextField("描述你遇到的问题…", text: $ticketDescription)
                        .foregroundColor(Theme.textPrimary)
                    Button("提交工单") {
                        if let t = store.submitTicket(category: ticketCategory, description: ticketDescription) {
                            ticketResult = "工单已提交：\(t.id)。我们会尽快回复。"
                            ticketDescription = ""
                        } else {
                            ticketResult = "请描述你遇到的问题"
                        }
                    }
                    .foregroundColor(Theme.accent)
                    if !ticketResult.isEmpty {
                        Text(ticketResult).font(.caption).foregroundColor(Theme.success)
                    }
                    ForEach(store.data.tickets.prefix(5)) { t in
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(t.id) · \(t.category)").font(.caption).foregroundColor(Theme.accent2)
                            Text(t.status).font(.caption2).foregroundColor(Theme.textSecondary)
                        }
                    }
                }

                Section("导入与邀请") {
                    Button("导入其他助手的聊天归档（conversations.json）") {
                        showImporter = true
                    }
                    .foregroundColor(Theme.accent)
                    Button("创建 Magic Link 邀请链接") {
                        magicLink = store.createMagicLink()
                    }
                    .foregroundColor(Theme.accent)
                    if !magicLink.isEmpty {
                        Button {
                            UIPasteboard.general.string = magicLink
                        } label: {
                            HStack {
                                Text(magicLink).font(.caption).lineLimit(1)
                                Spacer()
                                Image(systemName: "doc.on.doc").font(.caption)
                            }
                        }
                        .foregroundColor(Theme.accent2)
                    }
                }

                Section("年龄验证与安全虚拟机") {
                    HStack {
                        Text(store.data.settings.ageVerified ? "已完成年龄验证" : "未完成（购物与代买功能不可用）")
                            .font(.footnote)
                            .foregroundColor(Theme.textPrimary)
                        Spacer()
                        if !store.data.settings.ageVerified {
                            Button("完成验证") {
                                store.data.settings.ageGateActive = true
                                store.save()
                            }
                            .font(.caption)
                            .foregroundColor(Theme.accent)
                        }
                    }
                    Toggle(isOn: Binding(
                        get: { store.data.settings.cvmConnected },
                        set: { _ in store.toggleCvm() })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Muse 安全虚拟机").font(.footnote).foregroundColor(Theme.textPrimary)
                            Text("独立的持久 Linux 计算机，配备完整的浏览器，可供你和智能体完成任务（本地模拟）。")
                                .font(.caption2)
                                .foregroundColor(Theme.textSecondary)
                        }
                    }
                }

                Section("语音音色（TTS）") {
                    if TtsService.shared.voices.isEmpty {
                        Text("未检测到可用音色").font(.caption).foregroundColor(Theme.textSecondary)
                    }
                    ForEach(TtsService.shared.voices.prefix(6), id: \.identifier) { voice in
                        Button {
                            TtsService.shared.preview(voice)
                            store.data.settings.ttsVoice = voice.identifier
                            store.save()
                        } label: {
                            HStack {
                                Text(voice.name).font(.footnote).foregroundColor(Theme.textPrimary)
                                Spacer()
                                if store.data.settings.ttsVoice == voice.identifier {
                                    Image(systemName: "checkmark").font(.caption).foregroundColor(Theme.accent)
                                }
                                Text("试听").font(.caption2).foregroundColor(Theme.accent2)
                            }
                        }
                    }
                }

                Section("个人播客") {
                    ForEach(store.data.podcastEpisodes.prefix(10)) { ep in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ep.title).font(.footnote).foregroundColor(Theme.textPrimary)
                                Text(ep.createdAt.formatted(date: .numeric, time: .shortened))
                                    .font(.caption2).foregroundColor(Theme.textSecondary)
                            }
                            Spacer()
                            Button("▶ 播放") { TtsService.shared.speak(ep.script) }
                                .font(.caption).foregroundColor(Theme.accent)
                            Button("导出") {
                                let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                                let url = dir.appendingPathComponent("podcast-\(ep.id).md")
                                try? Data("# \(ep.title)\n\n\(ep.script)".utf8).write(to: url)
                                exportURL = url
                                showShareSheet = true
                            }
                            .font(.caption).foregroundColor(Theme.accent)
                        }
                    }
                    if store.data.podcastEpisodes.isEmpty {
                        Text("还没有剧集。对智能体说「创建播客: 主题」即可生成第一期。")
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                    }
                }

                Section("设备配对（Muse Link）") {
                    Button("生成配对码") {
                        let code = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8).uppercased())
                        store.pairDevice(name: "我的设备 · \(store.data.pairedDevices.count + 1)", code: code)
                        pairResult = "配对码 \(code) 已生成——在另一台设备上输入即可完成 Link（本地模拟）。"
                    }
                    .foregroundColor(Theme.accent)
                    if !pairResult.isEmpty {
                        Text(pairResult).font(.caption).foregroundColor(Theme.success)
                    }
                    ForEach(store.data.pairedDevices) { device in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(device.name).font(.footnote).foregroundColor(Theme.textPrimary)
                                Text("配对码 \(device.code)").font(.caption2).foregroundColor(Theme.textSecondary)
                            }
                            Spacer()
                            Button("从其他设备退出") { store.unpairDevice(device) }
                                .font(.caption)
                                .foregroundColor(Theme.danger)
                        }
                    }
                }

                Section("应用锁与外观") {
                    if store.data.settings.pinEnabled {
                        Button("关闭 PIN 锁") {
                            PinService.disable()
                            pinResult = "PIN 已关闭"
                        }
                        .foregroundColor(Theme.danger)
                        Text("PIN 锁已启用，启动应用时需要解锁")
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                    } else {
                        SecureField("设置 4-6 位数字 PIN", text: $newPin)
                            .keyboardType(.numberPad)
                        Button("启用 PIN 锁") {
                            let p = newPin.trimmingCharacters(in: .whitespaces)
                            if p.count >= 4, p.count <= 6, p.allSatisfy(\.isNumber) {
                                PinService.setPin(p)
                                newPin = ""
                                pinResult = "PIN 已启用，下次启动需要解锁"
                            } else {
                                pinResult = "PIN 需为 4-6 位数字"
                            }
                        }
                        .foregroundColor(Theme.accent)
                    }
                    if !pinResult.isEmpty {
                        Text(pinResult).font(.caption).foregroundColor(Theme.success)
                    }
                    Picker("外观", selection: $store.data.settings.appearance) {
                        Text("深色").tag("dark")
                        Text("浅色").tag("light")
                    }
                    .onChange(of: store.data.settings.appearance) { _ in store.save() }
                }

                Section("语音与输入") {
                    Toggle("朗读助手回复（TTS）", isOn: $store.data.settings.ttsEnabled)
                        .onChange(of: store.data.settings.ttsEnabled) { _ in store.save() }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("按住说话 / 免手动")
                            .foregroundColor(Theme.textPrimary)
                        Text("对话页的麦克风按钮：按住说话，松开发送；快捷键语义为开始/停止切换。首次使用会请求麦克风与语音识别权限。")
                            .font(.footnote)
                            .foregroundColor(Theme.textSecondary)
                    }
                    .padding(.vertical, 2)
                }

                Section("隐私与安全") {
                    permissionRow(icon: "mic.fill", title: "麦克风", desc: "语音输入需要访问麦克风")
                    permissionRow(icon: "waveform.badge.magnifyingglass", title: "语音识别", desc: "用于转写你的语音消息")
                    permissionRow(icon: "photo.on.rectangle", title: "照片", desc: "同步照片与视频进行内容理解和媒体编辑")
                    permissionRow(icon: "lock.shield", title: "文件访问", desc: "仅在你明确要求时读取文件；所有数据保存在本机")
                }

                Section("关于") {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("6.0.0 (iOS)")
                            .foregroundColor(Theme.textSecondary)
                    }
                    HStack {
                        Text("助手后端")
                        Spacer()
                        Text("本地引擎（离线）")
                            .foregroundColor(Theme.textSecondary)
                    }
                    Button("下载我的智能体数据") {
                        let url = ExportService.export(store.data, to: FileManager.default
                            .urls(for: .documentDirectory, in: .userDomainMask)[0])
                        exportURL = url
                        showShareSheet = true
                        exportMessage = "已导出：\(url.lastPathComponent)"
                    }
                    .foregroundColor(Theme.accent)
                    if !exportMessage.isEmpty {
                        Text(exportMessage)
                            .font(.caption)
                            .foregroundColor(Theme.success)
                    }

                    Button("重置应用数据") {
                        showResetConfirm = true
                    }
                    .foregroundColor(Theme.danger)
                }

                Section {
                    Text("Muse · 个人 AI 智能体\n隐私：对话与文件默认仅保存在本机。接入云端后端时，仅传输你明确发送的内容。")
                        .font(.caption2)
                        .foregroundColor(Theme.textSecondary)
                }
            }
            .navigationTitle("设置")
            .confirmationDialog("确定要重置全部应用数据吗？此操作不可撤销。", isPresented: $showResetConfirm, titleVisibility: .visible) {
                Button("重置", role: .destructive) { store.resetAll() }
                Button("取消", role: .cancel) {}
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = exportURL {
                    ShareSheet(items: [url])
                }
            }
            .sheet(isPresented: Binding(
                get: { store.data.settings.ageGateActive },
                set: { if !$0 {
                    store.data.settings.ageGateActive = false
                    store.save()
                }})) {
                AgeVerificationSheet()
            }
            .sheet(item: $consentConnector) { connector in
                OAuthConsentSheet(connector: connector) { granted in
                    if granted {
                        store.setConnectorEnabled(connector, enabled: true)
                    }
                    consentConnector = nil
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json, .data]) { result in
                switch result {
                case .success(let url):
                    let secured = url.startAccessingSecurityScopedResource()
                    defer { if secured { url.stopAccessingSecurityScopedResource() } }
                    do {
                        let raw = try Data(contentsOf: url)
                        let r = try ImportService.importJSON(raw, into: store.data)
                        store.save()
                        exportMessage = "导入成功：\(r.conversations) 个对话、\(r.memories) 条记忆。"
                    } catch {
                        exportMessage = "导入失败：\(error.localizedDescription)"
                    }
                case .failure(let error):
                    exportMessage = "导入失败：\(error.localizedDescription)"
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func permissionRow(icon: String, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .frame(width: 22)
                .foregroundColor(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundColor(Theme.textPrimary)
                Text(desc)
                    .font(.footnote)
                    .foregroundColor(Theme.textSecondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// UIActivityViewController 封装（iOS 15 兼容的分享导出）
struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
