import SwiftUI
import Foundation

// MARK: - App theme

enum MCThemeMode: String, CaseIterable, Identifiable {
    case dark = "dark"
    case light = "light"
    case auto = "auto"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dark: return "Tối"
        case .light: return "Sáng"
        case .auto: return "Tự động"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .dark: return .dark
        case .light: return .light
        case .auto: return nil
        }
    }
}

@MainActor
final class MCThemeStore: ObservableObject {
    @Published var mode: MCThemeMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "mc_theme_mode") }
    }
    init() {
        mode = MCThemeMode(rawValue: UserDefaults.standard.string(forKey: "mc_theme_mode") ?? "auto") ?? .auto
    }
}

// MARK: - Logs hôm nay

struct MCArchivedLog: Identifiable, Codable, Equatable {
    var id = UUID()
    var date: Date
    var text: String
}

@MainActor
final class MCChatHistoryStore: ObservableObject {
    @Published private(set) var entries: [MCArchivedLog] = [] {
        didSet { save() }
    }
    private let key = "mc_chat_history_today"

    init() { loadAndPrune() }

    func append(_ entry: MCLogEntry) {
        pruneIfNeeded()
        let text = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // Không ghi lại cùng một dòng liên tiếp do SwiftUI/reconnect gửi trùng callback.
        if entries.last?.text == text && Date().timeIntervalSince(entries.last?.date ?? .distantPast) < 1 { return }
        entries.append(MCArchivedLog(date: Date(), text: text))
    }

    func clearToday() { entries.removeAll() }

    private func isToday(_ date: Date) -> Bool { Calendar.current.isDateInToday(date) }

    private func pruneIfNeeded() {
        entries.removeAll { !isToday($0.date) }
    }

    private func loadAndPrune() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([MCArchivedLog].self, from: data) else {
            entries = []
            return
        }
        entries = decoded.filter { isToday($0.date) }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

struct MCLogsView: View {
    @EnvironmentObject var history: MCChatHistoryStore

    var body: some View {
        NavigationStack {
            Group {
                if history.entries.isEmpty {
                    VStack(spacing: 10) {
                    Image(systemName: "text.bubble")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Chưa có lịch sử")
                        .font(.headline)
                    Text("Chat trong hôm nay sẽ được lưu tại đây.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 10) {
                                ForEach(history.entries) { entry in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.text)
                                            .textSelection(.enabled)
                                        Text(entry.date, style: .time)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal)
                                    .id(entry.id)
                                    Divider()
                                }
                            }
                            .padding(.top, 8)
                        }
                    }
                }
            }
            .navigationTitle("Logs")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Xoá hôm nay", role: .destructive) { history.clearToday() }
                        .disabled(history.entries.isEmpty)
                }
            }
        }
    }
}

struct MCSettingsView: View {
    @EnvironmentObject var theme: MCThemeStore

    var body: some View {
        NavigationStack {
            Form {
                Section("Giao diện") {
                    Picker("Chế độ", selection: $theme.mode) {
                        ForEach(MCThemeMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.inline)
                    Text("Tự động sẽ theo giao diện sáng/tối của iPhone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
