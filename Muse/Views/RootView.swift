import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showOnboarding = false
    @State private var locked = false

    private var isLoggedIn: Bool { store.data.session != nil }

    var body: some View {
        Group {
            if locked {
                LockView()
            } else if isLoggedIn {
                MainTabView()
            } else {
                LoginView()
            }
        }
        .preferredColorScheme(colorScheme)
        .onAppear {
            showOnboarding = !store.data.settings.onboarded
            locked = store.data.settings.pinEnabled
        }
        .onReceive(NotificationCenter.default.publisher(for: .museUnlocked)) { _ in
            locked = false
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView {
                store.data.settings.onboarded = true
                store.save()
                showOnboarding = false
            }
        }
    }

    /// 外观（对齐原版「外观：深色/浅色」）——深浅色令牌动态适配
    private var colorScheme: ColorScheme? {
        switch store.data.settings.appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil   // 跟随系统
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            ChatScreen()
                .tabItem { Label("对话", systemImage: "bubble.left.and.bubble.right") }
            TasksScreen()
                .tabItem { Label("任务", systemImage: "checklist") }
            ConnectorsScreen()
                .tabItem { Label("连接器", systemImage: "link") }
            BillingScreen()
                .tabItem { Label("订阅", systemImage: "creditcard") }
            SettingsScreen()
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
    }
}
