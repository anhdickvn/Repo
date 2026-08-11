import SwiftUI

@main
struct ChatApp: App {
    var body: some Scene {
        WindowGroup {
            ChatAppRootView()
        }
    }
}

/// Root view owns all shared stores and injects them at the highest possible level.
/// This prevents any NavigationLink/ForEach destination from being rendered without
/// the required @EnvironmentObject values during the first SwiftUI layout pass.
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
        // Inject shared objects on the TabView itself, not only on individual tabs.
        // SwiftUI may evaluate child/destination views while building ForEach/List.
        .environmentObject(accountStore)
        .environmentObject(themeStore)
        .environmentObject(historyStore)
        .preferredColorScheme(themeStore.mode.colorScheme)
        .tint(.blue)
    }
}
