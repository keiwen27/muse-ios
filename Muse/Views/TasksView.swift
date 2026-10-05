import SwiftUI

struct TasksScreen: View {
    @EnvironmentObject private var store: AppStore
    @State private var showNewTask = false

    private var pending: [AgentTask] {
        store.data.tasks.filter { $0.state == .waitingApproval }
    }
    private var running: [AgentTask] {
        store.data.tasks.filter { $0.state == .running || $0.state == .queued }
    }
    private var finished: [AgentTask] {
        store.data.tasks.filter { !pending.contains($0) && !running.contains($0) }
    }

    var body: some View {
        NavigationView {
            List {
                Section("需要你的批准（\(pending.count)）") {
                    if pending.isEmpty {
                        Text("没有待处理的任务")
                            .foregroundColor(Theme.textSecondary)
                            .font(.footnote)
                    }
                    ForEach(pending) { task in
                        TaskRow(task: task)
                    }
                }

                Section("进行中（\(running.count)）") {
                    if running.isEmpty {
                        Text("暂无进行中的任务")
                            .foregroundColor(Theme.textSecondary)
                            .font(.footnote)
                    }
                    ForEach(running) { task in
                        TaskRow(task: task)
                    }
                }

                Section("审计记录（智能体做过与计划做的每件事）") {
                    if store.data.audit.isEmpty {
                        Text("暂无记录")
                            .foregroundColor(Theme.textSecondary)
                            .font(.footnote)
                    }
                    ForEach(store.data.audit.prefix(30)) { entry in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(entry.tool)
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(Theme.accent2)
                                Spacer()
                                Text(entry.verdict)
                                    .font(.caption2)
                                    .foregroundColor(Theme.textSecondary)
                            }
                            Text(entry.detail)
                                .font(.footnote)
                                .foregroundColor(Theme.textPrimary)
                                .lineLimit(2)
                            Text(entry.time, style: .time)
                                .font(.caption2)
                                .foregroundColor(Theme.textSecondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("任务")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showNewTask = true
                    } label: {
                        Image(systemName: "calendar.badge.plus")
                    }
                }
            }
            .sheet(isPresented: $showNewTask) {
                ScheduledTaskSheet()
            }
        }
        .navigationViewStyle(.stack)
    }

}

struct TaskRow: View {
    @EnvironmentObject private var store: AppStore
    var task: AgentTask

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(task.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Theme.textPrimary)
                if task.isHighRisk {
                    Text("高风险")
                        .font(.caption2)
                        .foregroundColor(Theme.danger)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Theme.danger.opacity(0.18))
                        .cornerRadius(4)
                }
                Spacer()
                Text(task.stateText)
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
            }
            Text(task.summary)
                .font(.footnote)
                .foregroundColor(Theme.textSecondary)
            if let hint = task.scheduleHint {
                Text(hint)
                    .font(.caption2)
                    .foregroundColor(Theme.accent2)
            }
            if task.network != .none {
                Text(task.network == .unlimited
                     ? "网络：无限制（已授权）"
                     : "网络：仅限 \(task.actionPayload ?? "")")
                    .font(.caption2)
                    .foregroundColor(Theme.warning)
            }
            if task.isBrowserTask && task.state == .running {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.surface3)
                        Capsule()
                            .fill(Theme.brandGradient)
                            .frame(width: geo.size.width * CGFloat(task.progress) / 100)
                    }
                }
                .frame(height: 5)
                Text("进度 \(task.progress)%")
                    .font(.caption2)
                    .foregroundColor(Theme.textSecondary)
            }

            HStack(spacing: 10) {
                if task.state == .waitingApproval {
                    actionButton("批准", filled: true) { store.approve(task) }
                    actionButton("拒绝", filled: false) { store.cancel(task) }
                } else if task.action == .browserTask && task.state == .running && task.progress < 100 {
                    actionButton("继续运行", filled: true) { store.advanceBrowserTask(task) }
                    actionButton("停止并接管", filled: false) { store.stopBrowserTask(task) }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func actionButton(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundColor(filled ? .white : Theme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8)
                    .fill(filled ? Theme.accent : Theme.surface3))
        }
        .buttonStyle(.plain)
    }
}


/// 定时任务编辑器（对齐原版「定时任务」+ 网络访问授权）
struct ScheduledTaskSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var summary = ""
    @State private var freq = "每天"
    @State private var time = "09:00"
    @State private var needNetwork = false

    private let freqs = ["每天", "每周", "工作日"]

    var body: some View {
        NavigationView {
            Form {
                Section("任务") {
                    TextField("任务名称", text: $title)
                    TextField("做什么（智能体会按计划执行）", text: $summary)
                }
                Section("计划") {
                    Picker("频率", selection: $freq) {
                        ForEach(freqs, id: \.self) { Text($0) }
                    }
                    TextField("时间 (HH:mm)", text: $time)
                        .keyboardType(.numbersAndPunctuation)
                }
                Section {
                    Toggle("需要网络访问（将请求授权）", isOn: $needNetwork)
                    Button("创建") {
                        let t = title.trimmingCharacters(in: .whitespaces)
                        let s = summary.trimmingCharacters(in: .whitespaces)
                        guard !t.isEmpty, !s.isEmpty else { return }
                        var task = AgentTask(
                            title: "定时任务（\(freq) \(time)）", summary: s,
                            risk: needNetwork ? "medium" : "low",
                            isScheduled: true, scheduleHint: "\(freq) \(time)")
                        if needNetwork {
                            task.network = .unlimited
                            task.action = .networkGrant
                            task.state = .waitingApproval
                        } else {
                            task.state = .queued
                        }
                        store.data.tasks.append(task)
                        store.log("schedule.create", "\(freq) \(time) · \(s)")
                        dismiss()
                    }
                }
            }
            .navigationTitle("新建定时任务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}