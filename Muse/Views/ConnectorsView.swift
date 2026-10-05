import SwiftUI

struct ConnectorsScreen: View {
    @EnvironmentObject private var store: AppStore

    @State private var newName = ""
    @State private var newKind = "oauth"
    @State private var newClientId = ""
    @State private var newClientSecret = ""
    @State private var newApiKey = ""
    @State private var newBaseUrl = ""
    @State private var addResult = ""

    private var connectedCount: Int {
        store.data.connectors.filter(\.isEnabled).count
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    Text("你的智能体会使用连接器来管理你的邮件、安排好你的日程等。你随时可以添加或移除账户。开启“自动分享”后，新的内容会自动共享给智能体；关闭后仅共享你明确要求的。")
                        .font(.footnote)
                        .foregroundColor(Theme.textSecondary)
                } header: {
                    Text("已连接 \(connectedCount) 项")
                }

                Section("内置连接器") {
                    ForEach(builtins) { connector in
                        ConnectorRow(connector: connector)
                    }
                }

                Section("自定义连接器") {
                    ForEach(customs) { connector in
                        ConnectorRow(connector: connector, showKind: true)
                    }
                    customForm
                }

                Section {
                    Text("Meta 不会审核自定义连接器及其如何使用你的信息。智能体可能会执行非预期操作。请谨慎授权访问，并仔细阅读其隐私政策。")
                        .font(.caption2)
                        .foregroundColor(Theme.textSecondary)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("连接器")
        }
        .navigationViewStyle(.stack)
    }

    private var builtins: [Connector] {
        store.data.connectors.filter { $0.kind == "builtin" }
    }
    private var customs: [Connector] {
        store.data.connectors.filter { $0.kind != "builtin" }
    }

    private var customForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("连接器名称", text: $newName)
                .textFieldStyle(.roundedBorder)
            Picker("接入方式", selection: $newKind) {
                Text("OAuth 接入").tag("oauth")
                Text("API Key 接入").tag("apikey")
            }
            .pickerStyle(.segmented)
            if newKind == "oauth" {
                TextField("Client ID", text: $newClientId)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                SecureField("Client Secret", text: $newClientSecret)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
            } else {
                SecureField("API Key", text: $newApiKey)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
            }
            TextField("服务地址（可选）", text: $newBaseUrl)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
            Button {
                addCustom()
            } label: {
                Text("添加连接器")
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.white)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.accent))
            }
            if !addResult.isEmpty {
                Text(addResult)
                    .font(.caption)
                    .foregroundColor(Theme.success)
            }
        }
        .padding(.vertical, 4)
    }

    private func addCustom() {
        switch store.addCustomConnector(
            name: newName, kind: newKind,
            clientId: newClientId, clientSecret: newClientSecret,
            apiKey: newApiKey, baseUrl: newBaseUrl) {
        case .ok(let conn):
            addResult = "已添加自定义连接器「\(conn.name)」，可打开开关进行连接"
            newName = ""; newClientId = ""; newClientSecret = ""; newApiKey = ""; newBaseUrl = ""
        case .emptyName:
            addResult = "请填写连接器名称"
        case .duplicate:
            addResult = "同名连接器已存在"
        case .missingCredential:
            addResult = newKind == "oauth" ? "OAuth 需要 Client ID 与 Client Secret" : "API Key 接入需要填写密钥"
        }
    }
}

struct ConnectorRow: View {
    @EnvironmentObject private var store: AppStore
    var connector: Connector
    var showKind = false
    var onRequestConsent: (() -> Void)?

    @State private var autoShare: Bool

