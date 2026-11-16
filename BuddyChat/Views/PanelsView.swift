import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Shared frame for the smaller pop-up windows.
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
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var saved: [String] = []

    var body: some View {
        RetroSheet(title: "Away Message", icon: "note.text") {
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
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        RetroSheet(title: "My Profile", icon: "person.text.rectangle") {
            VStack(alignment: .leading, spacing: 12) {
                Text("This is what buddies see when they Get Info on you.").font(Retro.body(12)).foregroundStyle(Retro.ink)
                TextEditor(text: $text)
                    .font(Retro.body(14)).foregroundStyle(Retro.ink)
                    .scrollContentBackground(.hidden)
                    .frame(height: 200).padding(4).background(Retro.field).bevel(sunken: true)
                HStack {
                    Button("Cancel") { dismiss() }.buttonStyle(RetroButtonStyle())
                    Spacer()
                    Button("Save") { Task { await store.setProfile(text); dismiss() } }.buttonStyle(RetroButtonStyle(bold: true))
                }
            }
        }
        .onAppear { text = store.users[store.myUID]?.profile ?? "" }
    }
}

// MARK: Add buddy / send IM

struct AddBuddyView: View {
    @EnvironmentObject var store: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var screenName = ""
    @State private var groupID: UUID?
    @State private var newGroup = ""
    @State private var message: String?

    var body: some View {
        RetroSheet(title: "Add a Buddy", icon: "person.badge.plus") {
            VStack(alignment: .leading, spacing: 14) {
                RetroField(label: "Buddy's Screen Name", text: $screenName)
                Text("Add to group").font(Retro.body(12)).foregroundStyle(Retro.ink)
                Picker("Group", selection: $groupID) {
                    ForEach(store.groups) { g in Text(g.name).tag(Optional(g.id)) }
                }
                .pickerStyle(.menu)
                .padding(4).background(Retro.field).bevel(sunken: true)
                if let message { Text(message).font(Retro.body(12)).foregroundStyle(message.hasPrefix("Added") ? .green : .red) }
                HStack {
                    Button("Close") { dismiss() }.buttonStyle(RetroButtonStyle())
                    Spacer()
                    Button("Add Buddy") { add() }.buttonStyle(RetroButtonStyle(bold: true)).disabled(screenName.isEmpty)
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

    private func add() {
        message = nil
        Task {
            guard let uid = await store.lookUp(screenName: screenName) else {
                message = "No one has the screen name \"\(screenName)\"."
                return
            }
            guard uid != store.myUID else { message = "That's you!"; return }
            if let g = groupID ?? store.groups.first?.id { await store.addBuddy(uid, toGroup: g) }
            message = "Added \(store.name(uid)) to your Buddy List."
            screenName = ""
        }
    }
}

// MARK: Settings & skin

struct SettingsView: View {
    @EnvironmentObject var store: ChatStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("theme") private var theme: RetroTheme = .ocean
    @AppStorage("soundsOn") private var soundsOn = true
    @State private var logoItem: PhotosPickerItem?
    @State private var pickingSlot: Sounds.Slot?
    @State private var note: String?
    @State private var refresh = 0

    var body: some View {
        RetroSheet(title: "Setup", icon: "gearshape.fill") {
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
                    Text("Replaces the BuddyChat buddy on the sign-on screen and Buddy List.").font(Retro.body(11)).foregroundStyle(Retro.dark)
                }

                if let note { Text(note).font(Retro.body(12)).foregroundStyle(.red) }

                HStack {
                    Button("Sign Off") { Task { dismiss(); await store.signOff() } }.buttonStyle(RetroButtonStyle())
                    Spacer()
                    Button("Done") { dismiss() }.buttonStyle(RetroButtonStyle(bold: true))
                }
            }
        }
        .fileImporter(isPresented: Binding(get: { pickingSlot != nil }, set: { if !$0 { pickingSlot = nil } }),
                      allowedContentTypes: [.audio]) { result in
            guard let slot = pickingSlot else { return }
            do {
                try Sounds.setCustom(slot, from: try result.get())
                Sounds.shared.play(slot)
                refresh += 1
            } catch {
                note = "Couldn't use that file: \(error.localizedDescription)"
            }
            pickingSlot = nil
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
    @Environment(\.dismiss) private var dismiss
    @State private var room = ""
    @State private var joined: String?

    var body: some View {
        if let joined {
            ChatRoomView(room: joined) { self.joined = nil }
        } else {
            RetroSheet(title: "Chat Rooms", icon: "person.3.fill") {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Type a room name to join it. If it doesn't exist yet, it's created. Give friends the same name to chat together.")
                        .font(Retro.body(12)).foregroundStyle(Retro.ink)
                    RetroField(label: "Room name", text: $room)
                    HStack {
                        Button("Close") { dismiss() }.buttonStyle(RetroButtonStyle())
                        Spacer()
                        Button("Join") {
                            let key = AuthService.normalize(room)
                            if !key.isEmpty { joined = key }
                        }
                        .buttonStyle(RetroButtonStyle(bold: true))
                        .disabled(AuthService.normalize(room).isEmpty)
                    }
                }
            }
        }
    }
}

struct ChatRoomView: View {
    let room: String
    let onLeave: () -> Void
    @EnvironmentObject var store: ChatStore
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
        ZStack {
            Color(red: 0.0, green: 0.5, blue: 0.5).ignoresSafeArea()
            RetroWindow(title: "Chat Room: \(room)", icon: "person.3.fill") {
                VStack(spacing: 8) {
                    Text("In the room: " + (here.isEmpty ? "just you" : here.map { store.name($0) }.joined(separator: ", ")))
                        .font(Retro.body(11)).foregroundStyle(Retro.ink).frame(maxWidth: .infinity, alignment: .leading)
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                ForEach(messages) { m in
                                    (Text((m.fromName ?? store.name(m.from)) + ": ").font(Retro.titleFont(13))
                                        .foregroundColor(m.from == store.myUID ? Retro.me : Retro.them)
                                     + Text(m.text).font(Retro.body(14)).foregroundColor(Retro.ink))
                                        .id(m.id)
                                }
                            }
                            .padding(8)
                        }
                        .background(Retro.field).bevel(sunken: true)
                        .onChange(of: messages.last?.id) { _, last in if let last { proxy.scrollTo(last, anchor: .bottom) } }
                    }
                    HStack {
                        TextField("", text: $draft).font(Retro.body(14)).foregroundStyle(Retro.ink)
                            .padding(6).background(Retro.field).bevel(sunken: true)
                            .onSubmit(send)
                        Button("Send", action: send).buttonStyle(RetroButtonStyle(bold: true))
                    }
                    HStack {
                        Spacer()
                        Button("Leave Room") { leave() }.buttonStyle(RetroButtonStyle())
                    }
                }
                .padding(10)
            }
            .padding(16)
        }
        .onAppear(perform: join)
        .onDisappear(perform: stopAll)
    }

    private func join() {
        streams = [
            store.db.listen("rooms/\(room)/messages", query: ["orderBy": "\"$key\"", "limitToLast": "100"]) { value in
                messages = ((value as? [String: Any]) ?? [:]).compactMap { k, v in
                    (v as? [String: Any]).map { ChatMessage(id: k, dict: $0) }
                }.sorted { $0.id < $1.id }
                Sounds.shared.play(.receive)
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

    private func leave() {
        stopAll()
        Task { try? await store.db.delete("rooms/\(room)/members/\(store.myUID)") }
        onLeave()
    }
}
