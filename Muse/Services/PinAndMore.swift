import Foundation
import CryptoKit

/// PIN 应用锁（对齐原版：4-6 位、错误 3 次锁定 60 秒冷却、可更改；E2E 可注入设置对象）
enum PinService {
    static let maxAttempts = 3
    static let cooldown: TimeInterval = 60

    static var isEnabled: Bool { AppStore.shared.data.settings.pinEnabled }

    static func isLockedOut(_ s: MuseSettings) -> Bool {
        if let until = s.pinLockedUntil { return Date() < until }
        return false
    }

    static func cooldownRemaining(_ s: MuseSettings) -> TimeInterval {
        if let until = s.pinLockedUntil, Date() < until { return until.timeIntervalSinceNow }
        return 0
    }

    static func setPin(_ pin: String, settings: MuseSettings? = nil) {
        let s = settings ?? AppStore.shared.data.settings
        let salt = newSalt()
        s.pinEnabled = true
        s.pinSalt = salt
        s.pinHash = hash(pin, salt: salt)
        s.pinFailedAttempts = 0
        s.pinLockedUntil = nil
        if settings == nil { AppStore.shared.save() }
    }

    static func disable(settings: MuseSettings? = nil) {
        let s = settings ?? AppStore.shared.data.settings
        s.pinEnabled = false
        s.pinHash = ""; s.pinSalt = ""
        s.pinFailedAttempts = 0
        s.pinLockedUntil = nil
        if settings == nil { AppStore.shared.save() }
    }

    /// 验证；成功返回 true，失败累计错误（3 次进入冷却）
    @discardableResult
    static func verify(_ pin: String, settings: MuseSettings? = nil) -> Bool {
        let s = settings ?? AppStore.shared.data.settings
        guard s.pinEnabled else { return true }
        if isLockedOut(s) { return false }
        if hash(pin, salt: s.pinSalt) == s.pinHash {
            s.pinFailedAttempts = 0
            if settings == nil { AppStore.shared.save() }
            return true
        }
        s.pinFailedAttempts += 1
        if s.pinFailedAttempts >= maxAttempts {
            s.pinLockedUntil = Date().addingTimeInterval(cooldown)
            s.pinFailedAttempts = 0
        }
        if settings == nil { AppStore.shared.save() }
        return false
    }

    private static func newSalt() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
    }

    private static func hash(_ pin: String, salt: String) -> String {
        var data = Data("pin:\(pin)".utf8) + Data(salt.utf8)
        for _ in 0..<20000 { data = Data(SHA256.hash(data: data)) }
        return data.base64EncodedString()
    }
}

/// 聊天导入（对齐原版「从支持的 AI 助手导出你的聊天」）
/// iOS 沙盒内无法解 zip 且不引入第三方库，接受 conversations.json 单文件（Windows 端支持 .zip 全量归档）。
enum ImportService {
    struct ImportResult: Equatable {
        var conversations: Int
        var memories: Int
    }

    struct ImportedConversation: Codable {
        var title: String?
        var messages: [ImportedMessage]?
    }
    struct ImportedMessage: Codable {
        var role: String?
        var text: String?
    }

    static func importJSON(_ raw: Data, into data: MuseData) throws -> ImportResult {
        var result = ImportResult(conversations: 0, memories: 0)
        if let list = try? JSONDecoder().decode([ImportedConversation].self, from: raw) {
            for c in list {
                var conv = Conversation()
                conv.title = (c.title?.isEmpty == false) ? c.title! : "导入的对话"
                for m in c.messages ?? [] {
                    let role: MessageRole = (m.role ?? "user").lowercased() == "agent" ? .agent
                        : (m.role ?? "user").lowercased() == "system" ? .system : .user
                    conv.messages.append(Message(role: role, text: m.text ?? ""))
                }
                data.conversations.append(conv)
                result.conversations += 1
            }
            return result
        }
        if let mems = try? JSONDecoder().decode([String].self, from: raw) {
            for m in mems {
                data.memories.append(MemoryItem(content: m, source: "迁移导入"))
                result.memories += 1
            }
            return result
        }
        throw NSError(domain: "MuseImport", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "无法识别的归档格式（需要 conversations.json 或 memory.json）"])
    }
}

/// 帮助工单（对齐 hatch-api /help_ticket 的本地实现）
enum TicketService {
    @discardableResult
    static func submit(_ data: MuseData, category: String, description: String) -> SupportTicket {
        let ticket = SupportTicket(category: category, description: description, status: "已提交（本地工单）")
        data.tickets.insert(ticket, at: 0)
        data.audit.insert(AuditEntry(tool: "help.ticket", detail: "[\(ticket.id)] \(category)"), at: 0)
        return ticket
    }
}
