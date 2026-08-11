import SwiftUI
import UIKit

extension Color {
    init?(hex: String) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self = Color(red: r, green: g, blue: b)
    }
}

struct MCChatView: View {
    let profile: MCServerProfile
    @EnvironmentObject var accountStore: MCAccountStore
    @EnvironmentObject var historyStore: MCChatHistoryStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var client = MCClient()
    @StateObject private var resourcePack = MCResourcePackStore.shared
    @State private var input = ""
    @State private var inputFocused = false
    @State private var showPlayers = false
    @State private var showTools = false
    @State private var toolTab = 0
    @State private var tooltipItem: MCItemSlot?
    @State private var tooltipWindowItem: MCOpenWindowItem?
    @State private var savedHistoryCount = 0

    private var account: MCAccount? { accountStore.account(for: profile.accountId) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(client.log) { entry in
                            logRow(entry).id(entry.id)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                }
                .background(Color(.systemBackground))
                .onChange(of: client.log.count) { _ in
                    if let last = client.log.last {
                        historyStore.append(last)
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            Divider()

            VStack(spacing: 5) {
                if client.state == .connected && !client.tabCompletions.isEmpty && input.hasPrefix("/") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(client.tabCompletions.prefix(10), id: \.self) { name in
                                Button(name) {
                                    input = replaceLastToken(in: input, with: name)
                                    inputFocused = true
                                }
                                .buttonStyle(.bordered)
                                .font(.caption)
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                }

                HStack(spacing: 8) {
                    Button("TAB") { completeTab() }
                        .font(.headline)
                        .foregroundStyle(.blue)

                    MCTabTextField(text: $input, isFocused: $inputFocused,
                                   placeholder: "Message...",
                                   onSubmit: sendMessage,
                                   onTab: completeTab)
                        .disabled(client.state != .connected)
                        .frame(height: 40)

                    Button { sendMessage() } label: {
                        Image(systemName: "paperplane.fill")
                            .font(.title3)
                    }
                    .disabled(client.state != .connected || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .background(Color(.systemBackground))
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .navigationTitle(profile.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 18) {
                    Button { showPlayers = true } label: {
                        Image(systemName: "person.3.fill")
                    }
                    .disabled(client.state != .connected)

                    Button { showTools = true; toolTab = 0 } label: {
                        Image(systemName: "briefcase.fill")
                    }
                    .disabled(client.state != .connected)
                }
            }
        }
        .sheet(isPresented: $showPlayers) { playerListSheet }
        .sheet(isPresented: $showTools) { toolsSheet }
        .sheet(item: $tooltipItem) { item in
            itemTooltipSheet(name: item.plainName, segments: item.nameSegments,
                             lore: item.loreSegments, image: resourcePack.image(for: item))
        }
        .sheet(item: $tooltipWindowItem) { item in
            itemTooltipSheet(name: item.plainName, segments: item.nameSegments,
                             lore: item.loreSegments, image: resourcePack.image(for: item),
                             windowAction: { mouseButton in
                                 client.clickWindowSlot(item.slot, mouseButton: mouseButton)
                                 tooltipWindowItem = nil
                             })
        }
        .onChange(of: input) { newValue in
            guard client.state == .connected else { return }
            if newValue.hasPrefix("/") && newValue.contains(" ") {
                client.requestTabCompletions(newValue)
            } else if !newValue.hasPrefix("/") {
                client.tabCompletions = []
            }
        }
        .onDisappear {
            // Không disconnect khi quay về danh sách/app xuống nền. Chỉ disconnect khi người dùng bấm Ngắt.
        }
    }

    // MARK: - Briefcase: inventory / GUI / vị trí

    private var toolsSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $toolTab) {
                    Text("Túi đồ").tag(0)
                    Text("GUI").tag(1)
                    Text("Vị trí").tag(2)
                }
                .pickerStyle(.segmented)
                .padding()

                Group {
                    switch toolTab {
                    case 0: inventoryView
                    case 1: serverMenuView
                    default: positionView
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Cặp sách")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Đóng") { showTools = false }
                }
            }
        }
    }

    private var inventoryView: some View {
        List {
            Section("Giáp") { inventoryRows(slots: 5...8, emptyText: "(chưa mặc giáp)") }
            Section("Balo") { inventoryRows(slots: 9...35, emptyText: "(balo trống)") }
            Section("Hotbar") {
                ForEach(0..<9, id: \.self) { i in
                    if let item = client.hotbar[i] {
                        itemActionRow(item: item) {
                            client.useHotbarItem(i)
                        } rightClick: {
                            client.useHotbarItem(i)
                        } more: {
                            tooltipItem = item
                        }
                    } else {
                        Text("(ô trống)").foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var serverMenuView: some View {
        Group {
            if let window = client.currentWindow {
                if window.items.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "square.grid.3x3")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("GUI trống")
                            .font(.headline)
                        Text("Server chưa gửi item cho GUI này.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    List {
                        Section(window.title.isEmpty ? "GUI server" : window.title) {
                            ForEach(window.items.keys.sorted(), id: \.self) { slot in
                                if let item = window.items[slot] {
                                    itemActionRow(item: item) {
                                        client.clickWindowSlot(slot, mouseButton: 0)
                                    } rightClick: {
                                        client.clickWindowSlot(slot, mouseButton: 1)
                                    } more: {
                                        tooltipWindowItem = item
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "square.grid.3x3")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Chưa có GUI")
                        .font(.headline)
                    Text("Gõ /ah, /pv hoặc lệnh GUI trên server; app sẽ nhận GUI nhưng không tự bật. Sau đó mở Cặp sách → GUI.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
        }
    }

    private var positionView: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack(spacing: 28) {
                    Button { client.movePlayer(dx: 0.5, dz: 0) } label: {
                        Image(systemName: "arrow.left")
                            .font(.title)
                    }
                    Button { client.movePlayer(dx: 0, dz: 0.5) } label: {
                        Image(systemName: "arrow.up")
                            .font(.title)
                    }
                    Button { client.movePlayer(dx: 0, dz: -0.5) } label: {
                        Image(systemName: "arrow.down")
                            .font(.title)
                    }
                    Button { client.movePlayer(dx: -0.5, dz: 0) } label: {
                        Image(systemName: "arrow.right")
                            .font(.title)
                    }
                }
                .buttonStyle(.bordered)

                Button("Jump") { client.jumpPlayer() }
                    .buttonStyle(.borderedProminent)

                VStack(spacing: 8) {
                    Text(String(format: "X=%.2f   Y=%.2f   Z=%.2f", client.playerX, client.playerY, client.playerZ))
                        .font(.system(.body, design: .monospaced))
                    Text("Map: \(client.currentDimension)")
                        .font(.headline)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
            .padding(24)
        }
    }

    // MARK: - Inventory + GUI rows

    @ViewBuilder
    private func inventoryRows(slots: ClosedRange<Int>, emptyText: String) -> some View {
        let items = slots.compactMap { slot in client.playerInventory[slot].map { (slot, $0) } }
        if items.isEmpty {
            Text(emptyText).foregroundStyle(.secondary)
        } else {
            ForEach(items, id: \.0) { _, item in
                itemActionRow(item: item) {
                    tooltipItem = item
                } rightClick: {
                    tooltipItem = item
                } more: {
                    tooltipItem = item
                }
            }
        }
    }

    @ViewBuilder
    private func itemActionRow(item: MCItemSlot,
                               leftClick: @escaping () -> Void,
                               rightClick: @escaping () -> Void,
                               more: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Button(action: leftClick) { itemVisual(item: item) }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Chuột trái") { leftClick() }
                    Button("Chuột phải") { rightClick() }
                    Button("Xem tooltip / Lore") { more() }
                }
            Spacer()
            Menu {
                Button("Chuột trái") { leftClick() }
                Button("Chuột phải") { rightClick() }
                Button("Xem tooltip / Lore") { more() }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func itemActionRow(item: MCOpenWindowItem,
                               leftClick: @escaping () -> Void,
                               rightClick: @escaping () -> Void,
                               more: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Button(action: leftClick) {
                itemVisual(itemId: item.itemId, damage: item.damage,
                           segments: item.nameSegments, plainName: item.plainName)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Chuột trái") { leftClick() }
                Button("Chuột phải") { rightClick() }
                Button("Xem tooltip / Lore") { more() }
            }
            Spacer()
            Menu {
                Button("Chuột trái") { leftClick() }
                Button("Chuột phải") { rightClick() }
                Button("Xem tooltip / Lore") { more() }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func itemVisual(item: MCItemSlot) -> some View {
        itemVisual(itemId: item.itemId, damage: item.damage,
                   segments: item.nameSegments, plainName: item.plainName, count: item.count)
    }

    @ViewBuilder
    private func itemVisual(itemId: Int16, damage: Int16,
                            segments: [MCChatSegment]?, plainName: String,
                            count: Int? = nil) -> some View {
        HStack(spacing: 10) {
            if let image = resourcePack.image(for: MCItemSlot(hotbarIndex: -1, itemId: itemId, damage: damage,
                                                              count: count ?? 1, nameSegments: segments)) {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 42, height: 42)
            } else {
                Image(systemName: "cube.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 42, height: 42)
            }
            VStack(alignment: .leading, spacing: 2) {
                if let segments, !segments.isEmpty { coloredText(segments) } else { Text(plainName) }
                if let count, count > 1 {
                    Text("x\(count)").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func itemTooltipSheet(name: String, segments: [MCChatSegment]?, lore: [[MCChatSegment]], image: UIImage?, windowAction: ((UInt8) -> Void)? = nil) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        if let image {
                            Image(uiImage: image).resizable().interpolation(.none).scaledToFit().frame(width: 64, height: 64)
                        } else {
                            Image(systemName: "cube.fill").font(.largeTitle).foregroundStyle(.secondary).frame(width: 64, height: 64)
                        }
                        if let segments, !segments.isEmpty { coloredText(segments).font(.headline) } else { Text(name).font(.headline) }
                    }
                    if lore.isEmpty {
                        Text("Không có Lore").foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(lore.enumerated()), id: \.offset) { _, line in coloredText(line) }
                    }
                    if let windowAction {
                        HStack {
                            Button("Chuột trái") { windowAction(0) }.buttonStyle(.borderedProminent)
                            Button("Chuột phải") { windowAction(1) }.buttonStyle(.bordered)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Tooltip")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { Button("Đóng") { tooltipItem = nil; tooltipWindowItem = nil } }
            }
        }
    }

    // MARK: - Players / connection / chat

    private var playerListSheet: some View {
        NavigationStack {
            List {
                Section("Online · \(client.onlinePlayerNames.count)") {
                    ForEach(client.onlinePlayerNames.sorted { $0.lowercased() < $1.lowercased() }, id: \.self) { name in
                        HStack {
                            Image(systemName: "person.fill").foregroundStyle(.secondary)
                            Text(name).textSelection(.enabled)
                        }
                    }
                    if client.onlinePlayerNames.isEmpty {
                        Text("Chưa nhận được danh sách người chơi từ server.").foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Người chơi")
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Đóng") { showPlayers = false } } }
        }
    }

    private func completeTab() {
        guard client.state == .connected else { return }
        if let completed = client.completeWithNextPlayerName(input) {
            input = completed
            inputFocused = true
            client.requestTabCompletions(input)
        } else if input.hasPrefix("/") {
            client.requestTabCompletions(input)
            inputFocused = true
        }
    }

    private func replaceLastToken(in text: String, with value: String) -> String {
        guard let range = text.range(of: #"\S+$"#, options: .regularExpression) else { return text + value }
        return String(text[..<range.lowerBound]) + value
    }

    private func sendMessage() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        client.sendChat(text)
        input = ""
    }

    @ViewBuilder
    private func logRow(_ entry: MCLogEntry) -> some View {
        if let segments = entry.segments, !segments.isEmpty {
            coloredText(segments).font(.system(.subheadline))
        } else {
            Text(entry.text)
                .font(.system(.subheadline))
                .foregroundStyle(entry.kind == .info ? .secondary : .primary)
                .textSelection(.enabled)
        }
    }

    private func coloredText(_ segments: [MCChatSegment]) -> Text {
        segments.reduce(Text("")) { partial, seg in
            var t = Text(seg.text).foregroundColor(seg.colorHex.flatMap(Color.init(hex:)) ?? .primary)
            if seg.bold { t = t.bold() }
            if seg.italic { t = t.italic() }
            if seg.strikethrough { t = t.strikethrough() }
            if seg.underline { t = t.underline() }
            return partial + t
        }
    }
}
