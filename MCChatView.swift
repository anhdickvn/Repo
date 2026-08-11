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
    @State private var showStatus = false
    @State private var tooltipItem: MCItemSlot?
    @State private var tooltipWindowItem: MCOpenWindowItem?
    @State private var savedHistoryCount = 0
    @State private var movementKeys: Set<String> = []

    private var account: MCAccount? { accountStore.account(for: profile.accountId) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                MiniMapView(x: client.playerX, z: client.playerZ, trail: client.movementTrail)
                    .frame(width: 150, height: 150)
                VStack(alignment: .leading, spacing: 5) {
                    Text(String(format: "X %.2f  Y %.2f  Z %.2f", client.playerX, client.playerY, client.playerZ))
                        .font(.system(.caption, design: .monospaced))
                    Text("\(client.currentDimension) · \(client.isOnGroundLabel)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    movementPad
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            Divider()

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
                                   onTab: completeTab,
                                   movementEnabled: !inputFocused && client.state == .connected,
                                   onMoveKey: { key in
                                       switch key {
                                       case "w": client.movePlayer(forward: 0.30, strafe: 0)
                                       case "s": client.movePlayer(forward: -0.30, strafe: 0)
                                       case "a": client.movePlayer(forward: 0, strafe: -0.30)
                                       case "d": client.movePlayer(forward: 0, strafe: 0.30)
                                       default: break
                                       }
                                   })
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

                    Button { showStatus = true } label: {
                        Image(systemName: "cross.case.fill")
                    }
                    .disabled(client.state != .connected)

                    Button { showTools = true } label: {
                        Image(systemName: "briefcase.fill")
                    }
                    .disabled(client.state != .connected)
                }
            }
        }
        .sheet(isPresented: $showPlayers) { playerListSheet }
        .sheet(isPresented: $showStatus) { statusSheet }
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
        .onAppear {
            guard client.state == .disconnected else { return }
            guard let account else {
                client.appendUserInfo("Chưa chọn Minecraft username cho server này.")
                return
            }
            client.connect(host: profile.host, port: profile.port, username: account.username)
        }
        .task {
            await resourcePack.ensureVanillaAssets()
        }
        .onDisappear {
            // Không disconnect khi quay về danh sách/app xuống nền. Chỉ disconnect khi người dùng bấm Ngắt.
        }
    }

    private var movementPad: some View {
        VStack(spacing: 4) {
            Button("W") { client.movePlayer(forward: 1, strafe: 0) }
                .buttonStyle(.bordered)
            HStack(spacing: 4) {
                Button("A") { client.movePlayer(forward: 0, strafe: -1) }
                    .buttonStyle(.bordered)
                Button("S") { client.movePlayer(forward: -1, strafe: 0) }
                    .buttonStyle(.bordered)
                Button("D") { client.movePlayer(forward: 0, strafe: 1) }
                    .buttonStyle(.bordered)
                Button("JUMP") { client.jumpPlayer() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Briefcase: inventory / GUI / vị trí

    private var toolsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Luôn hiển thị túi đồ/player inventory. Không còn tab "Túi đồ / GUI / Vị trí".
                    Text("Túi đồ")
                        .font(.headline)
                        .padding(.horizontal)

                    inventoryPanel

                    // Khi server mở /pv hoặc một GUI khác, GUI được hiển thị ngay trong cùng màn hình.
                    if let window = client.currentWindow {
                        Divider().padding(.vertical, 4)
                        Text(window.title.isEmpty ? "GUI server" : window.title)
                            .font(.headline)
                            .padding(.horizontal)
                        serverWindowPanel(window)
                    }

                    positionSummary
                }
                .padding(.vertical)
            }
            .navigationTitle("Túi đồ & GUI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Đóng") { showTools = false }
                }
            }
        }
    }

    private var inventoryPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if client.playerInventory.values.compactMap({ $0 }).isEmpty && client.hotbar.compactMap({ $0 }).isEmpty {
                Text("Đang chờ server gửi túi đồ...").foregroundStyle(.secondary)
            } else {
                SectionHeader("Giáp")
                inventoryRows(slots: 5...8, emptyText: "(chưa mặc giáp)")
                SectionHeader("Balo")
                inventoryRows(slots: 9...35, emptyText: "(balo trống)")
                SectionHeader("Hotbar · chạm icon = chuột phải")
                hotbarGrid
            }
        }
        .padding(.horizontal)
    }

    private var hotbarGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 9), spacing: 6) {
            ForEach(0..<9, id: \.self) { index in
                if let item = client.hotbar[index] {
                    Button {
                        // Hotbar: chạm trực tiếp vào icon luôn thực hiện CHUỘT PHẢI / Use Item.
                        // Không mở menu "..." và không cần thao tác phụ.
                        client.useHotbarItem(index)
                    } label: {
                        VStack(spacing: 2) {
                            itemVisual(item: item)
                                .frame(maxWidth: .infinity)
                            Text("\(index + 1)").font(.caption2).foregroundStyle(.secondary)
                        }
                        .padding(4)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                } else {
                    VStack(spacing: 2) {
                        Image(systemName: "square.dashed").foregroundStyle(.secondary)
                        Text("\(index + 1)").font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    @ViewBuilder
    private func SectionHeader(_ title: String) -> some View {
        Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func serverWindowPanel(_ window: MCOpenWindow) -> some View {
        if window.items.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "square.grid.3x3").font(.largeTitle)
                Text("GUI đang chờ item...").font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding()
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                ForEach(window.items.keys.sorted(), id: \.self) { slot in
                    if let item = window.items[slot] {
                        Button {
                            client.clickWindowSlot(slot, mouseButton: 0)
                        } label: {
                            VStack(spacing: 3) {
                                itemVisual(itemId: item.itemId, damage: item.damage, segments: item.nameSegments, plainName: item.plainName)
                                    .frame(maxWidth: .infinity, minHeight: 58)
                                Text("Ô \(slot)").font(.caption2).foregroundStyle(.secondary)
                            }
                            .padding(4)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Chuột trái") { client.clickWindowSlot(slot, mouseButton: 0) }
                            Button("Chuột phải") { client.clickWindowSlot(slot, mouseButton: 1) }
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private var positionSummary: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Vị trí") .font(.headline)
            Text(String(format: "X=%.2f   Y=%.2f   Z=%.2f", client.playerX, client.playerY, client.playerZ))
                .font(.system(.footnote, design: .monospaced))
            Text("Map: \(client.currentDimension)").font(.footnote)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
    }

    private var inventoryView: some View { inventoryPanel }

    private var serverMenuView: some View {
        if let window = client.currentWindow {
            serverWindowPanel(window)
        } else {
            Text("Chưa có GUI server đang mở.").foregroundStyle(.secondary)
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

    // MARK: - Trạng thái người chơi

    private var statusSheet: some View {
        NavigationStack {
            VStack(spacing: 22) {
                VStack(spacing: 10) {
                    Text("Máu").font(.headline)
                    HStack(spacing: 4) {
                        ForEach(0..<10, id: \.self) { index in
                            Image(systemName: heartSymbol(index: index, value: client.health))
                                .foregroundStyle(.red)
                                .font(.title3)
                        }
                    }
                    Text(String(format: "%.1f / 20 HP", client.health))
                        .font(.caption).foregroundStyle(.secondary)
                }

                VStack(spacing: 10) {
                    Text("Thức ăn").font(.headline)
                    HStack(spacing: 4) {
                        ForEach(0..<10, id: \.self) { index in
                            Image(systemName: foodSymbol(index: index, value: client.food))
                                .foregroundStyle(.orange)
                                .font(.title3)
                        }
                    }
                    Text("\(client.food) / 20 · saturation \(String(format: "%.1f", client.foodSaturation))")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Button { client.respawn() } label: {
                    Label("Respawn", systemImage: "arrow.clockwise.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(client.health > 0)

                Spacer()
            }
            .padding()
            .navigationTitle("Sinh tồn")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Đóng") { showStatus = false }
                }
            }
        }
    }

    private func heartSymbol(index: Int, value: Float) -> String {
        let hearts = max(0, min(10, Int(ceil(value / 2.0))))
        return index < hearts ? "heart.fill" : "heart"
    }

    private func foodSymbol(index: Int, value: Int) -> String {
        let meat = max(0, min(10, Int(ceil(Double(value) / 2.0))))
        return index < meat ? "fork.knife.circle.fill" : "fork.knife.circle"
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


private struct MiniMapView: View {
    let x: Double
    let z: Double
    let trail: [(x: Double, z: Double)]

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let cell = min(size.width, size.height) / 48
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                for i in 0...48 {
                    var p = Path()
                    p.move(to: CGPoint(x: CGFloat(i) * cell, y: 0))
                    p.addLine(to: CGPoint(x: CGFloat(i) * cell, y: size.height))
                    context.stroke(p, with: .color(.secondary.opacity(0.12)), lineWidth: 0.5)
                    var q = Path()
                    q.move(to: CGPoint(x: 0, y: CGFloat(i) * cell))
                    q.addLine(to: CGPoint(x: size.width, y: CGFloat(i) * cell))
                    context.stroke(q, with: .color(.secondary.opacity(0.12)), lineWidth: 0.5)
                }
                if trail.count > 1 {
                    var path = Path()
                    for (i, point) in trail.enumerated() {
                        let px = center.x + CGFloat(point.x - x) * cell
                        let py = center.y + CGFloat(point.z - z) * cell
                        if i == 0 { path.move(to: CGPoint(x: px, y: py)) }
                        else { path.addLine(to: CGPoint(x: px, y: py)) }
                    }
                    context.stroke(path, with: .color(.blue), lineWidth: 2)
                }
                var player = Path()
                player.move(to: CGPoint(x: center.x, y: center.y - 5))
                player.addLine(to: CGPoint(x: center.x + 5, y: center.y + 5))
                player.addLine(to: CGPoint(x: center.x - 5, y: center.y + 5))
                player.closeSubpath()
                context.fill(player, with: .color(.red))
            }
        }
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.secondary.opacity(0.25)))
    }
}

private extension MCClient {
    var isOnGroundLabel: String { "\(health <= 0 ? "Dead" : "HP \(Int(health))")" }
}
