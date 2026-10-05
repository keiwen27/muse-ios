import Foundation

// MARK: - 枚举

enum MessageRole: String, Codable { case user, agent, system }

enum AgentState: String, Codable { case idle, thinking, working, making, waitingApproval }

enum AgentTaskState: String, Codable { case queued, waitingApproval, running, done, cancelled }

/// 智能体协作角色（对齐原版五种协作智能体）
enum AgentRole: String, Codable, CaseIterable {
    case general, strategy, builder, research, synthesis, review

    var displayName: String {
        switch self {
        case .strategy: return "策略智能体"
        case .builder: return "构建智能体"
        case .research: return "研究智能体"
        case .synthesis: return "合成智能体"
        case .review: return "评审智能体"
        case .general: return "通用助手"
        }
    }

    var persona: String {
        switch self {
        case .strategy: return "聚焦目标、优先事项、执行顺序与产品权衡，表述直截了当。"
        case .builder: return "专注于落地实现、用户流程、具体步骤与第一版可交付内容。"
        case .research: return "专注于证据、未知信息与应核实事项，不声称拥有隐私数据访问权限。"
        case .synthesis: return "整合各项观点，输出简洁摘要、决策与后续步骤。"
        case .review: return "重点关注风险、边缘情况与依据不足的主张，点评直言客观。"
        case .general: return "帮你完成任务的个人 AI 智能体。"
        }
    }
}

/// 任务动作类型：批准后由 TaskExecutor 实际执行
enum TaskActionKind: String, Codable {
    case none, reminderAdd, mailSend, browserCheckout, fileWrite, browserTask, networkGrant
}

/// 每任务网络访问范围（对齐原版「允许这项任务的无限制网络访问？」）
enum NetworkScope: String, Codable {
    case none, domains, unlimited
}

/// 商品卡（对齐原版「商品网格视图/为你购买」的本地模拟数据）
struct ProductCard: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var price: String
    var source: String
}

/// 幻灯片（对齐原版内嵌幻灯片编辑器的本地实现）
struct Slide: Codable, Identifiable {
    var id = UUID()
    var title: String
    var bullets: [String]
}

/// 个人播客剧集（对齐原版「创建播客/发布到播客动态」）
struct PodcastEpisode: Codable, Identifiable {
    var id = UUID().uuidString.prefix(8).lowercased()
    var createdAt = Date()
    var title: String
    var script: String
    var played = false
}

/// 已配对设备（对齐原版「Muse Link（设备/硬件）」「从其他设备退出」）
struct PairedDevice: Codable, Identifiable {
    var id = UUID()
    var name: String
    var code: String
    var pairedAt = Date()
}

/// 记忆（对齐原版「你的个人信息」与持久信息提取）
struct MemoryItem: Codable, Identifiable {
    var id = UUID()
    var createdAt = Date()
    var content: String
    var source: String = "用户告知"   // 用户告知 | 对话提取 | 迁移导入
}

/// 帮助工单（对齐 hatch-api /help_ticket）
struct SupportTicket: Codable, Identifiable {
    var id: String = "MUSE-\(Int.random(in: 100000...999999))"
    var createdAt = Date()
    var category: String
    var description: String
    var status: String = "已提交"
}

// MARK: - 实体

struct Attachment: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var kind: String = "文件"   // 文件 | 图片 | 音频
    var path: String?
}

struct Message: Codable, Identifiable {
    var id = UUID()
    var hasAlt: Bool { altText != nil }
    var hasProducts: Bool { !products.isEmpty }
    var role: MessageRole
    var text: String = ""
    var time = Date()
    var attachments: [Attachment] = []
    /// A/B 双回复（对齐原版「两条回复已就绪，请选择你偏好的回复」）
    var altText: String?
    var preferredVariant: String?
    /// 商品网格数据（「搜商品: …」时填充）
    var products: [ProductCard] = []
    /// 幻灯片数据（「做幻灯片: …」时填充）
    var slides: [Slide] = []
}

struct Conversation: Codable, Identifiable {
    var id = UUID()
    var title: String = "新对话"
    var messages: [Message] = []
    var createdAt = Date()
    var updatedAt = Date()
    var role: AgentRole = .general
    /// 置顶（对齐原版「已置顶/拖放到这里即可固定」）
    var pinned = false
    /// 收藏（对齐原版「已收藏/取消收藏」）
    var favorite = false
}

struct AgentTask: Codable, Identifiable {
    var id = UUID()
    var title: String
    var summary: String
    var risk: String = "low"          // low | medium | high
    var isScheduled = false
    var scheduleHint: String?
    var state: AgentTaskState = .queued
    var createdAt = Date()
    var action: TaskActionKind = .none
    var actionPayload: String?
    var progress: Int = 0
    var network: NetworkScope = .none

    var stateText: String {
        switch state {
        case .queued: return "排队中"
        case .waitingApproval: return "需要你的批准"
        case .running: return "正在工作"
        case .done: return "已完成"
        case .cancelled: return "已取消"
        }
    }

