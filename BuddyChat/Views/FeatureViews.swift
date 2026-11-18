import SwiftUI

/// Picks what goes inside each kind of desktop window.
struct WindowContent: View {
    let kind: WindowKind
    var minimized = false

    var body: some View {
        switch kind {
        case .buddyList: BuddyListPane()
        case .im(let uid): IMPane(buddyID: uid, minimized: minimized)
        case .info(let uid): BuddyInfoPane(buddyID: uid)
        case .room(let room): ChatRoomView(room: room)
        case .rooms: RoomsView()
        case .away: AwayMessageView()
        case .profile: ProfileEditorView()
        case .addBuddy: AddBuddyView()
        case .setup: SettingsView()
        case .pounce: PounceView()
        case .history(let uid): HistoryView(buddyID: uid)
        case .directory: DirectoryView()
        case .catcher: CatcherView()
        case .invites: InvitesView()
        case .privacy: PrivacyView()
        }
    }
}

private func sectionTitle(_ text: String) -> some View {
    Text(text).font(Retro.titleFont(12)).foregroundStyle(Retro.ink)
}

private func hint(_ text: String) -> some View {
    Text(text).font(Retro.body(11)).foregroundStyle(Retro.dark).fixedSize(horizontal: false, vertical: true)
}

// MARK: Buddy Pounce

struct PounceView: View {
    @EnvironmentObject var store: ChatStore
    @Environment(\.closeWindow) private var closeWindow
    @State private var buddy: String?
    @State private var triggers: Set<BuddyPounce.Trigger> = [.signsOn]
    @State private var openIM = true
    @State private var message = ""
    @State private var playSound = true
    @State private var keep = false

    private var buddies: [String] {
        Array(store.allBuddyIDs).sorted { store.name($0).localizedCaseInsensitiveCompare(store.name($1)) == .orderedAscending }
    }

    var body: some View {
        Pane(title: "Homie Pounce", icon: "bell.badge.fill") {
            VStack(alignment: .leading, spacing: 10) {
                hint("Get told, or send a message automatically, when a homie signs on or comes back.")

                sectionTitle("New Pounce")
                Menu {
                    ForEach(buddies, id: \.self) { uid in Button(store.name(uid)) { buddy = uid } }
                } label: {
                    HStack {
                        Text(buddy.map { store.name($0) } ?? "Choose a homie…").font(Retro.body(13)).foregroundStyle(Retro.ink)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 10)).foregroundStyle(Retro.ink)
                    }
                    .padding(6).background(Retro.field).bevel(sunken: true)
                }
                Text("When they…").font(Retro.body(12)).foregroundStyle(Retro.ink)
                ForEach(BuddyPounce.Trigger.allCases) { t in
                    Toggle(isOn: Binding(get: { triggers.contains(t) },
                                         set: { on in if on { triggers.insert(t) } else { triggers.remove(t) } })) {
                        Text(t.label).font(Retro.body(12)).foregroundStyle(Retro.ink)
                    }
                    .toggleStyle(CheckboxStyle())
                }
                Text("Then…").font(Retro.body(12)).foregroundStyle(Retro.ink)
                Toggle(isOn: $openIM) { Text("Pop up an IM window").font(Retro.body(12)).foregroundStyle(Retro.ink) }
                    .toggleStyle(CheckboxStyle())
                Toggle(isOn: $playSound) { Text("Play a sound").font(Retro.body(12)).foregroundStyle(Retro.ink) }
                    .toggleStyle(CheckboxStyle())
                RetroField(label: "Send this message (optional)", text: $message)
                Toggle(isOn: $keep) { Text("Keep this pounce after it goes off").font(Retro.body(12)).foregroundStyle(Retro.ink) }
                    .toggleStyle(CheckboxStyle())
                HStack {
                    Spacer()
                    Button("Add Pounce", action: add)
                        .buttonStyle(RetroButtonStyle(bold: true))
                        .disabled(buddy == nil || triggers.isEmpty)
                }

                sectionTitle("Waiting Pounces")
                if store.prefs.pounces.isEmpty {
                    hint("None yet.")
                }
                ForEach(store.prefs.pounces) { p in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.name(p.buddy)).font(Retro.titleFont(12)).foregroundStyle(Retro.ink)
                            Text(BuddyPounce.Trigger.allCases.filter { p.triggers.contains($0) }.map(\.label).joined(separator: ", "))
                                .font(Retro.body(11)).foregroundStyle(Retro.ink)
                            if !p.sendMessage.isEmpty {
                                Text("Sends: \"\(p.sendMessage)\"").font(Retro.body(11)).foregroundStyle(Retro.dark)
                            }
                            Text(p.keep ? "Every time" : "Once").font(Retro.body(10)).foregroundStyle(Retro.dark)
                        }
                        Spacer()
                        Button {
                            store.prefs.pounces.removeAll { $0.id == p.id }
                            store.savePrefs()
                        } label: { Image(systemName: "trash").foregroundStyle(Retro.dark) }
                        .buttonStyle(.plain)
                    }
                    .padding(6).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Retro.field).bevel(sunken: true)
                }
                HStack { Spacer(); Button("Close") { closeWindow() }.buttonStyle(RetroButtonStyle()) }
            }
        }
        .onAppear(perform: prefill)
        .onChange(of: store.pounceFor) { _, _ in prefill() }
    }

    private func prefill() {
        if let uid = store.pounceFor {
            buddy = uid
            store.pounceFor = nil
        }
    }

    private func add() {
        guard let buddy else { return }
        store.prefs.pounces.append(BuddyPounce(buddy: buddy, triggers: triggers, openIM: openIM,
                                               sendMessage: message.trimmingCharacters(in: .whitespacesAndNewlines),
                                               playSound: playSound, keep: keep))
        store.savePrefs()
        message = ""
        self.buddy = nil
    }
}

