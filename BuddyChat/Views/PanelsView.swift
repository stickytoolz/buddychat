import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// The inside of a desktop window: the window supplies the title bar, this just scrolls.
struct Pane<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView { content().padding(12) }
    }
}

/// Shared frame for real pop-up sheets (pickers and such).
struct RetroSheet<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Color(red: 0.0, green: 0.5, blue: 0.5).ignoresSafeArea()
            RetroWindow(title: title, icon: icon) {
                ScrollView { content().padding(18) }
            }
            .padding(16)
        }
    }
}

// MARK: Away message

struct AwayMessageView: View {
    @EnvironmentObject var store: ChatStore
    @Environment(\.closeWindow) private var dismiss
    @State private var text = ""
    @State private var saved: [String] = []

    var body: some View {
        Pane(title: "Away Message", icon: "note.text") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Write your away message. People who IM you get it as an auto response.")
                    .font(Retro.body(12)).foregroundStyle(Retro.ink)
                TextEditor(text: $text)
                    .font(Retro.body(14)).foregroundStyle(Retro.ink)
                    .scrollContentBackground(.hidden)
                    .frame(height: 110).padding(4).background(Retro.field).bevel(sunken: true)
                Text("Tip: %n = their screen name, %t = time, %d = date").font(Retro.body(11)).foregroundStyle(Retro.dark)

                HStack {
                    Button("I'm Back") {
                        Task { await store.setAway(nil); dismiss() }
                    }
                    .buttonStyle(RetroButtonStyle())
                    .disabled(store.awayMessage == nil)
                    Spacer()
                    Button("Save") {
                        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !t.isEmpty, !saved.contains(t) else { return }
                        saved.insert(t, at: 0)
                        store.savedAwayMessages = saved
                    }
                    .buttonStyle(RetroButtonStyle())
                    Button("I'm Away") {
                        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        Task { await store.setAway(t.isEmpty ? "I am away right now." : t); dismiss() }
                    }
                    .buttonStyle(RetroButtonStyle(bold: true))
                }

                Text("Saved Away Messages").font(Retro.titleFont(12)).foregroundStyle(Retro.ink).padding(.top, 8)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(saved, id: \.self) { msg in
                        HStack {
                            Text(msg).font(Retro.body(13)).foregroundStyle(Retro.ink).lineLimit(2)
                            Spacer()
                            Button { saved.removeAll { $0 == msg }; store.savedAwayMessages = saved } label: {
                                Image(systemName: "trash").foregroundStyle(Retro.dark)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(8)
                        .contentShape(Rectangle())
                        .onTapGesture { text = msg }
                        Divider()
                    }
                }
                .background(Retro.field).bevel(sunken: true)

                Button("Close") { dismiss() }.buttonStyle(RetroButtonStyle()).frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .onAppear {
            saved = store.savedAwayMessages
            text = store.awayMessage ?? ""
        }
    }
}

// MARK: Profile

struct ProfileEditorView: View {
    @EnvironmentObject var store: ChatStore
    @Environment(\.closeWindow) private var dismiss
    @State private var text = ""
    @State private var interests = ""
    @State private var location = ""
    @State private var iconItem: PhotosPickerItem?
    @State private var working = false

    var body: some View {
        Pane(title: "My Profile", icon: "person.text.rectangle") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Homie Icon").font(Retro.titleFont(12)).foregroundStyle(Retro.ink)
                HStack(spacing: 10) {
                    BuddyIcon(uid: store.myUID, size: 56)
                    VStack(alignment: .leading, spacing: 6) {
                        PhotosPicker(selection: $iconItem, matching: .images) {
                            Text("Choose Picture").font(Retro.body(12)).foregroundStyle(Retro.ink)
                                .padding(.horizontal, 10).padding(.vertical, 5).background(Retro.face).bevel()
                        }
                        if store.icons[store.myUID] != nil {
                            Button("Remove") { Task { await store.setMyIcon(nil) } }.buttonStyle(RetroButtonStyle())
                        }
                    }
                    if working { ProgressView() }
                }
                Text("Shows next to your name on homies' lists and in IMs.").font(Retro.body(10)).foregroundStyle(Retro.dark)

                Text("Profile").font(Retro.titleFont(12)).foregroundStyle(Retro.ink)
                Text("What homies see when they Get Info on you. Links work.").font(Retro.body(11)).foregroundStyle(Retro.ink)
                TextEditor(text: $text)
                    .font(Retro.body(14)).foregroundStyle(Retro.ink)
                    .scrollContentBackground(.hidden)
                    .frame(height: 140).padding(4).background(Retro.field).bevel(sunken: true)

                Text("Member Directory").font(Retro.titleFont(12)).foregroundStyle(Retro.ink)
                RetroField(label: "Location", text: $location)
                RetroField(label: "Interests (e.g. skating, punk, anime)", text: $interests)

                HStack {
                    Button("Cancel") { dismiss() }.buttonStyle(RetroButtonStyle())
                    Spacer()
                    Button("Save") {
                        Task {
                            await store.setProfile(text)
                            await store.setDirectoryInfo(interests: interests, location: location)
                            dismiss()
                        }
                    }
                    .buttonStyle(RetroButtonStyle(bold: true))
                }
            }
        }
        .onAppear {
            let me = store.users[store.myUID]
            text = me?.profile ?? ""
            interests = me?.interests ?? ""
            location = me?.location ?? ""
        }
        .onChange(of: iconItem) { _, item in
            guard let item else { return }
            working = true
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    await store.setMyIcon(img)
                }
                iconItem = nil
                working = false
            }
        }
    }
}

