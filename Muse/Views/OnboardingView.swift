import SwiftUI

/// 首次启动引导：欢迎 → 权限说明 → 选择初始任务
struct OnboardingView: View {
    var onFinish: () -> Void
    @State private var page = 0
    @State private var selected: Set<String> = []

    private let starters = [
        "每周五 17:00 汇总本周笔记与日历，草拟摘要邮件",
        "每天 10:00 检查邮件并整理优先级（发送前需批准）",
        "帮我盯住「降噪耳机」价格，低于 ¥899 时请求批准下单",
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                welcome.tag(0)
                permissions.tag(1)
                startersPage.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            HStack {
                if page > 0 {
                    Button("上一步") { withAnimation { page -= 1 } }
                        .buttonStyle(.bordered)
                }
                Spacer()
                Button(page == 2 ? "开始使用" : "继续") {
                    if page == 2 {
                        for task in selected {
                            AppStore.shared.data.tasks.append(AgentTask(
                                title: "初始任务", summary: task,
                                risk: task.contains("下单") ? "high" : "medium"))
                        }
                        AppStore.shared.save()
                        onFinish()
                    } else {
                        withAnimation { page += 1 }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 18)
        }
        .background(Theme.bg.ignoresSafeArea())
    }

    private var welcome: some View {
        VStack(spacing: 14) {
            BrandBadge(size: 72)
                .shadow(color: Theme.accent.opacity(0.5), radius: 22)
            Text("Muse")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundColor(Theme.textPrimary)
            Text("你的个人 AI 智能体")
                .foregroundColor(Theme.textSecondary)
            Text("为 Muse 分配目标或任务，剩下的就交给它——无论是帮你存钱、改善健康，还是进行智能购物，它都能帮到你。")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundColor(Theme.textPrimary.opacity(0.9))
                .padding(.horizontal, 36)
                .padding(.top, 6)
            Spacer()
        }
        .padding(.top, 90)
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("系统访问权限")
                .font(.title3.weight(.bold))
                .foregroundColor(Theme.textPrimary)
            perm(icon: "mic.fill", title: "麦克风", desc: "语音输入需要访问麦克风")
            perm(icon: "waveform.badge.magnifyingglass", title: "语音识别", desc: "用于转写你的语音消息")
            perm(icon: "calendar", title: "日历与提醒", desc: "读取日程，为任务提供上下文")
            perm(icon: "photo.on.rectangle", title: "照片", desc: "同步照片与视频进行内容理解和媒体编辑")
            perm(icon: "lock.shield", title: "隐私", desc: "在批准之前，Muse 不会执行任何高危操作；所有动作都记入审计记录")
            Spacer()
        }
        .padding(.horizontal, 30)
        .padding(.top, 60)
    }

    private var startersPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("选择初始任务")
                .font(.title3.weight(.bold))
                .foregroundColor(Theme.textPrimary)
            Text("可随时添加、编辑或取消。")
                .font(.footnote)
                .foregroundColor(Theme.textSecondary)
            ForEach(starters, id: \.self) { task in
                Button {
                    if selected.contains(task) { selected.remove(task) } else { selected.insert(task) }
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: selected.contains(task) ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(selected.contains(task) ? Theme.accent : Theme.textSecondary)
                        Text(task)
                            .font(.footnote)
                            .foregroundColor(Theme.textPrimary)
                            .multilineTextAlignment(.leading)
                        Spacer()
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(selected.contains(task) ? Theme.accent : Theme.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 60)
    }

    private func perm(icon: String, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .frame(width: 26)
                .foregroundColor(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Theme.textPrimary)
                Text(desc)
                    .font(.footnote)
                    .foregroundColor(Theme.textSecondary)
            }
        }
    }
}
