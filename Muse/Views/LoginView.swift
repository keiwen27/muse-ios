import SwiftUI

/// 登录页（对齐原版：Meta 账户体系授权登录，无自定义密码）
struct LoginView: View {
    @EnvironmentObject private var store: AppStore
    @State private var provider: String = "Meta"
    @State private var identifier = ""
    @State private var inviteCode = ""
    @State private var message = ""
    @State private var messageIsError = true
    @State private var showConsent = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 48)
            BrandBadge(size: 64)
                .shadow(color: Theme.accent.opacity(0.5), radius: 18)
            Text("登录 Muse")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(Theme.textPrimary)
                .padding(.top, 10)
            Text("使用你的 Meta 账户继续")
                .font(.footnote)
                .foregroundColor(Theme.textSecondary)

            // 账户标识（授权页会用到）
            TextField("Meta 账户（邮箱或手机号）", text: $identifier)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundColor(Theme.textPrimary)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(Theme.surface2)
                .cornerRadius(10)
                .padding(.horizontal, 28)
                .padding(.top, 22)

            // 账户中心授权按钮（对齐原版三入口）
            VStack(spacing: 10) {
                providerButton("使用 Meta 账户继续", provider: "Meta", filled: true)
                providerButton("使用 Facebook 账户继续", provider: "Facebook", filled: false)
                providerButton("使用 Instagram 账户继续", provider: "Instagram", filled: false)
            }
            .padding(.horizontal, 28)
            .padding(.top, 14)

            // 邀请码 / 等候名单（对齐原版邀请制）
            HStack(spacing: 8) {
                TextField("邀请码（选填）", text: $inviteCode)
                    .textInputAutocapitalization(.never)
                    .foregroundColor(Theme.textPrimary)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(Theme.surface2)
                    .cornerRadius(10)
                Button("兑换") {
                    do {
                        try AuthService.shared.redeemInvite(inviteCode)
                        message = "邀请码已兑换。"
                        messageIsError = false
                    } catch {
                        message = error.localizedDescription
                        messageIsError = true
                    }
                }
                .foregroundColor(Theme.accent)
            }
            .padding(.horizontal, 28)
            .padding(.top, 14)

            Button("没有邀请码？加入等候名单") {
                do {
                    try AuthService.shared.joinWaitlist(identifier)
                    message = "已加入等候名单：\(identifier)。有空缺时我们会通过邮件通知你。"
                    messageIsError = false
                } catch {
                    message = error.localizedDescription
                    messageIsError = true
                }
            }
            .font(.footnote)
            .foregroundColor(Theme.accent)
            .padding(.top, 12)

            if !message.isEmpty {
                Text(message)
                    .font(.footnote)
                    .foregroundColor(messageIsError ? Theme.danger : Theme.success)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .padding(.top, 8)
            }

            Spacer()
            Text("授权由 Meta 账户中心完成（OIDC）。本演示环境在本地模拟账户中心授权页并签发 30 天会话，不会向任何服务器发送你的账户信息。")
                .font(.caption2)
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 20)
        }
        .background(Theme.bg.ignoresSafeArea())
        .sheet(isPresented: $showConsent) {
            MetaConsentSheet(provider: provider, identifier: identifier) { session in
                store.data.session = session
                store.save()
            }
        }
        .preferredColorScheme(.dark)
    }

    private func providerButton(_ title: String, provider: String, filled: Bool) -> some View {
        Button {
            self.provider = provider
            showConsent = true
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(filled ? .white : Theme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(RoundedRectangle(cornerRadius: 10)
                    .fill(filled ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.surface2)))
        }
    }
}

/// Meta 账户中心授权页（本地模拟 accountscenter.meta.com 的 OAuth 同意流程）
struct MetaConsentSheet: View {
    @Environment(\.dismiss) private var dismiss
    var provider: String
    var identifier: String
    var onResult: (UserSession) -> Void

    @State private var account = ""
    @State private var hint = ""

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Text("允许 Muse 访问你的 \(provider) 账户。授权后将完成会话引导（本地模拟账户中心 OIDC）。")
                        .font(.footnote)
                        .foregroundColor(Theme.textSecondary)
                }
                Section("Muse 将获得以下权限") {
                    consentRow("✓", "你的公开资料（头像与昵称）")
                    consentRow("✓", "你的电子邮箱地址")
                }
                Section(provider + " 账户") {
                    TextField("邮箱或手机号", text: $account)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundColor(Theme.textPrimary)
                    if !hint.isEmpty {
                        Text(hint).font(.footnote).foregroundColor(Theme.danger)
                    }
                }
                Section {
                    Button("允许") {
                        let id = account.isEmpty ? identifier : account
                        do {
                            let session = try AuthService.shared.authorize(provider: provider, identifier: id)
                            onResult(session)
                            dismiss()
                        } catch {
                            hint = error.localizedDescription
                        }
                    }
                    .foregroundColor(Theme.accent)
                    Button("取消", role: .cancel) { dismiss() }
                        .foregroundColor(Theme.textSecondary)
                }
            }
            .navigationTitle("Meta 账户中心")
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
    }

    private func consentRow(_ mark: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Text(mark)
                .font(.footnote.weight(.bold))
                .foregroundColor(Theme.success)
            Text(text)
                .font(.footnote)
                .foregroundColor(Theme.textPrimary)
        }
    }
}
