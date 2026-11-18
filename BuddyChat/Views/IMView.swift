import SwiftUI

/// A buddy's picture, or a plain placeholder if they haven't set one.
struct BuddyIcon: View {
    let uid: String
    var size: CGFloat = 32
    @EnvironmentObject var store: ChatStore

    var body: some View {
        Group {
            if let img = store.icons[uid] {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                ZStack {
                    Retro.face
                    Image(systemName: "person.fill").font(.system(size: size * 0.55)).foregroundStyle(Retro.shadow)
                }
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .bevel(sunken: true)
    }
}

/// The inside of an IM window.
struct IMPane: View {
    let buddyID: String
    var minimized = false
    @EnvironmentObject var store: ChatStore
    @State private var draft = ""
    @State private var pieces: [RichSegment] = []     // earlier parts of the message, each in its own style
    @State private var sendError: String?
    @State private var attach: AttachPicker?
    @State private var confirmWarn = false
    @AppStorage("myStyle") private var styleData: Data = Data()
    @AppStorage private var backgroundRaw: String

    init(buddyID: String, minimized: Bool = false) {
        self.buddyID = buddyID
        self.minimized = minimized
        _backgroundRaw = AppStorage(wrappedValue: IMBackground.plain.rawValue, "imBackground.\(buddyID)")
    }

    private var conv: String { conversationID(store.myUID, buddyID) }
    private var background: IMBackground { IMBackground(rawValue: backgroundRaw) ?? .plain }
    private var style: TextStyle {
        get { (try? JSONDecoder().decode(TextStyle.self, from: styleData)) ?? TextStyle() }
        nonmutating set { styleData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
    private var blocked: Bool { store.blocked.contains(buddyID) }
    private var canSend: Bool {
        !blocked && !(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && pieces.isEmpty)
    }

    var body: some View {
        let user = store.users[buddyID]
        let presence = user?.presence(now: store.now) ?? .offline
        VStack(spacing: 4) {
            statusBar(user: user, presence: presence)
            transcript
            if store.typing[conv]?.isEmpty == false {
                Text("\(store.name(buddyID)) is typing…").font(Retro.body(10)).italic()
                    .foregroundStyle(Retro.dark).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6)
            }
            if blocked {
                Text("You've blocked this person. Unblock from Get Info to talk.").font(Retro.body(10)).foregroundStyle(.red)
            }
            if let sendError { Text(sendError).font(Retro.body(10)).foregroundStyle(.red).padding(.horizontal, 6) }
            formatBar
            if !pieces.isEmpty { piecesPreview }
            composer
        }
        .padding(.bottom, 6)
        .onAppear { store.open(with: buddyID) }
        .onDisappear { store.close(conv) }
        .onChange(of: minimized) { _, isMin in if !isMin { store.markRead(conv) } }
        .confirmationDialog("Warn \(store.name(buddyID))?", isPresented: $confirmWarn, titleVisibility: .visible) {
            Button("Warn", role: .destructive) {
                Task {
                    do { try await store.warn(buddyID) } catch { sendError = "Couldn't warn: \(error.localizedDescription)" }
                }
            }
        } message: {
            Text("Each warning raises their warning level by 10% for a day. At 50% or more, they have to wait between messages.")
        }
    }

    // MARK: Top bar: picture, status, warning level, buttons

    private func statusBar(user: UserInfo?, presence: Presence) -> some View {
        HStack(spacing: 6) {
            BuddyIcon(uid: buddyID, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Group {
                    switch presence {
                    case .online: Text("Online").foregroundStyle(.green)
                    case .away: Text("Away").foregroundStyle(.orange)
                    case .idle: Text("Idle \(user?.idleMinutes(now: store.now) ?? 0) min").foregroundStyle(.gray)
                    case .offline: Text("Offline (gets it later)").foregroundStyle(.gray)
                    }
                }
                .font(Retro.body(10))
                Text("Warning: \(store.warningLevel(buddyID))%").font(Retro.body(9)).foregroundStyle(Retro.dark)
            }
            Spacer(minLength: 2)
            smallButton("Info") { store.windows.open(.info(buddyID)) }
            smallButton("Warn") { confirmWarn = true }
                .disabled(store.alreadyWarned(buddyID) || blocked)
                .opacity(store.alreadyWarned(buddyID) ? 0.5 : 1)
            Menu {
                Button { store.windows.open(.history(buddyID)) } label: { Label("Message History", systemImage: "clock.arrow.circlepath") }
                Button { store.pounceFor = buddyID; store.windows.open(.pounce) } label: { Label("Homie Pounce…", systemImage: "bell.badge") }
                Menu {
                    ForEach(IMBackground.allCases) { bg in
                        Button { backgroundRaw = bg.rawValue } label: {
                            if bg == background { Label(bg.label, systemImage: "checkmark") } else { Text(bg.label) }
                        }
                    }
                } label: { Label("Background", systemImage: "paintpalette") }
                Button(blocked ? "Unblock" : "Block", role: blocked ? nil : .destructive) {
                    Task { await store.setBlocked(buddyID, !blocked) }
                }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 12, weight: .bold)).foregroundStyle(Retro.ink)
                    .frame(width: 26, height: 22).background(Retro.face).bevel()
            }
        }
        .padding(.horizontal, 6).padding(.top, 6)
    }

    private func smallButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Retro.body(10)).foregroundStyle(Retro.ink)
                .padding(.horizontal, 6).frame(height: 22).background(Retro.face).bevel()
        }
        .buttonStyle(.plain)
    }

    // MARK: Conversation

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(store.messages[conv] ?? []) { m in
                        messageRow(m).id(m.id)
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(IMBackgroundView(background: background))
            .bevel(sunken: true)
            .padding(.horizontal, 6)
            .onChange(of: store.messages[conv]?.last?.id) { _, last in
                if let last { withAnimation { proxy.scrollTo(last, anchor: .bottom) } }
            }
            .onAppear {
                if let last = store.messages[conv]?.last?.id { proxy.scrollTo(last, anchor: .bottom) }
            }
        }
    }

    private func messageRow(_ m: ChatMessage) -> some View {
        let mine = m.from == store.myUID
        let name = mine ? store.myScreenName : store.name(m.from)
        let time = m.date.formatted(date: .omitted, time: .shortened)
        return VStack(alignment: .leading, spacing: 1) {
            (Text(m.isAuto ? "Auto response from \(name)" : name).font(Retro.titleFont(12))
                .foregroundColor(mine ? Retro.me : Retro.them)
             + Text(" (\(time)):").font(Retro.body(9)).foregroundColor(Retro.shadow))
            if let offer = m.file {
                FileCard(offer: offer, message: m, buddyID: buddyID)
            } else {
                RichText.text(RichText.segments(of: m))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Formatting

    /// Changing the style partway through keeps what you already typed in the old style (per-word formatting).
    private func restyle(_ change: (inout TextStyle) -> Void) {
        let old = style
        var new = old
        change(&new)
        guard new != old else { return }
        if !draft.isEmpty {
            pieces.append(RichSegment(text: draft, style: old))
            draft = ""
        }
        style = new
    }

    private var formatBar: some View {
        HStack(spacing: 4) {
            Menu {
                ForEach(TextStyle.fonts, id: \.self) { f in
                    Button { restyle { $0.font = f } } label: { Text(f) }
                }
            } label: {
                Text(style.font).font(.custom(style.font, size: 11)).lineLimit(1)
                    .foregroundStyle(Retro.ink).padding(.horizontal, 4).frame(maxWidth: 70, minHeight: 22)
                    .background(Retro.field).bevel(sunken: true)
            }
            fmt("A-") { restyle { $0.size = max(11, $0.size - 2) } }
            fmt("A+") { restyle { $0.size = min(28, $0.size + 2) } }
            fmt("B", on: style.bold) { restyle { $0.bold.toggle() } }
            fmt("I", on: style.italic) { restyle { $0.italic.toggle() } }
            fmt("U", on: style.underline) { restyle { $0.underline.toggle() } }
            Menu {
                ForEach(TextStyle.colors, id: \.self) { c in
                    Button { restyle { $0.color = c } } label: { Label(c, systemImage: "circle.fill") }
                }
            } label: {
                Circle().fill(Color(hex: style.color)).frame(width: 18, height: 18).overlay(Circle().stroke(Retro.dark))
            }
            Menu {
                ForEach(Smiley.allCases) { face in
                    Button { insert(face.code) } label: {
                        Label { Text(face.code) } icon: { Image(uiImage: face.image(size: 22)) }
                    }
                }
            } label: {
                Image(uiImage: Smiley.smile.image(size: 20)).frame(width: 24, height: 22).background(Retro.face).bevel()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
    }

    private func fmt(_ label: String, on: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(label == "B" ? Retro.titleFont(11) : label == "I" ? Retro.body(11).italic() : Retro.body(11))
                .underline(label == "U")
                .foregroundStyle(Retro.ink)
                .frame(width: 24, height: 22)
                .background(on ? Retro.shadow.opacity(0.4) : Retro.face)
                .bevel(sunken: on)
        }
        .buttonStyle(.plain)
    }

    private func insert(_ code: String) {
        if !draft.isEmpty && !draft.hasSuffix(" ") { draft += " " }
        draft += code + " "
    }

    /// The parts typed so far in other styles, shown above the text box.
    private var piecesPreview: some View {
        HStack(alignment: .top, spacing: 4) {
            RichText.text(pieces).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            Button {
                if let last = pieces.popLast() {
                    draft = last.text + draft
                    style = last.style
                }
            } label: {
                Image(systemName: "delete.left").font(.system(size: 11)).foregroundStyle(Retro.ink)
                    .frame(width: 24, height: 20).background(Retro.face).bevel()
            }
            .buttonStyle(.plain)
        }
        .padding(4)
        .background(Retro.field.opacity(0.7))
        .bevel(sunken: true)
        .padding(.horizontal, 6)
    }

    // MARK: Typing and sending

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 5) {
            Menu {
                Button { attach = .photo } label: { Label("Send a Photo", systemImage: "photo") }
                Button { attach = .file } label: { Label("Send a File", systemImage: "doc") }
            } label: {
                Image(systemName: "paperclip").font(.system(size: 15, weight: .semibold)).foregroundStyle(Retro.ink)
                    .frame(width: 30, height: 30).background(Retro.face).bevel()
            }
            .disabled(blocked)
            TextField("", text: $draft, axis: .vertical)
                .lineLimit(1...3)
                .font(style.swiftUIFont)
                .foregroundStyle(Color(hex: style.color))
                .padding(5)
                .background(Retro.field)
                .bevel(sunken: true)
                .onChange(of: draft) { _, new in if !new.isEmpty { store.userIsTyping(to: buddyID) } }
                .onSubmit(send)
            Button(action: send) {
                Text("Send").font(Retro.titleFont(12)).foregroundStyle(Retro.ink)
                    .padding(.horizontal, 8).frame(height: 30).background(Retro.face).bevel()
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .opacity(canSend ? 1 : 0.5)
        }
        .padding(.horizontal, 6)
        .sheet(item: $attach) { kind in
            switch kind {
            case .photo:
                PhotoPicker { data in
                    attach = nil
                    if let data {
                        let stamp = Int(Date().timeIntervalSince1970)
                        sendFileData(data, name: "photo-\(stamp).jpg")
                    }
                }
                .ignoresSafeArea()
            case .file:
                DocumentPicker { url in
                    attach = nil
                    guard let url else { return }
                    guard let data = try? Data(contentsOf: url) else { sendError = "Couldn't read that file."; return }
                    sendFileData(data, name: url.lastPathComponent)
                }
                .ignoresSafeArea()
            }
        }
    }

    private func sendFileData(_ data: Data, name: String) {
        sendError = nil
        guard data.count <= ChatStore.maxFileBytes else {
            sendError = FileTransferError.tooBig.localizedDescription
            return
        }
        Task {
            do { try await store.sendFile(data, name: name, to: buddyID) }
            catch { sendError = error.localizedDescription }
        }
    }

    private func send() {
        guard canSend else { return }
        let current = style
        var all = pieces
        if !draft.isEmpty { all.append(RichSegment(text: draft, style: current)) }
        // Join neighbours that ended up with the same style.
        var merged: [RichSegment] = []
        for seg in all where !seg.text.isEmpty {
            if let last = merged.last, last.style == seg.style { merged[merged.count - 1].text += seg.text } else { merged.append(seg) }
        }
        guard !merged.isEmpty else { return }
        let text = merged.map(\.text).joined()
        let savedDraft = draft, savedPieces = pieces
        draft = ""
        pieces = []
        sendError = nil
        Task {
            do {
                try await store.send(text, to: buddyID, style: merged[0].style, rich: merged.count > 1 ? merged : nil)
            } catch {
                draft = savedDraft
                pieces = savedPieces
                sendError = error is DBError ? "Couldn't send. They may have blocked you." : error.localizedDescription
            }
        }
    }
}

/// The inside of a Get Info window.
struct BuddyInfoPane: View {
    let buddyID: String
    @EnvironmentObject var store: ChatStore
    @Environment(\.closeWindow) private var closeWindow
    @State private var alias = ""
    @State private var pickingSound = false
    @State private var note: String?
    @State private var soundStamp = 0
    @State private var confirmWarn = false

    var body: some View {
        let user = store.users[buddyID]
        let isBuddy = store.allBuddyIDs.contains(buddyID)
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    BuddyIcon(uid: buddyID, size: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.name(buddyID)).font(Retro.titleFont(16)).foregroundStyle(Retro.ink)
                        if store.name(buddyID) != store.realName(buddyID) {
                            Text("(\(store.realName(buddyID)))").font(Retro.body(11)).foregroundStyle(Retro.dark)
                        }
                        presenceLine(user)
                        Text("Warning level: \(store.warningLevel(buddyID))%").font(Retro.body(11)).foregroundStyle(Retro.dark)
                    }
                }

                HStack(spacing: 6) {
                    Button("Send IM") { store.windows.open(.im(buddyID)) }.buttonStyle(RetroButtonStyle(bold: true))
                    Button("Pounce") { store.pounceFor = buddyID; store.windows.open(.pounce) }.buttonStyle(RetroButtonStyle())
                    Button("History") { store.windows.open(.history(buddyID)) }.buttonStyle(RetroButtonStyle())
                }

                if let away = user?.awayMessage {
                    box("Away Message") { LinkedText(text: store.expandAway(away, for: nil)) }
                }
                box("Profile") {
                    if let p = user?.profile, !p.isEmpty { LinkedText(text: p) } else {
                        Text("(no profile)").font(Retro.body(13)).foregroundStyle(Retro.dark)
                    }
                }
                if let u = user, !(u.location.isEmpty && u.interests.isEmpty) {
                    box("Directory") {
                        VStack(alignment: .leading, spacing: 2) {
                            if !u.location.isEmpty { Text("Location: \(u.location)").font(Retro.body(12)).foregroundStyle(Retro.ink) }
                            if !u.interests.isEmpty { Text("Interests: \(u.interests)").font(Retro.body(12)).foregroundStyle(Retro.ink) }
                        }
                    }
                }

                box("Nickname on My Homie List") {
                    HStack {
                        TextField(store.realName(buddyID), text: $alias)
                            .font(Retro.body(13)).foregroundStyle(Retro.ink)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .onSubmit { store.setAlias(alias, for: buddyID) }
                        Button("Save") { store.setAlias(alias, for: buddyID) }.buttonStyle(RetroButtonStyle())
                    }
                }

                box("Sign-On Sound for This Homie") {
                    HStack {
                        Text(Sounds.buddySoundURL(buddyID) != nil ? "Custom sound" : "Default door sound")
                            .font(Retro.body(12)).foregroundStyle(Retro.ink).id(soundStamp)
                        Spacer()
                        Button { Sounds.shared.playSignOn(for: buddyID) } label: { Image(systemName: "play.fill") }
                            .buttonStyle(RetroButtonStyle())
                        Button("Change") { pickingSound = true }.buttonStyle(RetroButtonStyle())
                        if Sounds.buddySoundURL(buddyID) != nil {
                            Button("Reset") { Sounds.resetBuddySound(buddyID); soundStamp += 1 }.buttonStyle(RetroButtonStyle())
                        }
                    }
                }
                if let note { Text(note).font(Retro.body(11)).foregroundStyle(.red) }

                HStack(spacing: 6) {
                    Button("Warn") { confirmWarn = true }
                        .buttonStyle(RetroButtonStyle())
                        .disabled(store.alreadyWarned(buddyID))
                    Button(store.blocked.contains(buddyID) ? "Unblock" : "Block") {
                        Task { await store.setBlocked(buddyID, !store.blocked.contains(buddyID)) }
                    }
                    .buttonStyle(RetroButtonStyle())
                    if !isBuddy {
                        Button("Add Homie") {
                            if let g = store.groups.first?.id { Task { await store.addBuddy(buddyID, toGroup: g) } }
                        }
                        .buttonStyle(RetroButtonStyle())
                    }
                    Spacer()
                    Button("Close") { closeWindow() }.buttonStyle(RetroButtonStyle(bold: true))
                }
            }
            .padding(12)
        }
        .onAppear { alias = store.prefs.aliases[buddyID] ?? "" }
        .sheet(isPresented: $pickingSound) {
            DocumentPicker(types: [.audio]) { url in
                pickingSound = false
                guard let url else { return }
                do {
                    try Sounds.setBuddySound(buddyID, from: url)
                    soundStamp += 1
                    Sounds.shared.playSignOn(for: buddyID)
                } catch {
                    note = "Couldn't use that sound: \(error.localizedDescription)"
                }
            }
            .ignoresSafeArea()
        }
        .confirmationDialog("Warn \(store.name(buddyID))?", isPresented: $confirmWarn, titleVisibility: .visible) {
            Button("Warn", role: .destructive) { Task { try? await store.warn(buddyID) } }
        }
    }

    @ViewBuilder
    private func presenceLine(_ user: UserInfo?) -> some View {
        switch user?.presence(now: store.now) ?? .offline {
        case .online: Text("Online").font(Retro.body(12)).foregroundStyle(.green)
        case .away: Text("Away").font(Retro.body(12)).foregroundStyle(.orange)
        case .idle: Text("Idle for \(user?.idleMinutes(now: store.now) ?? 0) minutes").font(Retro.body(12)).foregroundStyle(.gray)
        case .offline:
            if let u = user, u.lastSeen > 0 {
                Text("Offline, last seen \(Date(timeIntervalSince1970: u.lastSeen / 1000).formatted(.relative(presentation: .named)))")
                    .font(Retro.body(11)).foregroundStyle(.gray)
            } else {
                Text("Offline").font(Retro.body(12)).foregroundStyle(.gray)
            }
        }
    }

    private func box<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(Retro.titleFont(11)).foregroundStyle(Retro.ink)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8).background(Retro.field).bevel(sunken: true)
        }
    }
}
