import Foundation
import CryptoKit

/// 账户服务（对齐 auth.meta.com OIDC → session bootstrap 的本地实现）：
/// 注册 / 登录 / 登出 / 邀请码兑换 / 等候名单，会话令牌 30 天有效。
final class AuthService {
    static let shared = AuthService()

    struct AuthError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private struct UserRecord: Codable {
        var email: String
        var displayName: String
        var salt: String
        var hash: String
        var inviteRedeemed = false
        var createdAt = Date()
    }

    private struct AuthStore: Codable {
        var users: [UserRecord] = []
        var waitlist: [String] = []
        var sessions: [String: String] = [:]   // token → email
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
        for (_, email) in store.sessions {
            guard let user = store.users.first(where: { $0.email == email }) else { continue }
            let s = UserSession(
                email: user.email, displayName: user.displayName,
                token: store.sessions.first(where: { $0.value == email })?.key ?? "",
                issuedAt: user.createdAt, inviteRedeemed: user.inviteRedeemed)
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

    private func hashPassword(_ password: String, salt: String) -> String {
        var data = Data(password.utf8) + Data(salt.utf8)
        for _ in 0..<20000 {
            data = Data(SHA256.hash(data: data))
        }
        return data.base64EncodedString()
    }

    private func newSalt() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
    }

    private func bootstrap(_ user: UserRecord) -> UserSession {
        var token = "muse_"
        var bytes = [UInt8](repeating: 0, count: 24)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        token += Data(bytes).base64EncodedString()
        store.sessions[token] = user.email
        save()
        return UserSession(
            email: user.email, displayName: user.displayName,
            token: token, issuedAt: Date(), inviteRedeemed: user.inviteRedeemed)
    }

    // MARK: API

    func register(email: String, password: String, inviteCode: String?) throws -> UserSession {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard email.contains("@") else { throw AuthError(message: "请输入有效的邮箱地址") }
        guard password.count >= 6 else { throw AuthError(message: "密码至少 6 位") }
        guard !store.users.contains(where: { $0.email == email }) else {
            throw AuthError(message: "该邮箱已注册，请直接登录")
        }
        if let code = inviteCode, !code.trimmingCharacters(in: .whitespaces).isEmpty {
            try validateInvite(code)
        }
        let salt = newSalt()
        let user = UserRecord(
            email: email,
            displayName: String(email.split(separator: "@").first ?? "muse"),
            salt: salt,
            hash: hashPassword(password, salt: salt),
            inviteRedeemed: inviteCode != nil && !inviteCode!.isEmpty)
        store.users.append(user)
        if current == nil { current = bootstrap(user) } else { save() }
        return current!
    }

    func login(email: String, password: String) throws -> UserSession {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let user = store.users.first(where: { $0.email == email }) else {
            throw AuthError(message: "账户不存在，请先注册")
        }
        let hash = hashPassword(password, salt: user.salt)
        guard hash == user.hash else { throw AuthError(message: "密码不正确") }
        current = bootstrap(user)
        return current!
    }

    // MARK: 多账户（对齐原版「使用其他账户」「从其他设备退出」）

    var registeredAccounts: [String] { store.users.map(\.email) }

    /// 会话有效期内免密切换
    func switchToExistingSession(_ email: String) -> Bool {
        guard let tokenKV = store.sessions.first(where: { $0.value == email }),
              let user = store.users.first(where: { $0.email == email }) else { return false }
        current = UserSession(
            email: user.email, displayName: user.displayName,
            token: tokenKV.key, issuedAt: user.createdAt, inviteRedeemed: user.inviteRedeemed)
        return true
    }

    @discardableResult
    func removeAccount(_ email: String) -> Bool {
        guard let idx = store.users.firstIndex(where: { $0.email == email }) else { return false }
        store.users.remove(at: idx)
        store.sessions = store.sessions.filter { $0.value != email }
        if current?.email == email { current = nil }
        save()
        return true
    }

    func logout() {
        if let token = current?.token {
            store.sessions.removeValue(forKey: token)
            save()
        }
        current = nil
    }

    private func validateInvite(_ code: String) throws {
        let c = code.trimmingCharacters(in: .whitespaces).uppercased()
        if validInviteCodes.contains(c) || (c.hasPrefix("抢先体验") && c.count >= 6) { return }
        throw AuthError(message: "邀请码无效。你可以在官网申请加入等候名单。")
    }

    func redeemInvite(_ code: String) throws {
        try validateInvite(code)
        if var session = current {
            session.inviteRedeemed = true
            current = session
        }
        if let idx = store.users.firstIndex(where: { $0.email == current?.email }) {
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
}
