import Foundation

/// 账户服务 v3（对齐原版登录方式）：
/// 无自定义密码注册/登录 —— 登录即「Meta 账户体系授权」
/// （auth.meta.com OIDC → 账户中心允许 → muse.ai/oidc/callback → hatch/session/bootstrap）。
/// 本地等价实现：选择 Meta / Facebook / Instagram 账户 → 授权 Sheet 允许 → 签发 30 天会话。
final class AuthService {
    static let shared = AuthService()

    struct AuthError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private struct UserRecord: Codable {
        var identifier: String          // 邮箱或手机号（Meta 账户标识）
        var displayName: String
        var provider: String = "Meta"   // Meta | Facebook | Instagram
        var inviteRedeemed = false
        var createdAt = Date()
    }

    private struct AuthStore: Codable {
        var users: [UserRecord] = []
        var waitlist: [String] = []
        var sessions: [String: String] = [:]   // token → identifier
    }

    private let fileURL: URL
    private var store: AuthStore
    private(set) var current: UserSession?

    let validInviteCodes = ["MUSE2026", "ENDO-VIP"]

    /// dataDir 为 nil 时使用 Documents（E2E 可注入临时目录）
    init(dataDir: URL? = nil) {
        let dir = dataDir ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = dir.appendingPathComponent("auth.json")
        store = AuthStore()
        if let raw = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(AuthStore.self, from: raw) {
            store = decoded
        }
        restoreSession()
    }

    /// session bootstrap：从本地凭据恢复未过期会话
    private func restoreSession() {
        for (token, identifier) in store.sessions {
            guard let user = store.users.first(where: { $0.identifier == identifier }) else { continue }
            let s = UserSession(
                email: user.identifier, displayName: user.displayName,
                token: token, issuedAt: user.createdAt, inviteRedeemed: user.inviteRedeemed)
            if Date().timeIntervalSince(s.issuedAt) < 30 * 86400 {
                current = s
                return
            }
        }
    }

    private func save() {
        if let raw = try? JSONEncoder().encode(store) {
            try? raw.write(to: fileURL, options: .atomic)
        }
    }

    private func newToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return "muse_" + Data(bytes).base64EncodedString()
    }

    private func bootstrap(_ user: UserRecord) -> UserSession {
        let token = newToken()
        store.sessions[token] = user.identifier
        save()
        return UserSession(
            email: user.identifier, displayName: user.displayName,
            token: token, issuedAt: Date(), inviteRedeemed: user.inviteRedeemed)
    }

    // MARK: 账户中心授权（对齐 OIDC 授权 + 会话引导）：标识为邮箱或手机号，无密码
    // 两道闸门：① 标识格式（邮箱/11 位手机号） ② 邀请码（原版邀请制准入）

    private let emailRegex = try! NSRegularExpression(pattern: "^[^@\\s]+@[^@\\s]+\\.[^@\\s]{2,}$")
    private let phoneRegex = try! NSRegularExpression(pattern: "^1\\d{10}$")

    private func isIdentifierValid(_ id: String) -> Bool {
        let range = NSRange(id.startIndex..., in: id)
        return phoneRegex.firstMatch(in: id, range: range) != nil
            || emailRegex.firstMatch(in: id, range: range) != nil
    }

    func authorize(provider: String, identifier: String, inviteCode: String) throws -> UserSession {
        let identifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard isIdentifierValid(identifier) else {
            throw AuthError(message: "账户标识无效：需为邮箱地址或 11 位手机号")
        }
        let invite = inviteCode.trimmingCharacters(in: .whitespaces).uppercased()
        guard validInviteCodes.contains(invite)
            || (invite.hasPrefix("抢先体验") && invite.count >= 6) else {
            throw AuthError(message: "邀请码无效——Muse 为邀请制准入。你可以在官网申请加入等候名单。")
        }
        let user: UserRecord
        if var existing = store.users.first(where: { $0.identifier == identifier }) {
            existing.provider = provider
            if let idx = store.users.firstIndex(where: { $0.identifier == identifier }) {
                store.users[idx] = existing
            }
            user = existing
        } else {
            user = UserRecord(
                identifier: identifier,
                displayName: String(identifier.split(separator: "@").first ?? "Meta 用户"),
                provider: provider)
            store.users.append(user)
        }
        current = bootstrap(user)
        return current!
    }

    func logout() {
        if let token = current?.token {
            store.sessions.removeValue(forKey: token)
            save()
        }
        current = nil
    }

    // MARK: 邀请码 / 等候名单

    func redeemInvite(_ code: String) throws {
        let c = code.trimmingCharacters(in: .whitespaces).uppercased()
        guard validInviteCodes.contains(c) || (c.hasPrefix("抢先体验") && c.count >= 6) else {
            throw AuthError(message: "邀请码无效。你可以在官网申请加入等候名单。")
        }
        if var session = current {
            session.inviteRedeemed = true
            current = session
        }
        if let idx = store.users.firstIndex(where: { $0.identifier == current?.email }) {
            store.users[idx].inviteRedeemed = true
        }
        save()
    }

    func joinWaitlist(_ email: String) throws {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard email.contains("@") else { throw AuthError(message: "请输入有效的邮箱地址") }
        if !store.waitlist.contains(email) { store.waitlist.append(email) }
        save()
    }

    // MARK: 多账户（对齐原版「使用其他账户」「从其他设备退出」）

    var registeredAccounts: [String] { store.users.map(\.identifier) }

    /// 会话有效期内免密切换
    func switchToExistingSession(_ identifier: String) -> Bool {
        guard let tokenKV = store.sessions.first(where: { $0.value == identifier }),
              let user = store.users.first(where: { $0.identifier == identifier }) else { return false }
        current = UserSession(
            email: user.identifier, displayName: user.displayName,
            token: tokenKV.key, issuedAt: user.createdAt, inviteRedeemed: user.inviteRedeemed)
        return true
    }

    @discardableResult
    func removeAccount(_ identifier: String) -> Bool {
        guard let idx = store.users.firstIndex(where: { $0.identifier == identifier }) else { return false }
        store.users.remove(at: idx)
        store.sessions = store.sessions.filter { $0.value != identifier }
        if current?.email == identifier { current = nil }
        save()
        return true
    }
}
