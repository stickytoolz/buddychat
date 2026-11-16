import SwiftUI

struct BuddyListView: View {
    @EnvironmentObject var store: ChatStore
    @State private var chatWith: ChatTarget?
    @State private var infoFor: ChatTarget?
    @State private var sheet: SheetKind?
    @State private var showOffline = true

    enum SheetKind: String, Identifiable {
        case away, profile, addBuddy, settings, rooms
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                RetroWindow(title: "\(store.myScreenName)'s Buddy List", icon: "list.bullet.rectangle.fill",
                            trailing: {
                                Button { Task { await store.signOff() } } label: {
                                    Text("Sign Off").font(Retro.body(11)).foregroundStyle(.white)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(.white.opacity(0.7)))
                                }
                            }) {
                    VStack(spacing: 0) {
                        header
                        list
                        toolbar
                    }
                }
            }
            .padding(10)
            .background(Color(red: 0.0, green: 0.5, blue: 0.5).ignoresSafeArea())
            .navigationDestination(item: $chatWith) { target in
                IMView(buddyID: target.id)
            }
            .sheet(item: $infoFor) { target in BuddyInfoView(buddyID: target.id) }
            .sheet(item: $sheet) { kind in
                switch kind {
                case .away: AwayMessageView()
                case .profile: ProfileEditorView()
                case .addBuddy: AddBuddyView()
                case .settings: SettingsView()
                case .rooms: RoomsView()
                }
            }
            .overlay(alignment: .top) { bannerView }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: Pieces

    private var header: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                BuddyMascot(size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.myScreenName).font(Retro.titleFont(15)).foregroundStyle(Retro.ink)
                    if let away = store.awayMessage {
                        Text("Away: \(away)").font(Retro.body(11)).foregroundStyle(Retro.dark).lineLimit(1)
                    } else {
                        Text("Available").font(Retro.body(11)).foregroundStyle(.green)
                    }
                }
                Spacer()
            }
            .padding(8)
            .background(Retro.field)
            .bevel(sunken: true)
        }
        .padding(8)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(store.groups) { group in
                    groupSection(group)
                }
                if !store.strangers.isEmpty {
                    groupHeader(name: "Recent IMs", online: store.strangers.count, total: store.strangers.count, collapsed: false) {}
                    ForEach(store.strangers, id: \.self) { uid in buddyRow(uid) }
                }
                offlineSection
            }
            .padding(.vertical, 4)
        }
        .background(Retro.field)
        .bevel(sunken: true)
        .padding(.horizontal, 8)
    }

    private func onlineMembers(_ g: BuddyGroup) -> [String] {
        g.members.filter { (store.users[$0]?.presence(now: store.now) ?? .offline) != .offline || store.flash[$0] != nil }
            .sorted { store.name($0).localizedCaseInsensitiveCompare(store.name($1)) == .orderedAscending }
    }

    private func groupSection(_ g: BuddyGroup) -> some View {
        let online = onlineMembers(g)
        return VStack(alignment: .leading, spacing: 0) {
            groupHeader(name: g.name, online: online.count, total: g.members.count, collapsed: g.collapsed) {
                store.toggleCollapsed(g.id)
            }
            .contextMenu {
                Button("Delete Group", role: .destructive) { Task { await store.deleteGroup(g.id) } }
            }
            if !g.collapsed {
                ForEach(online, id: \.self) { uid in buddyRow(uid) }
            }
        }
    }

    private var offlineSection: some View {
        let offline = store.groups.flatMap(\.members).filter {
            (store.users[$0]?.presence(now: store.now) ?? .offline) == .offline && store.flash[$0] == nil
        }
        return VStack(alignment: .leading, spacing: 0) {
            groupHeader(name: "Offline", online: offline.count, total: offline.count, collapsed: !showOffline) { showOffline.toggle() }
            if showOffline {
                ForEach(offline.sorted { store.name($0) < store.name($1) }, id: \.self) { uid in buddyRow(uid) }
            }
        }
    }

    private func groupHeader(name: String, online: Int, total: Int, collapsed: Bool, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            HStack(spacing: 4) {
                Image(systemName: collapsed ? "arrowtriangle.right.fill" : "arrowtriangle.down.fill").font(.system(size: 9))
                Text("\(name) (\(online)/\(total))").font(Retro.titleFont(13))
                Spacer()
            }
            .foregroundStyle(Retro.ink)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func buddyRow(_ uid: String) -> some View {
        let user = store.users[uid]
        let presence = user?.presence(now: store.now) ?? .offline
        let flashing = store.flash[uid] != nil
        return Button { chatWith = ChatTarget(id: uid) } label: {
            HStack(spacing: 6) {
                if flashing {
                    Image(systemName: presence == .offline ? "door.left.hand.closed" : "door.left.hand.open")
                        .font(.system(size: 12)).foregroundStyle(presence == .offline ? .red : .green)
                        .frame(width: 18)
                } else {
                    presenceIcon(presence).frame(width: 18)
                }
                Text(store.name(uid))
                    .font(presence == .idle || presence == .offline ? Retro.body(14).italic() : Retro.body(14))
                    .foregroundStyle(presence == .offline ? Retro.shadow : Retro.ink)
                if presence == .idle, let m = user?.idleMinutes(now: store.now) {
                    Text("(idle \(m))").font(Retro.body(11)).foregroundStyle(Retro.shadow)
                }
                Spacer()
                if store.unreadFrom(uid) {
                    Image(systemName: "envelope.fill").foregroundStyle(.orange)
                }
            }
            .padding(.leading, 22).padding(.trailing, 8).padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { chatWith = ChatTarget(id: uid) } label: { Label("Send IM", systemImage: "bubble.left") }
            Button { infoFor = ChatTarget(id: uid) } label: { Label("Get Info", systemImage: "info.circle") }
            Menu("Move to Group") {
                ForEach(store.groups) { g in
                    Button(g.name) { Task { await store.addBuddy(uid, toGroup: g.id) } }
                }
            }
            Button(store.blocked.contains(uid) ? "Unblock" : "Block") {
                Task { await store.setBlocked(uid, !store.blocked.contains(uid)) }
            }
            Button("Remove Buddy", role: .destructive) { Task { await store.removeBuddy(uid) } }
        }
    }

    @ViewBuilder
    private func presenceIcon(_ p: Presence) -> some View {
        switch p {
        case .online: Image(systemName: "person.fill").font(.system(size: 12)).foregroundStyle(.green)
        case .away: Image(systemName: "note.text").font(.system(size: 12)).foregroundStyle(.orange)
        case .idle: Image(systemName: "moon.zzz.fill").font(.system(size: 11)).foregroundStyle(.gray)
        case .offline: Image(systemName: "person").font(.system(size: 12)).foregroundStyle(.gray)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 0) {
            toolButton("IM", "bubble.left.fill") { sheet = .addBuddy }
            toolButton("Chat", "person.3.fill") { sheet = .rooms }
            toolButton("Away", "note.text") { sheet = .away }
            toolButton("Profile", "person.text.rectangle") { sheet = .profile }
            toolButton("Setup", "gearshape.fill") { sheet = .settings }
        }
        .padding(8)
    }

    private func toolButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 18))
                Text(title).font(Retro.body(10))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(RetroButtonStyle())
    }

    @ViewBuilder
    private var bannerView: some View {
        if let text = store.banner {
            Text(text)
                .font(Retro.body(13)).foregroundStyle(Retro.ink).lineLimit(2)
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 1, green: 1, blue: 0.85)).bevel()
                .padding(.horizontal, 16).padding(.top, 4)
                .onTapGesture {
                    if let entry = store.inbox.values.max(by: { $0.ts < $1.ts }) { chatWith = ChatTarget(id: entry.with) }
                    store.banner = nil
                }
                .task {
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    store.banner = nil
                }
                .transition(.move(edge: .top))
        }
    }
}

struct ChatTarget: Identifiable, Hashable { let id: String }