// MARK: Message history

struct HistoryView: View {
    let buddyID: String
    @EnvironmentObject var store: ChatStore
    @State private var all: [ChatMessage] = []
    @State private var search = ""
    @State private var loading = true

    private var shown: [ChatMessage] {
        let q = search.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? all : all.filter { $0.text.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Retro.dark)
                TextField("Search", text: $search)
                    .font(Retro.body(13)).foregroundStyle(Retro.ink)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            .padding(5).background(Retro.field).bevel(sunken: true)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        let list = shown
                        if loading { ProgressView().frame(maxWidth: .infinity) }
                        if !loading && list.isEmpty {
                            hint(search.isEmpty ? "No messages yet." : "Nothing matches \"\(search)\".")
                        }
                        ForEach(Array(list.enumerated()), id: \.element.id) { i, m in
                            if i == 0 || !Calendar.current.isDate(list[i - 1].date, inSameDayAs: m.date) {
                                Text(m.date.formatted(date: .complete, time: .omitted))
                                    .font(Retro.titleFont(10)).foregroundStyle(Retro.dark)
                                    .frame(maxWidth: .infinity).padding(.top, 4)
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                (Text(m.from == store.myUID ? store.myScreenName : store.name(m.from)).font(Retro.titleFont(11))
                                    .foregroundColor(m.from == store.myUID ? Retro.me : Retro.them)
                                 + Text(" (\(m.date.formatted(date: .omitted, time: .shortened)))").font(Retro.body(9))
                                    .foregroundColor(Retro.shadow))
                                RichText.text(RichText.segments(of: m))
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .id(m.id)
                        }
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Retro.field).bevel(sunken: true)
                .onChange(of: all.count) { _, _ in
                    if let last = all.last?.id { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
            hint("Showing your last \(all.count) messages with \(store.name(buddyID)).")
        }
        .padding(6)
        .task {
            all = await store.history(with: buddyID)
            loading = false
        }
    }
}

// MARK: Member directory

struct DirectoryView: View {
    @EnvironmentObject var store: ChatStore
    @State private var query = ""
    @State private var added: Set<String> = []

