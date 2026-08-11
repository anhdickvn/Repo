import SwiftUI

struct MCServerListView: View {
    @StateObject private var store = MCProfileStore()
    @EnvironmentObject var accountStore: MCAccountStore
    @EnvironmentObject var historyStore: MCChatHistoryStore
    @State private var showAdd = false
    @State private var showAddAccount = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text("ChatCraft")
                            .font(.largeTitle.bold())
                        Spacer()
                        Button { showAdd = true } label: { Image(systemName: "plus") }
                            .font(.title2)
                    }

                    HStack {
                        Text("Accounts")
                            .font(.title3.weight(.semibold))
                        Spacer()
                        NavigationLink { AccountListView().environmentObject(accountStore) } label: {
                            Image(systemName: "pencil")
                        }
                        Button {
                            showAddAccount = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }

                    if accountStore.accounts.isEmpty {
                        NavigationLink {
                            AccountListView().environmentObject(accountStore)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "person.crop.circle.badge.plus")
                                    .font(.system(size: 42))
                                VStack(alignment: .leading) {
                                    Text("Minecraft Username")
                                        .font(.headline)
                                    Text("(chưa đặt tên)")
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                            }
                            .padding(18)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                        }
                        .buttonStyle(.plain)
                    } else {
                        ForEach(accountStore.accounts) { account in
                            HStack(spacing: 14) {
                                MinecraftSkinView(username: account.username)
                                    .frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading) {
                                    Text(account.username).font(.headline)
                                    Text("Minecraft Username")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(18)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                        }
                    }

                    HStack {
                        Text("Servers")
                            .font(.title3.weight(.semibold))
                        Spacer()
                        Button { showAdd = true } label: { Image(systemName: "plus") }
                    }

                    ForEach(store.profiles) { profile in
                        NavigationLink {
                            MCChatView(profile: profile)
                                .environmentObject(accountStore)
                                .environmentObject(historyStore)
                        } label: {
                            serverCard(profile)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in store.profiles.remove(atOffsets: offsets) }
                }
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 90)
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showAddAccount) {
                MCAccountEditView(account: MCAccount(username: "")) { newAccount in
                    accountStore.accounts.append(newAccount)
                }
                .environmentObject(accountStore)
            }
            .sheet(isPresented: $showAdd) {
                MCServerEditView(
                    profile: MCServerProfile(name: "Tôi Chơi NetWork", host: "proxy.toichoi.com", port: 54321, accountId: accountStore.accounts.first?.id)
                ) { newProfile in
                    store.profiles.append(newProfile)
                }
                .environmentObject(accountStore)
            }
        }
        .onAppear { store.ensureDefaultServer() }
    }

    @ViewBuilder
    private func serverCard(_ profile: MCServerProfile) -> some View {
        HStack(spacing: 16) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 44))
                .frame(width: 76, height: 76)
                .foregroundStyle(.orange)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 5) {
                Text(profile.name).font(.headline)
                Text("\(profile.host):\(profile.port)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("✦ TOI CHOI NETWORK ✦")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct MCServerEditView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var accountStore: MCAccountStore
    @State var profile: MCServerProfile
    let onSave: (MCServerProfile) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Thông tin server") {
                    TextField("Tên server", text: $profile.name)
                    TextField("Server IP", text: $profile.host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Server port", value: $profile.port, format: .number)
                        .keyboardType(.numberPad)
                }
                Section("Username") {
                    if accountStore.accounts.isEmpty {
                        Text("Hãy thêm username ở mục Accounts.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Minecraft Username", selection: $profile.accountId) {
                            Text("Chưa chọn").tag(UUID?.none)
                            ForEach(accountStore.accounts) { account in
                                Text(account.username).tag(Optional(account.id))
                            }
                        }
                    }
                }
                Section {
                    Text("Mặc định: proxy.toichoi.com:54321 — Tôi Chơi NetWork")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(profile.name.isEmpty ? "Add server" : "Edit server")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Huỷ") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        profile.name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        profile.host = profile.host.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(profile)
                        dismiss()
                    }
                    .disabled(profile.name.isEmpty || profile.host.isEmpty)
                }
            }
        }
    }
}

struct MinecraftSkinView: View {
    let username: String
    var body: some View {
        // Skin thật sẽ được thay bằng texture skin khi có API/packet skin; đây là placeholder gọn,
        // không phải icon item. Username không bị điền sẵn trong form.
        ZStack {
            Color.brown.opacity(0.35)
            Image(systemName: "person.fill")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
        }
    }
}