    var isHighRisk: Bool { risk == "high" }
    var isBrowserTask: Bool { action == .browserTask || action == .browserCheckout }

    var networkText: String {
        switch network {
        case .domains: return "网络：仅限 \(actionPayload ?? "")"
        case .unlimited: return "网络：无限制（已授权）"
        case .none: return ""
        }
    }
}

struct AuditEntry: Codable, Identifiable {
    var id = UUID()
    var time = Date()
    var tool: String
    var detail: String
    var verdict: String = "自动执行"
}

struct Connector: Codable, Identifiable {
    var id: String
    var name: String
    var connectorDescription: String
    var glyph: String = "◈"
    var kind: String = "builtin"      // builtin | oauth | apikey
    var isEnabled = false
    var autoShare = true
    var canRead = true
    var canWrite = false
    var canSend = false
    var clientId: String = ""
    var clientSecret: String = ""
    var apiKey: String = ""
    var baseUrl: String = ""
    var accessToken: String?

    private enum CodingKeys: String, CodingKey {
        case id, name, connectorDescription = "description", glyph, kind, isEnabled, autoShare
        case clientId, clientSecret, apiKey, baseUrl, canRead, canWrite, canSend, accessToken
    }

    func scopeOn(_ scope: String) -> Bool {
        switch scope {
        case "read": return canRead
        case "write": return canWrite
        case "send": return canSend
        default: return false
        }
    }
}

// MARK: - 账户与订阅

struct UserSession: Codable, Equatable {
    var email: String
    var displayName: String
    var token: String
    var issuedAt: Date = Date()
    var inviteRedeemed = false
}

enum PlanKind: String, Codable { case free, pro }

struct QuotaTransaction: Codable, Identifiable {
    var id = UUID()
    var time = Date()
    var kind: String      // 消耗 | 充值 | 订阅
    var credits: Double
    var note: String = ""
}

struct Subscription: Codable {
    var plan: PlanKind = .free
    var credits: Double = 20
    var renewAt = Date().addingTimeInterval(30 * 86400)
    var transactions: [QuotaTransaction] = []

    var planText: String { plan == .pro ? "Pro 月度订阅" : "免费版" }
}

struct MuseSettings: Codable {
    var onboarded = false
    var ttsEnabled = true
    var greeting = "世界，你好！"
    var handsFreeMode = false
    var appearance = "dark"          // dark | light
    // PIN 应用锁（对齐原版：错误冷却、多次尝试锁定）
    var pinEnabled = false
    var pinSalt = ""
    var pinHash = ""
    var pinFailedAttempts = 0
    var pinLockedUntil: Date?
    var magicLink: String?
    var ageVerified = false
    var ttsVoice = ""
    var cvmConnected = false
    // UI 激活标记（非持久化语义，随 Codable 存储便于跨视图观察）
    var ageGateActive = false
    var slidesEditorActive = false
}

struct MuseData: Codable {
    var conversations: [Conversation] = []
    var tasks: [AgentTask] = []
    var audit: [AuditEntry] = []
    var connectors: [Connector] = MuseData.defaultConnectors
    var settings = MuseSettings()
    var subscription = Subscription()
    var session: UserSession?
    var memories: [MemoryItem] = []
    var tickets: [SupportTicket] = []
    var prefA = 0
    var prefB = 0
    var pairedDevices: [PairedDevice] = []
    var podcastEpisodes: [PodcastEpisode] = []

    static let defaultConnectors: [Connector] = [
        Connector(id: "facebook",  name: "Facebook",  connectorDescription: "发帖、评论、点赞、关注", glyph: "f"),
        Connector(id: "instagram", name: "Instagram", connectorDescription: "浏览与发布内容", glyph: "◎"),
        Connector(id: "whatsapp",  name: "WhatsApp",  connectorDescription: "管理消息与通话", glyph: "✆"),
        Connector(id: "calendar",  name: "日历",      connectorDescription: "读取日程，为任务提供上下文", glyph: "▦"),
        Connector(id: "reminders", name: "提醒事项",  connectorDescription: "管理提醒与待办", glyph: "☑"),
        Connector(id: "contacts",  name: "通讯录",    connectorDescription: "查找并管理人员", glyph: "☺"),
        Connector(id: "mail",      name: "邮件",      connectorDescription: "读取、起草与发送邮件", glyph: "✉", canWrite: true, canSend: true),
        Connector(id: "notes",     name: "笔记",      connectorDescription: "读取与管理笔记和便签", glyph: "✎", canWrite: true),
        Connector(id: "custom-oauth",  name: "自定义连接器（OAuth）",   connectorDescription: "Client ID / Client Secret 接入", glyph: "⚿", kind: "oauth"),
        Connector(id: "custom-apikey", name: "自定义连接器（API Key）", connectorDescription: "以 API 密钥接入外部服务", glyph: "⚿", kind: "apikey"),
    ]
}