    var body: some View {
        VStack(spacing: 6) {
            hint("Search everyone on BuddyChat by screen name, interests, location or profile. Add your own in My Profile.")
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Retro.dark)
                TextField("e.g. skating", text: $query)
                    .font(Retro.body(13)).foregroundStyle(Retro.ink)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            .padding(5).background(Retro.field).bevel(sunken: true)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let results = store.directorySearch(query)
                    if results.isEmpty { hint("No one found.").padding(8) }
                    ForEach(results) { u in
                        row(u)
                        Divider()
                    }
                }
            }
            .background(Retro.field).bevel(sunken: true)
        }
        .padding(6)
    }

    private func row(_ u: UserInfo) -> some View {
        let isBuddy = store.allBuddyIDs.contains(u.id) || added.contains(u.id)
        return HStack(alignment: .top, spacing: 6) {
            BuddyIcon(uid: u.id, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(u.screenName).font(Retro.titleFont(12)).foregroundStyle(Retro.ink)
                if !u.location.isEmpty { Text(u.location).font(Retro.body(10)).foregroundStyle(Retro.dark) }
                if !u.interests.isEmpty { Text(u.interests).font(Retro.body(10)).foregroundStyle(Retro.ink).lineLimit(2) }
            }
            Spacer(minLength: 2)
            VStack(spacing: 3) {
                mini("IM") { store.acceptedStrangers.insert(u.id); store.windows.open(.im(u.id)) }
                mini("Info") { store.windows.open(.info(u.id)) }
                if !isBuddy {
                    mini("Add") {
                        added.insert(u.id)
                        if let g = store.groups.first?.id { Task { await store.addBuddy(u.id, toGroup: g) } }
                    }
                }
            }
        }
        .padding(6)
    }

    private func mini(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Retro.body(10)).foregroundStyle(Retro.ink)
                .frame(width: 38, height: 20).background(Retro.face).bevel()
        }
        .buttonStyle(.plain)
    }
}

// MARK: IM Catcher

struct CatcherView: View {
    @EnvironmentObject var store: ChatStore
    @Environment(\.closeWindow) private var closeWindow

    var body: some View {
        Pane(title: "IM Catcher", icon: "tray.full.fill") {
            VStack(alignment: .leading, spacing: 10) {
                hint("IMs from people who aren't on your Homie List wait here, so strangers can't pop up windows on you.")
                Toggle(isOn: Binding(get: { store.prefs.imCatcher }, set: { store.prefs.imCatcher = $0; store.savePrefs() })) {
                    Text("Catch IMs from strangers").font(Retro.body(12)).foregroundStyle(Retro.ink)
                }
                .toggleStyle(CheckboxStyle())
                if store.caught.isEmpty {
                    hint("No waiting IMs.")
                }
                ForEach(store.caught, id: \.self) { uid in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            BuddyIcon(uid: uid, size: 24)
                            Text(store.realName(uid)).font(Retro.titleFont(12)).foregroundStyle(Retro.ink)
                        }
                        if let preview = store.inbox[conversationID(store.myUID, uid)]?.preview {
                            Text("\"\(preview)\"").font(Retro.body(11)).foregroundStyle(Retro.ink).lineLimit(3)
                        }
                        HStack(spacing: 4) {
                            Button("Block") {
                                store.caught.removeAll { $0 == uid }
                                Task { await store.setBlocked(uid, true) }
                            }
                            .buttonStyle(RetroButtonStyle())
                            Button("Ignore") { store.caught.removeAll { $0 == uid } }.buttonStyle(RetroButtonStyle())
                            Spacer()
                            Button("Read") {
                                store.caught.removeAll { $0 == uid }
                                store.acceptedStrangers.insert(uid)
                                store.windows.open(.im(uid))
                            }
                            .buttonStyle(RetroButtonStyle(bold: true))
                        }
                    }
                    .padding(6).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Retro.field).bevel(sunken: true)
                }
                HStack { Spacer(); Button("Close") { closeWindow() }.buttonStyle(RetroButtonStyle()) }
            }
        }
    }
}

// MARK: Chat invitations

struct InvitesView: View {
    @EnvironmentObject var store: ChatStore
    @Environment(\.closeWindow) private var closeWindow

    var body: some View {
        Pane(title: "Chat Invitations", icon: "envelope.open.fill") {
            VStack(alignment: .leading, spacing: 10) {
                if store.invites.isEmpty { hint("No invitations right now.") }
                ForEach(store.invites) { inv in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(store.name(inv.from)) invited you to the chat room \"\(inv.room)\"")
                            .font(Retro.titleFont(12)).foregroundStyle(Retro.ink)
                        if !inv.message.isEmpty {
                            Text(inv.message).font(Retro.body(12)).foregroundStyle(Retro.ink)
                        }
                        HStack {
                            Button("Decline") { Task { await store.dismissInvite(inv) } }.buttonStyle(RetroButtonStyle())
                            Spacer()
                            Button("Join") {
                                store.windows.open(.room(inv.room))
                                Task { await store.dismissInvite(inv) }
                            }
                            .buttonStyle(RetroButtonStyle(bold: true))
                        }
                    }
                    .padding(6).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Retro.field).bevel(sunken: true)
                }
                HStack { Spacer(); Button("Close") { closeWindow() }.buttonStyle(RetroButtonStyle()) }
            }
        }
    }
}