// MARK: Add buddy / send IM

struct AddBuddyView: View {
    @EnvironmentObject var store: ChatStore
    @Environment(\.closeWindow) private var dismiss
    @State private var screenName = ""
    @State private var groupID: UUID?
    @State private var newGroup = ""
    @State private var message: String?

    var body: some View {
        Pane(title: "Add a Homie", icon: "person.badge.plus") {
            VStack(alignment: .leading, spacing: 14) {
                RetroField(label: "Homie's Screen Name", text: $screenName)
                Text("Add to group").font(Retro.body(12)).foregroundStyle(Retro.ink)
                Picker("Group", selection: $groupID) {
                    ForEach(store.groups) { g in Text(g.name).tag(Optional(g.id)) }
                }
                .pickerStyle(.menu)
                .padding(4).background(Retro.field).bevel(sunken: true)
                if let message { Text(message).font(Retro.body(12)).foregroundStyle(message.hasPrefix("Added") ? .green : .red) }
                HStack {
                    Button("Send IM") { sendIM() }.buttonStyle(RetroButtonStyle()).disabled(screenName.isEmpty)
                    Spacer()
                    Button("Add Homie") { add() }.buttonStyle(RetroButtonStyle(bold: true)).disabled(screenName.isEmpty)
                }

                Divider().padding(.vertical, 6)
                Text("New Group").font(Retro.titleFont(12)).foregroundStyle(Retro.ink)
                HStack {
                    RetroField(label: "Group name", text: $newGroup)
                    Button("Create") {
                        Task { await store.addGroup(newGroup); newGroup = "" }
                    }
                    .buttonStyle(RetroButtonStyle())
                    .disabled(newGroup.isEmpty)
                    .padding(.top, 16)
                }
            }
        }
        .onAppear { groupID = store.groups.first?.id }
    }

    private func sendIM() {
        message = nil
        Task {
            guard let uid = await store.lookUp(screenName: screenName) else {
                message = "No one has the screen name \"\(screenName)\"."
                return
            }
            guard uid != store.myUID else { message = "That's you!"; return }
            store.acceptedStrangers.insert(uid)
            store.windows.open(.im(uid))
            screenName = ""
        }
    }

    private func add() {
        message = nil
        Task {
            guard let uid = await store.lookUp(screenName: screenName) else {
                message = "No one has the screen name \"\(screenName)\"."
                return
            }
            guard uid != store.myUID else { message = "That's you!"; return }
            if let g = groupID ?? store.groups.first?.id { await store.addBuddy(uid, toGroup: g) }
            message = "Added \(store.name(uid)) to your Homie List."
            screenName = ""
        }
    }
}

// MARK: Settings & skin

struct SettingsView: View {
    @EnvironmentObject var store: ChatStore
    @Environment(\.closeWindow) private var dismiss
    @AppStorage("theme") private var theme: RetroTheme = .ocean
    @AppStorage("soundsOn") private var soundsOn = true
    @State private var logoItem: PhotosPickerItem?
    @State private var wallpaperItem: PhotosPickerItem?
    @AppStorage("wallpaper") private var wallpaper: Wallpaper = .teal
    @AppStorage("wallpaperStamp") private var wallpaperStamp = 0
    @State private var pickingSlot: Sounds.Slot?
    @State private var note: String?
    @State private var refresh = 0

