import SwiftUI

@main
struct ChatApp: App {
    var body: some Scene {
        WindowGroup {
            ChatAppRootView()
        }
    }
}

/// Shared stores are injected at the highest level so every tab/navigation destination
/// receives the required environment objects during SwiftUI's first render pass.
struct ChatAppRootView: View {
    @StateObject private var accountStore = MCAccountStore()
    @StateObject private var themeStore = MCThemeStore()
    @StateObject private var historyStore = MCChatHistoryStore()

    var body: some View {
        TabView {
            MCServerListView()
                .tabItem { Label("ChatCraft", systemImage: "message.fill") }

            MCLogsView()
                .tabItem { Label("Logs", systemImage: "archivebox.fill") }

            MCSettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .environmentObject(accountStore)
        .environmentObject(themeStore)
        .environmentObject(historyStore)
        .preferredColorScheme(themeStore.mode.colorScheme)
        .tint(.blue)
    }
}
