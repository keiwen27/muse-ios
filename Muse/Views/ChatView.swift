import SwiftUI

struct ChatScreen: View {
    @EnvironmentObject private var store: AppStore
    @StateObject private var vm: ChatViewModel
    @State private var showRename = false
    @State private var renameText = ""
    @State private var exportURL: URL?
    @State private var showShare = false

    init() {
        _vm = StateObject(wrappedValue: ChatViewModel(store: AppStore.shared))
    }

    private func exportCurrent() {
        guard let conv = vm.current else { return }
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        exportURL = ExportService.exportConversation(conv, to: dir)
        showShare = true
    }

    var body: some View {
        NavigationView {
            ChatView(vm: vm)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Menu {
                            ForEach(vm.sortedConversations) { conv in
                                Button {
                                    vm.switchTo(conv.id)
                                } label: {
                                    HStack {
                                        Text((conv.pinned ? "📌 " : "") + (conv.favorite ? "⭐ " : "") + conv.title).lineLimit(1)
                                        if conv.id == vm.current?.id {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                            Divider()
                            Button {
                                showRename = true
                            } label: {
                                Label("重命名…", systemImage: "pencil")
                            }
                            Button {
                                vm.togglePin()
                            } label: {
                                Label(vm.current?.pinned == true ? "取消置顶" : "置顶", systemImage: "pin")
                            }
                            Button {
                                vm.toggleFavorite()
                            } label: {
                                Label(vm.current?.favorite == true ? "取消收藏" : "收藏", systemImage: "star")
                            }
                            Button {
                                exportCurrent()
                            } label: {
                                Label("导出对话为 Markdown", systemImage: "square.and.arrow.up")
                            }
                            Divider()
                            Button(role: .destructive) {
                                if let cur = vm.current { vm.delete(cur) }
                            } label: {
                                Label("删除当前会话", systemImage: "trash")
                            }
                        } label: {
                            HStack(spacing: 8) {
                                BrandBadge(size: 24)
                                Text(vm.current?.title ?? "新对话")
                                    .font(.headline)
                                    .foregroundColor(Theme.textPrimary)
                                    .lineLimit(1)
                                Image(systemName: "chevron.down")
                                    .font(.caption)
                                    .foregroundColor(Theme.textSecondary)
                            }
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            vm.newConversation()
                        } label: {
                            Image(systemName: "square.and.pencil")
                        }
                    }
                }
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $showRename) {
            RenameSheet(text: vm.current?.title ?? "") { vm.renameCurrent(to: $0) }
                .id(vm.current?.id)
        }
        .sheet(isPresented: $showShare) {
            if let url = exportURL { ShareSheet(items: [url]) }
        }
        // 幻灯片编辑器
        .sheet(isPresented: Binding(
            get: { store.data.settings.slidesEditorActive && !(vm.slidesToEdit ?? []).isEmpty },
            set: { if !$0 {
                store.data.settings.slidesEditorActive = false
                vm.slidesToEdit = nil
                store.save()
            }})) {
            SlidesEditorSheet(slides: vm.slidesToEdit ?? [])
        }
        // 年龄验证（对齐原版「正在打开年龄验证…」）
        .sheet(isPresented: Binding(
            get: { store.data.settings.ageGateActive },
            set: { if !$0 {
                store.data.settings.ageGateActive = false
                store.save()
            }})) {
            AgeVerificationSheet()
        }
        // 地图（「附近: …」）
        .sheet(isPresented: Binding(
            get: { store.lastMapQuery != nil },
            set: { if !$0 { store.lastMapQuery = nil; store.save() }})) {
            MapSheet()
        }
    }
}

/// 重命名会话（iOS 15 兼容实现）
struct RenameSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var text: String
    var onDone: (String) -> Void

    var body: some View {
        NavigationView {
            Form {
                TextField("会话名称", text: $text)
            }
            .navigationTitle("重命名会话")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确定") {
                        onDone(text)
                        dismiss()
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

struct ChatView: View {
    @ObservedObject var vm: ChatViewModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(vm.current?.messages ?? []) { msg in
                            Bubble(message: msg, vm: vm)
                                .id(msg.id)
                        }
                        if vm.showTyping {
                            HStack(spacing: 6) {
                                Circle().fill(Theme.accent).frame(width: 7, height: 7)
                                Text(vm.stateText)
                                    .font(.caption)
                                    .foregroundColor(Theme.textSecondary)
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .transition(.opacity)
                        }
                    }
                    .padding(.vertical, 12)
                }
                .onChange(of: vm.current?.messages.count ?? 0) { _ in
                    if let last = vm.current?.messages.last {
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            Composer(vm: vm)
        }
        .background(Theme.bg.ignoresSafeArea(edges: .bottom))
        .sheet(isPresented: $vm.showVoiceCall) { VoiceCallView() }
    }
}

// MARK: - 气泡

struct Bubble: View {
    var message: Message
    var vm: ChatViewModel?

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if isUser { Spacer(minLength: 56) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 3) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(message.text)
                        .font(.system(size: 14.5))
                        .foregroundColor(isUser ? .white : Theme.textPrimary)
                        .textSelection(.enabled)
                    ForEach(message.attachments) { att in
                        HStack(spacing: 5) {
                            Image(systemName: icon(for: att.kind))
                                .font(.caption2)
                            Text(att.name).font(.caption2).lineLimit(1)
                        }
                        .foregroundColor(isUser ? .white.opacity(0.9) : Theme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(isUser ? 0.18 : 0.35))
                        .cornerRadius(6)
                    }
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: Theme.bubbleCorner, style: .continuous)
                        .fill(isUser ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Theme.surface2))
                )