    var body: some View {
        Pane(title: "Setup", icon: "gearshape.fill") {
            VStack(alignment: .leading, spacing: 16) {
                section("Window Color") {
                    HStack {
                        ForEach(RetroTheme.allCases) { t in
                            Button { theme = t } label: {
                                LinearGradient(colors: t.colors, startPoint: .leading, endPoint: .trailing)
                                    .frame(height: 28)
                                    .overlay(Rectangle().stroke(theme == t ? Retro.ink : .clear, lineWidth: 3))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                section("Desktop Wallpaper") {
                    ForEach(Wallpaper.allCases.filter { $0 != .custom }) { w in
                        Button { wallpaper = w } label: {
                            HStack {
                                Image(systemName: wallpaper == w ? "largecircle.fill.circle" : "circle")
                                Text(w.label)
                            }
                            .font(Retro.body(13)).foregroundStyle(Retro.ink)
                        }
                        .buttonStyle(.plain)
                    }
                    PhotosPicker(selection: $wallpaperItem, matching: .images) {
                        HStack {
                            Image(systemName: wallpaper == .custom ? "largecircle.fill.circle" : "circle")
                            Text("My Picture…")
                        }
                        .font(Retro.body(13)).foregroundStyle(Retro.ink)
                    }
                }

                section("Sounds") {
                    Toggle(isOn: $soundsOn) { Text("Play sounds").font(Retro.body(13)).foregroundStyle(Retro.ink) }
                        .toggleStyle(CheckboxStyle())
                    ForEach(Sounds.Slot.allCases) { slot in
                        HStack {
                            Text(slot.label).font(Retro.body(13)).foregroundStyle(Retro.ink)
                            Spacer()
                            Button { Sounds.shared.play(slot) } label: { Image(systemName: "play.fill") }.buttonStyle(RetroButtonStyle())
                            Button("Change") { pickingSlot = slot }.buttonStyle(RetroButtonStyle())
                            if Sounds.customURL(slot) != nil {
                                Button("Reset") { Sounds.resetCustom(slot); refresh += 1 }.buttonStyle(RetroButtonStyle())
                            }
                        }
                    }
                    Text("Use \"Change\" to pick any sound file from your Files app.").font(Retro.body(11)).foregroundStyle(Retro.dark)
                }
                .id(refresh)

                section("Skin Picture") {
                    HStack {
                        BuddyMascot(size: 60).id(refresh)
                        PhotosPicker(selection: $logoItem, matching: .images) {
                            Text("Choose Picture").font(Retro.body(13)).foregroundStyle(Retro.ink)
                                .padding(.horizontal, 12).padding(.vertical, 6).background(Retro.face).bevel()
                        }
                        if SkinStore.customLogo != nil {
                            Button("Reset") { try? FileManager.default.removeItem(at: SkinStore.logoURL); refresh += 1 }
                                .buttonStyle(RetroButtonStyle())
                        }
                    }
                    Text("Replaces the BuddyChat mascot on the sign-on screen and taskbar.").font(Retro.body(11)).foregroundStyle(Retro.dark)
                }

                if let note { Text(note).font(Retro.body(12)).foregroundStyle(.red) }

                HStack {
                    Button("Sign Off") { Task { dismiss(); await store.signOff() } }.buttonStyle(RetroButtonStyle())
                    Spacer()
                    Button("Done") { dismiss() }.buttonStyle(RetroButtonStyle(bold: true))
                }
            }
        }
        .sheet(item: $pickingSlot) { slot in
            DocumentPicker(types: [.audio]) { url in
                pickingSlot = nil
                guard let url else { return }
                do {
                    try Sounds.setCustom(slot, from: url)
                    Sounds.shared.play(slot)
                    refresh += 1
                } catch {
                    note = "Couldn't use that file: \(error.localizedDescription)"
                }
            }
            .ignoresSafeArea()
        }
        .onChange(of: wallpaperItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data),
                   let jpeg = img.jpegData(compressionQuality: 0.85) {
                    try? jpeg.write(to: Wallpaper.customURL)
                    wallpaper = .custom
                    wallpaperStamp += 1
                }
                wallpaperItem = nil
            }
        }
        .onChange(of: logoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data),
                   let png = img.pngData() {
                    try? png.write(to: SkinStore.logoURL)
                    refresh += 1
                }
                logoItem = nil
            }
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Retro.titleFont(13)).foregroundStyle(Retro.ink)
            VStack(alignment: .leading, spacing: 8) { content() }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(Retro.face).bevel(sunken: true)
        }
    }
}

// MARK: Chat rooms

struct RoomsView: View {
    @EnvironmentObject var store: ChatStore
    @Environment(\.closeWindow) private var dismiss
    @State private var room = ""