/// Pick buddies to invite into a chat room.
struct InviteBuddiesSheet: View {
    let room: String
    @EnvironmentObject var store: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var picked: Set<String> = []
    @State private var message = "Come chat with me!"

    private var online: [String] {
        store.allBuddyIDs.filter { (store.users[$0]?.presence(now: store.now) ?? .offline) != .offline }
            .sorted { store.name($0).localizedCaseInsensitiveCompare(store.name($1)) == .orderedAscending }
    }

    var body: some View {
        RetroSheet(title: "Invite to \(room)", icon: "envelope.fill") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Homies who are online").font(Retro.titleFont(12)).foregroundStyle(Retro.ink)
                if online.isEmpty { hint("None of your homies are online right now.") }
                ForEach(online, id: \.self) { uid in
                    Toggle(isOn: Binding(get: { picked.contains(uid) },
                                         set: { on in if on { picked.insert(uid) } else { picked.remove(uid) } })) {
                        Text(store.name(uid)).font(Retro.body(13)).foregroundStyle(Retro.ink)
                    }
                    .toggleStyle(CheckboxStyle())
                }
                RetroField(label: "Message", text: $message)
                HStack {
                    Button("Cancel") { dismiss() }.buttonStyle(RetroButtonStyle())
                    Spacer()
                    Button("Send Invites") {
                        let who = picked, text = message
                        Task {
                            for uid in who { await store.invite(uid, to: room, message: text) }
                        }
                        dismiss()
                    }
                    .buttonStyle(RetroButtonStyle(bold: true))
                    .disabled(picked.isEmpty)
                }
            }
        }
    }
}

// MARK: Privacy

struct PrivacyView: View {
    @EnvironmentObject var store: ChatStore
    @Environment(\.closeWindow) private var closeWindow

    var body: some View {
        Pane(title: "Privacy", icon: "lock.fill") {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("Who can IM me")
                ForEach(AccountPrefs.Privacy.allCases) { p in
                    Button {
                        store.prefs.privacy = p
                        store.savePrefs()
                    } label: {
                        HStack {
                            Image(systemName: store.prefs.privacy == p ? "largecircle.fill.circle" : "circle")
                            Text(p.label)
                        }
                        .font(Retro.body(12)).foregroundStyle(Retro.ink)
                    }
                    .buttonStyle(.plain)
                }
                Toggle(isOn: Binding(get: { store.prefs.imCatcher }, set: { store.prefs.imCatcher = $0; store.savePrefs() })) {
                    Text("Send strangers' IMs to the IM Catcher first").font(Retro.body(12)).foregroundStyle(Retro.ink)
                }
                .toggleStyle(CheckboxStyle())
                .disabled(store.prefs.privacy == .buddiesOnly)

                sectionTitle("Invisible")
                Toggle(isOn: Binding(get: { store.invisible }, set: { on in Task { await store.setInvisible(on) } })) {
                    Text("Appear offline to everyone, but stay signed on").font(Retro.body(12)).foregroundStyle(Retro.ink)
                }
                .toggleStyle(CheckboxStyle())

                sectionTitle("Blocked")
                if store.blocked.isEmpty { hint("You haven't blocked anyone.") }
                ForEach(Array(store.blocked).sorted(), id: \.self) { uid in
                    HStack {
                        Text(store.realName(uid)).font(Retro.body(12)).foregroundStyle(Retro.ink)
                        Spacer()
                        Button("Unblock") { Task { await store.setBlocked(uid, false) } }.buttonStyle(RetroButtonStyle())
                    }
                }
                HStack { Spacer(); Button("Close") { closeWindow() }.buttonStyle(RetroButtonStyle()) }
            }
        }
    }
}