    init(connector: Connector, showKind: Bool = false, onRequestConsent: (() -> Void)? = nil) {
        self.connector = connector
        self.showKind = showKind
        self.onRequestConsent = onRequestConsent
        _autoShare = State(initialValue: connector.autoShare)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.surface3)
                        .frame(width: 34, height: 34)
                    Text(connector.glyph)
                        .foregroundColor(Theme.accent2)
                        .font(.system(size: 15, weight: .semibold))
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(connector.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(Theme.textPrimary)
                        if showKind {
                            Text(connector.kind == "oauth" ? "OAuth" : "API Key")
                                .font(.caption2)
                                .foregroundColor(Theme.accent2)
                        }
                    }
                    Text(connector.connectorDescription)
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(2)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { connector.isEnabled },
                    set: { on in
                        if on && connector.kind != "builtin" {
                            onRequestConsent?()   // OAuth/API Key：先过授权同意页
                            return
                        }
                        store.setConnectorEnabled(connector, enabled: on)
                    }))
                    .labelsHidden()
            }
            if connector.isEnabled {
                Toggle(isOn: $autoShare) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("自动分享")
                            .font(.footnote)
                            .foregroundColor(Theme.textPrimary)
                        Text("新内容自动共享；关闭后仅共享你明确要求的。")
                            .font(.caption2)
                            .foregroundColor(Theme.textSecondary)
                    }
                }
                .toggleStyle(.switch)
                .onChange(of: autoShare) { newValue in
                    store.setAutoShare(connector, enabled: newValue)
                }
                // 权限范围细分（对齐原版「读取权限/写入和删除权限/自动发送」）
                HStack(spacing: 14) {
                    scopeToggle("读取", scope: "read", connector: connector)
                    scopeToggle("写入", scope: "write", connector: connector)
                    scopeToggle("发送", scope: "send", connector: connector)
                    Spacer()
                }
            }
        }
        .padding(.vertical, 2)
    }
}


private extension ConnectorRow {
    func scopeToggle(_ label: String, scope: String, connector: Connector) -> some View {
        Button {
            store.toggleConnectorScope(connector, scope: scope)
        } label: {
            let on = store.data.connectors.first { $0.id == connector.id }?.scopeOn(scope) == true
            HStack(spacing: 3) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.caption2)
                Text(label).font(.caption2)
            }
            .foregroundColor(on ? Theme.accent : Theme.textSecondary)
        }
        .buttonStyle(.plain)
    }
}

/// OAuth/API Key 授权同意页（对齐原版「允许…在账户中心访问…」+ 权限范围选择）
struct OAuthConsentSheet: View {
    @Environment(\.dismiss) private var dismiss
    var connector: Connector
    var onResult: (Bool) -> Void

    @State private var grantRead = true
    @State private var grantWrite = false
    @State private var grantSend = false

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Text(connector.kind == "oauth"
                         ? "允许 Muse 在账户中心访问 \(connector.name)。授权后将签发访问令牌（本地模拟 OAuth 同意页）。"
                         : "即将以 API Key 接入 \(connector.name)。请确认该连接器需要的权限范围。")
                        .font(.footnote)
                        .foregroundColor(Theme.textSecondary)
                }
                Section("请求的权限范围") {
                    Toggle("读取（读取相关数据作为任务上下文）", isOn: $grantRead)
                    Toggle("写入和删除权限", isOn: $grantWrite)
                    Toggle("自动发送（代你发送消息/邮件/内容）", isOn: $grantSend)
                }
                Section {
                    Text("Meta 不会审核自定义连接器及其如何使用你的信息。智能体可能会执行非预期操作，请谨慎授权。")
                        .font(.caption2)
                        .foregroundColor(Theme.textSecondary)
                }
            }
            .navigationTitle("授权连接")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        onResult(false)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("授权并连接") {
                        store.data.connectors.first { $0.id == connector.id }?.accessToken =
                            "at_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(24).lowercased()
                        store.log("connector.consent", "\(connector.name) 已授权（\(grantRead ? "读取 " : "")\(grantWrite ? "写入 " : "")\(grantSend ? "发送" : "")", verdict: "用户确认")
                        onResult(true)
                        dismiss()
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}