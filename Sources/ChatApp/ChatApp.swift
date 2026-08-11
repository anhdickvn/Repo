import SwiftUI

@main
struct ChatApp: App {
    @StateObject private var accountStore = MCAccountStore()
    @StateObject private var themeStore = MCThemeStore()
    @StateObject private var historyStore = MCChatHistoryStore()

    var body: some Scene {
        WindowGroup {
            TabView {
                MCServerListView()
                    .environmentObject(accountStore)
                    .tabItem { Label("ChatCraft", systemImage: "message.fill") }

                MCLogsView()
                    .environmentObject(historyStore)
                    .tabItem { Label("Logs", systemImage: "archivebox.fill") }

                MCSettingsView()
                    .environmentObject(themeStore)
                    .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            }
            .preferredColorScheme(themeStore.mode.colorScheme)
            .tint(.blue)
        }
    }
}