                // A/B 双回复：方案 B 与偏好选择
                if let alt = message.altText {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("方案 B")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(Theme.accent2)
                        Text(alt)
                            .font(.system(size: 14))
                            .foregroundColor(Theme.textPrimary)
                            .textSelection(.enabled)
                        if let chosen = message.preferredVariant {
                            Text("已选择偏好：\(chosen)")
                                .font(.caption2)
                                .foregroundColor(Theme.success)
                        } else {
                            HStack(spacing: 8) {
                                Button {
                                    vm?.preferVariant(message, "A")
                                } label: {
                                    Text("👍 偏好 A")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 10).padding(.vertical, 5)
                                        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.accent))
                                }
                                Button {
                                    vm?.preferVariant(message, "B")
                                } label: {
                                    Text("👍 偏好 B")
                                        .font(.caption)
                                        .foregroundColor(Theme.textPrimary)
                                        .padding(.horizontal, 10).padding(.vertical, 5)
                                        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.surface3))
                                }
                            }
                        }
                    }
                    .padding(.top, 4)
                }

                // 幻灯片卡（打开编辑器）
                if !message.slides.isEmpty {
                    Button {
                        vm?.openSlides(message)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.richtext")
                            Text("幻灯片已就绪（\(message.slides.count) 页）— 点击打开编辑器")
                                .font(.caption)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        .foregroundColor(Theme.textPrimary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface2))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                }

                // 商品网格
                if !message.products.isEmpty {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(message.products) { product in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(product.name)
                                    .font(.caption)
                                    .foregroundColor(Theme.textPrimary)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                HStack(spacing: 4) {
                                    Text(product.price)
                                        .font(.caption.weight(.bold))
                                        .foregroundColor(Theme.accent2)
                                    Text("· \(product.source)")
                                        .font(.caption2)
                                        .foregroundColor(Theme.textSecondary)
                                }
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface2))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
                        }
                    }
                    .padding(.top, 8)
                }

                Text(message.time, style: .time)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textSecondary.opacity(0.7))
            }
            if !isUser { Spacer(minLength: 56) }
        }
        .padding(.horizontal, 12)
    }

    private func icon(for kind: String) -> String {
        switch kind {
        case "图片": return "photo"
        case "音频": return "waveform"
        default: return "doc"
        }
    }
}

// MARK: - 输入器

struct Composer: View {
    @ObservedObject var vm: ChatViewModel

    var body: some View {
        VStack(spacing: 6) {
            if !vm.pendingAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(vm.pendingAttachments) { att in
                            Text(att.name)
                                .font(.caption2)
                                .foregroundColor(Theme.textPrimary)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Theme.surface3)
                                .cornerRadius(6)
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }

            // 角色选择 + 语音通话入口
            HStack(spacing: 8) {
                Menu {
                    ForEach(AgentRole.allCases, id: \.self) { role in
                        Button {
                            vm.setRole(role)
                        } label: {
                            if vm.current?.role == role {
                                Label(role.displayName, systemImage: "checkmark")
                            } else {
                                Text(role.displayName)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2")
                            .font(.caption)
                        Text(vm.current?.role.displayName ?? "通用助手")
                            .font(.caption)
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                    .foregroundColor(Theme.textSecondary)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Theme.surface2)
                    .cornerRadius(14)
                }

                Button {
                    vm.showVoiceCall = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "phone.fill")
                            .font(.caption)
                        Text("语音通话")
                            .font(.caption)
                    }
                    .foregroundColor(Theme.textSecondary)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Theme.surface2)
                    .cornerRadius(14)
                }

                Spacer()
            }
            .padding(.horizontal, 12)

            HStack(alignment: .bottom, spacing: 10) {
                TextField("输入消息…", text: $vm.draft)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Theme.surface2)
                    .cornerRadius(22)
                    .foregroundColor(Theme.textPrimary)
                    .onSubmit { Task { await vm.send() } }

                MicButton(vm: vm)

                Button {
                    Task { await vm.send() }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(
                            Circle().fill(vm.draft.isEmpty ? Theme.surface3 : Theme.accent)
                        )
                }
                .disabled(vm.draft.isEmpty || vm.isBusy)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if vm.isRecording {
                HStack(spacing: 10) {
                    VoiceWaveform(level: vm.level)
                    Text("正在聆听…（按住说话，松开发送）")
                        .font(.caption2)
                        .foregroundColor(Theme.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, 18)
            }
        }
        .padding(.top, 6)
        .background(Theme.surface.ignoresSafeArea())
    }
}

/// 长按手势的麦克风按钮（按住说话，松开发送）
struct MicButton: View {
    @ObservedObject var vm: ChatViewModel
    @State private var isDown = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.brandGradient)
                .shadow(color: vm.isRecording ? Theme.accent.opacity(0.8) : .clear, radius: 12)
            Image(systemName: "mic.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(width: 40, height: 40)
        .contentShape(Circle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isDown {
                        isDown = true
                        vm.voiceDown()
                    }
                }
                .onEnded { _ in
                    if isDown {
                        isDown = false
                        vm.voiceUp()
                    }
                }
        )
        .accessibilityLabel("按住说话")
    }
}