    var body: some View {
        Pane(title: "Chat Rooms", icon: "person.3.fill") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Type a room name to join it. If it doesn't exist yet, it's created. Use Invite inside the room to bring homies in.")
                    .font(Retro.body(12)).foregroundStyle(Retro.ink)
                RetroField(label: "Room name", text: $room)
                    .onSubmit(join)
                HStack {
                    Button("Close") { dismiss() }.buttonStyle(RetroButtonStyle())
                    Spacer()
                    Button("Join", action: join)
                        .buttonStyle(RetroButtonStyle(bold: true))
                        .disabled(AuthService.normalize(room).isEmpty)
                }
            }
        }
    }

    private func join() {
        let key = AuthService.normalize(room)
        guard !key.isEmpty else { return }
        store.windows.open(.room(key))
        dismiss()
    }
}

struct ChatRoomView: View {
    let room: String
    @EnvironmentObject var store: ChatStore
    @Environment(\.closeWindow) private var closeWindow
    @State private var inviting = false
    @State private var loaded = false
    @State private var messages: [ChatMessage] = []
    @State private var members: [String: Double] = [:]
    @State private var draft = ""
    @State private var streams: [LiveQuery] = []
    @State private var timer: Timer?

    private var here: [String] {
        let now = Date().timeIntervalSince1970 * 1000
        return members.filter { now - $0.value < 120_000 }.keys.sorted { store.name($0) < store.name($1) }
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top) {
                Text("Here: " + (here.isEmpty ? "just you" : here.map { store.name($0) }.joined(separator: ", ")))
                    .font(Retro.body(10)).foregroundStyle(Retro.ink).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Invite") { inviting = true }.buttonStyle(RetroButtonStyle())
                Button("Leave") { leave() }.buttonStyle(RetroButtonStyle())
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(messages) { m in
                            (Text((m.fromName ?? store.name(m.from)) + ": ").font(Retro.titleFont(12))
                                .foregroundColor(m.from == store.myUID ? Retro.me : Retro.them)
                             + RichText.text(m.text, style: TextStyle()))
                                .fixedSize(horizontal: false, vertical: true)
                                .id(m.id)
                        }
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Retro.field).bevel(sunken: true)
                .onChange(of: messages.last?.id) { _, last in if let last { proxy.scrollTo(last, anchor: .bottom) } }
            }
            HStack {
                TextField("", text: $draft).font(Retro.body(14)).foregroundStyle(Retro.ink)
                    .padding(5).background(Retro.field).bevel(sunken: true)
                    .onSubmit(send)
                Button("Send", action: send).buttonStyle(RetroButtonStyle(bold: true))
            }
        }
        .padding(6)
        .onAppear(perform: join)
        .onDisappear(perform: leaveQuietly)
        .sheet(isPresented: $inviting) { InviteBuddiesSheet(room: room) }
    }

    private func join() {
        streams = [
            store.db.listen("rooms/\(room)/messages", query: ["orderBy": "\"$key\"", "limitToLast": "100"]) { value in
                let next = ((value as? [String: Any]) ?? [:]).compactMap { k, v in
                    (v as? [String: Any]).map { ChatMessage(id: k, dict: $0) }
                }.sorted { $0.id < $1.id }
                if loaded, let last = next.last, last.id != messages.last?.id, last.from != store.myUID {
                    Sounds.shared.play(.receive)
                }
                messages = next
                loaded = true
            },
            store.db.listen("rooms/\(room)/members") { value in
                members = ((value as? [String: Any]) ?? [:]).compactMapValues { ($0 as? NSNumber)?.doubleValue }
            },
        ]
        ping()
        timer = Timer.scheduledTimer(withTimeInterval: 45, repeats: true) { _ in Task { @MainActor in ping() } }
    }

    private func ping() {
        Task { try? await store.db.put("rooms/\(room)/members/\(store.myUID)", Database.serverTimestamp) }
    }

    private func send() {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        draft = ""
        Task {
            try? await store.db.push("rooms/\(room)/messages", [
                "from": store.myUID, "name": store.myScreenName, "text": t, "ts": Database.serverTimestamp,
            ] as [String: Any])
        }
    }

    private func stopAll() {
        streams.forEach { $0.stop() }
        streams = []
        timer?.invalidate()
    }

    private func leaveQuietly() {
        stopAll()
        Task { try? await store.db.delete("rooms/\(room)/members/\(store.myUID)") }
    }

    private func leave() {
        leaveQuietly()
        closeWindow()
    }
}
