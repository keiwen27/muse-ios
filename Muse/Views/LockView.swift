import SwiftUI

/// PIN 应用锁（对齐原版：错误计数与冷却锁定）
struct LockView: View {
    @State private var pin = ""
    @State private var hint = ""
    @State private var cooldownRemaining: TimeInterval = 0
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Theme.brandGradient)
                    .frame(width: 72, height: 72)
                    .shadow(color: Theme.accent.opacity(0.4), radius: 18)
                Image(systemName: "lock.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.white)
            }
            Text("输入 PIN 码解锁")
                .font(.headline)
                .foregroundColor(Theme.textPrimary)
                .padding(.top, 14)

            SecureField("PIN 码（4-6 位）", text: $pin)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.title3)
                .foregroundColor(Theme.textPrimary)
                .padding(.horizontal, 60)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface2))
                .padding(.top, 16)

            Text(hint)
                .font(.footnote)
                .foregroundColor(Theme.danger)
                .multilineTextAlignment(.center)
                .frame(minHeight: 20)
                .padding(.horizontal, 40)

            Button {
                unlock()
            } label: {
                Text("解锁")
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accent))
            }
            .padding(.horizontal, 80)
            .disabled(cooldownRemaining > 0)

            Spacer()
        }
        .background(Theme.bg.ignoresSafeArea())
        .onAppear { tick() }
        .onDisappear { timer?.invalidate() }
    }

    private func tick() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            let s = AppStore.shared.data.settings
            cooldownRemaining = PinService.cooldownRemaining(s)
            let left = PinService.maxAttempts - s.pinFailedAttempts
            hint = cooldownRemaining > 0
                ? "尝试次数过多，已锁定 — 请等待 \(Int(cooldownRemaining)) 秒"
                : (s.pinFailedAttempts > 0 ? "PIN 码错误。你还有 \(left) 次尝试机会。" : "")
        }
    }

    private func unlock() {
        guard cooldownRemaining <= 0 else { return }
        if PinService.verify(pin) {
            NotificationCenter.default.post(name: .museUnlocked, object: nil)
        } else {
            pin = ""
            tick()
        }
    }
}

extension Notification.Name {
    static let museUnlocked = Notification.Name("museUnlocked")
}
