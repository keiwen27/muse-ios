# Muse for iOS（iOS 15+）

Muse 个人 AI 智能体的 iPhone / iPad 客户端，SwiftUI 实现，最低部署目标 **iOS 15.0**，零第三方依赖。

## 快速开始

1. 将整个 `ios/Muse` 目录同步到装有 **Xcode 15+** 的 Mac；
2. 双击打开 `Muse.xcodeproj`；
3. 选择 iOS 15+ 的模拟器或真机（真机需在 Signing & Capabilities 中配置开发者团队）；
4. `Cmd + R` 运行。

> 本工程无法在 Windows 上编译；Windows 侧仅负责源码产出，已按 iOS 15 API 严格审校（使用 `NavigationView`、`TabView`、`async/await`，未使用任何 iOS 16+ API）。

## 功能

| 模块 | 说明 |
|---|---|
| 对话 | 气泡消息流、流式输出、附件、多会话 |
| 语音 | 按住说话（AAC 录音 + 实时电平波形），设备端转写（`SFSpeechRecognizer`） |
| 任务 | 定时任务、待批准队列（批准/拒绝）、完整审计记录 |
| 连接器 | Facebook/Instagram/WhatsApp/日历/提醒/通讯录/邮件/笔记 + 自定义 OAuth/API Key，自动分享开关 |
| 设置 | TTS 开关、权限说明、数据导出入口、重置 |
| 引导 | 三页 Onboarding：欢迎 → 权限说明 → 初始任务选择 |

## 架构

```
Muse/
├── MuseApp.swift              入口
├── Theme.swift                设计令牌（与 Windows 端共用一套 Brand）
├── Models/Models.swift        数据模型（Codable）
├── Services/
│   ├── AppStore.swift         全局状态 + JSON 持久化（Documents/muse.json）
│   ├── AgentBackend.swift     可插拔后端协议 + 本地离线引擎（AsyncThrowingStream 事件流）
│   └── SpeechService.swift    AVAudioRecorder 录音电平 + SFSpeechRecognizer 转写
├── ViewModels/
│   └── ChatViewModel.swift    对话流式编排（Combine 转发 Store 变更）
└── Views/                     RootTabView / Chat / Tasks / Connectors / Settings / Onboarding
```

接入真实云端：实现 `AgentBackend` 协议（OAuth 登录 → 会话引导 → SSE 流式对话 → TTS），替换 `ChatViewModel` 中的 `LocalAgentBackend` 即可，UI 与数据层无需改动。端点映射见 `docs/DESIGN.md` §1.2。

## 权限

`Info.plist` 已内置全部用途描述（麦克风 / 语音识别 / 照片 / 相机 / 位置 / 日历 / 提醒 / 通讯录），文案语义与 macOS 版一致。
