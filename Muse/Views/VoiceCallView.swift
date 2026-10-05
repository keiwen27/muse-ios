import SwiftUI

/// 语音通话（对齐原版：语音通话正在连接 → 通话中 → 已结束）
struct VoiceCallView: View {
    enum CallState { case connecting, active, ended }

    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var state: CallState = .connecting
    @State private var duration: TimeInterval = 0
    @State private var timer: Timer?

    private var stateText: String {
        switch state {
        case .connecting: return "语音通话正在连接"
        case .active: return "通话中"
        case .ended: return "语音通话已结束"
        }
    }

    private var durationText: String {
        let m = Int(duration) / 60, s = Int(duration) % 60
        return String(format: "%02d:%02d", m, s)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Theme.brandGradient)
                    .frame(width: 96, height: 96)
                    .shadow(color: Theme.accent.opacity(state == .active ? 0.7 : 0.3), radius: 20)
                    .scaleEffect(state == .active ? 1.0 + 0.04 * sin(duration * 4) : 1.0)
                    .animation(.easeInOut(duration: 0.3), value: state)
                Text("M")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            Text(stateText)
                .font(.headline)
                .foregroundColor(Theme.textPrimary)
                .padding(.top, 16)
            Text(durationText)
                .font(.footnote)
                .foregroundColor(Theme.textSecondary)
                .padding(.top, 4)

            if state == .active {
                VoiceWaveform(level: 0.55 + 0.35 * sin(duration * 3))
                    .padding(.top, 18)
            }

            Spacer()

            Button {
                if state == .ended {
                    dismiss()
                } else {
                    state = .ended
                    timer?.invalidate()
                }
            } label: {
                Text(state == .ended ? "关闭" : "挂断")
                    .foregroundColor(state == .ended ? Theme.textPrimary : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 10)
                        .fill(state == .ended ? Theme.surface3 : Theme.danger))
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 34)
        }
        .background(Theme.bg.ignoresSafeArea())
        .onAppear(perform: start)
        .onDisappear { timer?.invalidate() }
    }

    private func start() {
        // 1.2s 连接中 → 通话中（对齐原版 VoiceCallService 时序）
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            guard state == .connecting else { return }
            state = .active
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
                duration += 0.25
            }
        }
    }
}
