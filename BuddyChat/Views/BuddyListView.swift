import SwiftUI

/// The inside of the Buddy List window, which sits docked on the side of the screen.
struct BuddyListPane: View {
    @EnvironmentObject var store: ChatStore
    @State private var showOffline = true
    @State private var readingAway: Set<String> = []

    private var wm: WindowManager { store.windows }

    var body: some View {
        VStack(spacing: 0) {
            header
            list
            toolbar
        }
    }

    // MARK: You

    private var header: some View {
        Button { wm.open(.profile) } label: {
            HStack(spacing: 6) {
                if store.icons[store.myUID] != nil {
                    BuddyIcon(uid: store.myUID, size: 34)
                } else {
                    BuddyMascot(size: 34)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(store.myScreenName).font(Retro.titleFont(12)).foregroundStyle(Retro.ink).lineLimit(1)
                    Group {
                        if store.invisible {
                            Text("Invisible").foregroundStyle(Retro.dark)
                        } else if store.awayMessage != nil {
                            Text("Away").foregroundStyle(.orange)
                        } else {
                            Text("Available").foregroundStyle(.green)
                        }
                    }
                    .font(Retro.body(10))
                    let level = store.warningLevel(store.myUID)
                    if level > 0 {
                        Text("Warning: \(level)%").font(Retro.body(9)).foregroundStyle(.red)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(5)
            .background(Retro.field)
            .bevel(sunken: true)
        }
        .buttonStyle(.plain)
        .padding(5)
    }

    // MARK: Buddies

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
            .padding(.vertical, 3)
        }
        .background(Retro.field)
        .bevel(sunken: true)
        .padding(.horizontal, 5)
    }

    private func isShown(_ uid: String) -> Bool {
        (store.users[uid]?.presence(now: store.now) ?? .offline) != .offline || store.flash[uid] != nil
    }

    private func onlineMembers(_ g: BuddyGroup) -> [String] {
        g.members.filter(isShown)
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
        let offline = store.groups.flatMap(\.members).filter { !isShown($0) }
        return VStack(alignment: .leading, spacing: 0) {
            groupHeader(name: "Offline", online: offline.count, total: offline.count, collapsed: !showOffline) { showOffline.toggle() }
            if showOffline {
                ForEach(offline.sorted { store.name($0).localizedCaseInsensitiveCompare(store.name($1)) == .orderedAscending },
                        id: \.self) { uid in buddyRow(uid) }
            }
        }
    }

    private func groupHeader(name: String, online: Int, total: Int, collapsed: Bool, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            HStack(spacing: 3) {
                Image(systemName: collapsed ? "arrowtriangle.right.fill" : "arrowtriangle.down.fill").font(.system(size: 8))
                Text("\(name) (\(online)/\(total))").font(Retro.titleFont(11)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Retro.ink)
            .padding(.horizontal, 5).padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func buddyRow(_ uid: String) -> some View {
        let user = store.users[uid]
        let presence = user?.presence(now: store.now) ?? .offline
        let flashing = store.flash[uid] != nil
        let away = presence == .away ? user?.awayMessage : nil
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Button { wm.open(.im(uid)) } label: {
                    HStack(spacing: 4) {
                        if flashing {
                            Image(systemName: presence == .offline ? "door.left.hand.closed" : "door.left.hand.open")
                                .font(.system(size: 11)).foregroundStyle(presence == .offline ? .red : .green)
                                .frame(width: 14)
                        } else if away == nil {
                            presenceIcon(presence).frame(width: 14)
                        }
                        if store.icons[uid] != nil { BuddyIcon(uid: uid, size: 16) }
                        Text(store.name(uid))
                            .font(presence == .idle || presence == .offline ? Retro.body(12).italic() : Retro.body(12))
                            .foregroundStyle(presence == .offline ? Retro.shadow : Retro.ink)
                            .lineLimit(1)
                        if presence == .idle, let m = user?.idleMinutes(now: store.now) {
                            Text("(\(m))").font(Retro.body(9)).foregroundStyle(Retro.shadow)
                        }
                        Spacer(minLength: 0)
                        if store.unreadFrom(uid) {
                            Image(systemName: "envelope.fill").font(.system(size: 11)).foregroundStyle(.orange)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .overlay(alignment: .leading) {
                // Tap the away note to read their away message right here.
                if away != nil && !flashing {
                    Button {
                        if readingAway.contains(uid) { readingAway.remove(uid) } else { readingAway.insert(uid) }
                    } label: {
                        Image(systemName: "note.text").font(.system(size: 12)).foregroundStyle(.orange)
                            .frame(width: 18, height: 18).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .offset(x: -2)
                }
            }
            .padding(.leading, away != nil && !flashing ? 18 : 0)
            if let away, readingAway.contains(uid) {
                LinkedText(text: store.expandAway(away, for: nil), size: 11)
                    .padding(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(red: 1, green: 1, blue: 0.85))
                    .bevel()
                    .onTapGesture { readingAway.remove(uid) }
            }
        }
        .padding(.leading, 12).padding(.trailing, 5).padding(.vertical, 3)
        .contextMenu {
            Button { wm.open(.im(uid)) } label: { Label("Send IM", systemImage: "bubble.left") }
            Button { wm.open(.info(uid)) } label: { Label("Get Info / Nickname", systemImage: "info.circle") }
            if away != nil {
                Button { readingAway.insert(uid) } label: { Label("Read Away Message", systemImage: "note.text") }
            }
            Button { store.pounceFor = uid; wm.open(.pounce) } label: { Label("Buddy Pounce…", systemImage: "bell.badge") }
            Button { wm.open(.history(uid)) } label: { Label("Message History", systemImage: "clock.arrow.circlepath") }
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
        case .online: Image(systemName: "person.fill").font(.system(size: 11)).foregroundStyle(.green)
        case .away: Image(systemName: "note.text").font(.system(size: 11)).foregroundStyle(.orange)
        case .idle: Image(systemName: "moon.zzz.fill").font(.system(size: 10)).foregroundStyle(.gray)
        case .offline: Image(systemName: "person").font(.system(size: 11)).foregroundStyle(.gray)
        }
    }

    // MARK: Buttons along the bottom

    private var toolbar: some View {
        HStack(spacing: 3) {
            toolButton("IM", "bubble.left.fill") { wm.open(.addBuddy) }
            toolButton("Chat", "person.3.fill") { wm.open(.rooms) }
            toolButton("Away", "note.text") { wm.open(.away) }
            Menu {
                Button { wm.open(.addBuddy) } label: { Label("Add Buddy", systemImage: "person.badge.plus") }
                Button { wm.open(.profile) } label: { Label("My Profile & Icon", systemImage: "person.text.rectangle") }
                Button { store.pounceFor = nil; wm.open(.pounce) } label: { Label("Buddy Pounce", systemImage: "bell.badge") }
                Button { wm.open(.directory) } label: { Label("Member Directory", systemImage: "magnifyingglass") }
                Button { wm.open(.catcher) } label: {
                    Label(store.caught.isEmpty ? "IM Catcher" : "IM Catcher (\(store.caught.count))", systemImage: "tray.full")
                }
                Button { wm.open(.invites) } label: {
                    Label(store.invites.isEmpty ? "Chat Invitations" : "Chat Invitations (\(store.invites.count))", systemImage: "envelope.open")
                }
                Button { wm.open(.privacy) } label: { Label("Privacy", systemImage: "lock") }
                Button { Task { await store.setInvisible(!store.invisible) } } label: {
                    Label(store.invisible ? "Become Visible" : "Go Invisible", systemImage: store.invisible ? "eye" : "eye.slash")
                }
                Button { wm.open(.setup) } label: { Label("Setup", systemImage: "gearshape") }
                Divider()
                Button(role: .destructive) { Task { await store.signOff() } } label: {
                    Label("Sign Off", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } label: {
                toolLabel("More", "ellipsis.circle.fill", badge: !store.caught.isEmpty || !store.invites.isEmpty)
            }
        }
        .padding(5)
    }

    private func toolButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { toolLabel(title, icon) }.buttonStyle(.plain)
    }

    private func toolLabel(_ title: String, _ icon: String, badge: Bool = false) -> some View {
        VStack(spacing: 1) {
            Image(systemName: icon).font(.system(size: 14))
            Text(title).font(Retro.body(9))
        }
        .foregroundStyle(Retro.ink)
        .frame(maxWidth: .infinity, minHeight: 36)
        .background(Retro.face)
        .bevel()
        .overlay(alignment: .topTrailing) {
            if badge { Circle().fill(.red).frame(width: 8, height: 8).padding(3) }
        }
    }
}
