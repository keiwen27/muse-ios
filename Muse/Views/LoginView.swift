import SwiftUI

/// 登录 / 注册 / 邀请码 / 等候名单（对齐原版 OIDC 登录 + 邀请制）
struct LoginView: View {
    @EnvironmentObject private var store: AppStore

    enum Mode: String, CaseIterable {
        case login = "登录", register = "注册", invite = "邀请码"
    }

    @State private var mode: Mode = .login
    @State private var email = ""
    @State private var password = ""
    @State private var inviteCode = ""
    @State private var message = ""
    @State private var messageIsError = true
    @State private var busy = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 48)
            BrandBadge(size: 64)
                .shadow(color: Theme.accent.opacity(0.5), radius: 18)
            Text("Muse")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(Theme.textPrimary)
                .padding(.top, 10)
            Text("个人 AI 智能体 · 登录后开始使用")
                .font(.footnote)
                .foregroundColor(Theme.textSecondary)

            Picker("模式", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 28)
            .padding(.top, 22)

            Form {
                Section {
                    TextField("邮箱", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if mode != .invite {
                        SecureField("密码（至少 6 位）", text: $password)
                    }
                    if mode == .register {
                        TextField("邀请码（选填）", text: $inviteCode)
                            .textInputAutocapitalization(.never)
                    }
                    if mode == .invite {
                        TextField("邀请码", text: $inviteCode)
                            .textInputAutocapitalization(.never)
                    }
                }
                Section {
                    Button(action: { Task { await submit() } }) {
                        HStack {
                            Spacer()
                            if busy { ProgressView().tint(.white) }
                            Text(buttonTitle)
                                .foregroundColor(.white)
                            Spacer()
                        }
                    }
                    .listRowBackground(Theme.accent)
                    .disabled(busy)

                    if mode == .login {
                        Button("使用 Meta 账户继续") {
                            message = "已打开 Meta 账户中心授权页（OIDC）。本地引擎演示环境使用邮箱直接登录。"
                            messageIsError = false
                        }
                        .foregroundColor(Theme.accent)
                    }
                    if mode == .login || mode == .invite {
                        Button("没有邀请码？加入等候名单") { Task { await joinWaitlist() } }
                            .foregroundColor(Theme.accent)
                    }
                }

                if !message.isEmpty {
                    Section {
                        Text(message)
                            .font(.footnote)
                            .foregroundColor(messageIsError ? Theme.danger : Theme.success)
                    }
                }
            }
        }
        .background(Theme.bg.ignoresSafeArea())
    }

    private var buttonTitle: String {
        switch mode {
        case .login: return "登录"
        case .register: return "创建账户"
        case .invite: return "兑换邀请码"
        }
    }

    private func submit() async {
        busy = true
        defer { busy = false }
        do {
            switch mode {
            case .login:
                let session = try AuthService.shared.login(email: email, password: password)
                succeed(session)
            case .register:
                let session = try AuthService.shared.register(
                    email: email, password: password,
                    inviteCode: inviteCode.isEmpty ? nil : inviteCode)
                succeed(session)
            case .invite:
                try AuthService.shared.redeemInvite(inviteCode)
                message = "邀请码已兑换。请切换到「注册」完成账户创建。"
                messageIsError = false
            }
        } catch {
            message = error.localizedDescription
            messageIsError = true
        }
    }

    private func joinWaitlist() async {
        do {
            try AuthService.shared.joinWaitlist(email)
            message = "已加入等候名单：\(email)。有空缺时我们会通过邮件通知你。"
            messageIsError = false
        } catch {
            message = error.localizedDescription
            messageIsError = true
        }
    }

    private func succeed(_ session: UserSession) {
        store.data.session = session
        store.data.subscription.transactions.insert(
            QuotaTransaction(kind: "赠送", credits: 20, note: "新用户注册奖励"), at: 0)
        store.save()
    }
}
