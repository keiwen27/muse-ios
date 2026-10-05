import SwiftUI

/// 设计令牌（docs/DESIGN.md §2.3，与 Windows 端一致）
enum Theme {
    static let accent       = Color(red: 124/255, green:  92/255, blue: 1.0)      // #7C5CFF
    static let accent2      = Color(red:  77/255, green: 159/255, blue: 1.0)      // #4D9FFF
    static let bg           = Color(red: 14/255,  green: 15/255,  blue: 20/255)    // #0E0F14
    static let surface      = Color(red: 23/255,  green: 25/255,  blue: 35/255)    // #171923
    static let surface2     = Color(red: 30/255,  green: 34/255,  blue: 48/255)    // #1E2230
    static let surface3     = Color(red: 38/255,  green: 43/255,  blue: 61/255)    // #262B3D
    static let border       = Color(red: 42/255,  green: 48/255,  blue: 68/255)    // #2A3044
    static let textPrimary  = Color(red: 242/255, green: 243/255, blue: 247/255)   // #F2F3F7
    static let textSecondary = Color(red: 154/255, green: 160/255, blue: 180/255)   // #9AA0B4
    static let danger       = Color(red: 1.0,   green: 92/255,  blue: 108/255)     // #FF5C6C
    static let success      = Color(red: 61/255,  green: 220/255, blue: 151/255)   // #3DDC97
    static let warning      = Color(red: 1.0,   green: 193/255, blue: 92/255)      // #FFC15C

    static let brandGradient = LinearGradient(
        colors: [accent, accent2], startPoint: .topLeading, endPoint: .bottomTrailing)

    static let bubbleCorner: CGFloat = 16
    static let cardCorner: CGFloat = 10
}

struct BrandBadge: View {
    var size: CGFloat = 34
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(Theme.brandGradient)
            Text("M")
                .font(.system(size: size * 0.55, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
    }
}

/// 录音电平波形
struct VoiceWaveform: View {
    var level: Double
    var bars: Int = 7

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<bars, id: \.self) { i in
                let phase = 0.55 + 0.45 * Double((i * 7 + 3) % 5) / 5.0
                Capsule()
                    .fill(Theme.brandGradient)
                    .frame(width: 4, height: CGFloat(6 + max(0, min(1, level)) * 26 * phase))
                    .animation(.easeOut(duration: 0.12), value: level)
            }
        }
        .frame(height: 34)
    }
}
