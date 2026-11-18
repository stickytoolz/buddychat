import SwiftUI

struct IMView: View {
    let buddyID: String
    @EnvironmentObject var store: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var showInfo = false
    @State private var sendError: String?
    @State private var attach: AttachPicker?
    @AppStorage("myStyle") private var styleData: Data = Data()

    private var conv: String { conversationID(store.myUID, buddyID) }
    private var style: TextStyle {
        get { (try? JSONDecoder().decode(TextStyle.self, from: styleData)) ?? TextStyle() }
        nonmutating set { styleData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var body: some View {
        let user = store.users[buddyID]
        let presence = user?.presence(now: store.now) ?? .offline
        VStack(spacing: 0) {
            RetroWindow(title: "\(store.name(buddyID)) - Instant Message", icon: "bubble.left.and.bubble.right.fill",
                        trailing: {
                            Button { dismiss() } label: {
                                Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                                    .frame(width: 20, height: 18)
                                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(.white.opacity(0.7)))
                            }
                        }) {
                VStack(spacing: 6) {
                    statusBar(user: user, presence: presence)
                    transcript
                    if store.typing[conv]?.isEmpty == false {
                        Text("\(store.name(buddyID)) is typing…").font(Retro.body(11)).italic()
                            .foregroundStyle(Retro.dark).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8)
                    }
                    if store.blocked.contains(buddyID) {
                        Text("You've blocked this person. Unblock from Get Info to talk.").font(Retro.body(11)).foregroundStyle(.red)
                    }
                    if let sendError { Text(sendError).font(Retro.body(11)).foregroundStyle(.red) }
                    formatBar
                    composer
                }
                .padding(.bottom, 8)
            }
        }
        .padding(10)
        .background(Color(red: 0.0, green: 0.5, blue: 0.5).ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { store.open(with: buddyID) }
        .onDisappear { store.close(conv) }
        .sheet(isPresented: $showInfo) { BuddyInfoView(buddyID: buddyID) }
    }

    private func statusBar(user: UserInfo?, presence: Presence) -> some View {
        HStack {
            switch presence {
            case .online: Text("Online").foregroundStyle(.green)
            case .away: Text("Away").foregroundStyle(.orange)
            case .idle: Text("Idle \(user?.idleMinutes(now: store.now) ?? 0) min").foregroundStyle(.gray)
            case .offline: Text("Offline — they'll get your message when they sign on").foregroundStyle(.gray)
            }
            Spacer()
            Button("Get Info") { showInfo = true }.buttonStyle(RetroButtonStyle())
        }
        .font(Retro.body(11))
        .padding(.horizontal, 8).padding(.top, 8)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(store.messages[conv] ?? []) { m in
                        messageRow(m).id(m.id)
                    }
                }
                .padding(8)
            }
            .background(Retro.field)
            .bevel(sunken: true)
            .padding(.horizontal, 8)
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
        let name = mine ? store.myScreenName : (m.fromName ?? store.name(m.from))
        let time = m.date.formatted(date: .omitted, time: .standard)
        return VStack(alignment: .leading, spacing: 1) {
            (Text(m.isAuto ? "Auto response from \(name)" : name).font(Retro.titleFont(13))
                .foregroundColor(mine ? Retro.me : Retro.them)
             + Text(" (\(time)):").font(Retro.body(10)).foregroundColor(Retro.shadow))
            if let offer = m.file {
                FileCard(offer: offer, message: m, buddyID: buddyID)
            } else {
                Text(m.text)
                    .font(m.style.swiftUIFont)
                    .underline(m.style.underline)
                    .foregroundStyle(Color(hex: m.style.color))
                    .textSelection(.enabled)
            }
        }
    }

    private var formatBar: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(TextStyle.fonts, id: \.self) { f in
                    Button { var s = style; s.font = f; style = s } label: { Text(f) }
                }
            } label: {
                Text(style.font).font(.custom(style.font, size: 12)).lineLimit(1)
                    .foregroundStyle(Retro.ink).padding(.horizontal, 6).padding(.vertical, 4)
                    .background(Retro.field).bevel(sunken: true)
            }
            fmt("A-") { var s = style; s.size = max(11, s.size - 2); style = s }
            fmt("A+") { var s = style; s.size = min(28, s.size + 2); style = s }
            fmt("B", on: style.bold) { var s = style; s.bold.toggle(); style = s }
            fmt("I", on: style.italic) { var s = style; s.italic.toggle(); style = s }
            fmt("U", on: style.underline) { var s = style; s.underline.toggle(); style = s }
            Menu {
                ForEach(TextStyle.colors, id: \.self) { c in
                    Button { var s = style; s.color = c; style = s } label: {
                        Label(c, systemImage: "circle.fill")
                    }
                }
            } label: {
                Circle().fill(Color(hex: style.color)).frame(width: 18, height: 18).overlay(Circle().stroke(Retro.dark))
            }
            Spacer()
        }
        .padding(.horizontal, 8)
    }

    private func fmt(_ label: String, on: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(label == "B" ? Retro.titleFont(12) : label == "I" ? Retro.body(12).italic() : Retro.body(12))
                .underline(label == "U")
                .foregroundStyle(Retro.ink)
                .frame(width: 26, height: 22)
                .background(on ? Retro.shadow.opacity(0.4) : Retro.face)
                .bevel(sunken: on)
        }
        .buttonStyle(.plain)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Menu {
                Button { attach = .photo } label: { Label("Send a Photo", systemImage: "photo") }
                Button { attach = .file } label: { Label("Send a File", systemImage: "doc") }
            } label: {
                Image(systemName: "paperclip").font(.system(size: 17, weight: .semibold)).foregroundStyle(Retro.ink)
                    .frame(width: 34, height: 32).background(Retro.face).bevel()
            }
            .disabled(store.blocked.contains(buddyID))
            TextField("", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .font(style.swiftUIFont)
                .foregroundStyle(Color(hex: style.color))
                .padding(6)
                .background(Retro.field)
                .bevel(sunken: true)
                .onChange(of: draft) { _, new in if !new.isEmpty { store.userIsTyping(to: buddyID) } }
                .onSubmit(send)
            Button("Send", action: send)
                .buttonStyle(RetroButtonStyle(bold: true))
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.blocked.contains(buddyID))
        }
        .padding(.horizontal, 8)
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
        let text = draft
        draft = ""
        sendError = nil
        Task {
            do { try await store.send(text, to: buddyID, style: style) }
            catch {
                draft = text
                sendError = error is DBError ? "Couldn't send — they may have blocked you." : error.localizedDescription
            }
        }
    }
}

struct BuddyInfoView: View {
    let buddyID: String
    @EnvironmentObject var store: ChatStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let user = store.users[buddyID]
        ZStack {
            Color(red: 0.0, green: 0.5, blue: 0.5).ignoresSafeArea()
            RetroWindow(title: "Buddy Info: \(store.name(buddyID))", icon: "info.circle.fill") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(store.name(buddyID)).font(Retro.titleFont(20)).foregroundStyle(Retro.ink)
                        switch user?.presence(now: store.now) ?? .offline {
                        case .online: Text("Online").foregroundStyle(.green)
                        case .away: Text("Away").foregroundStyle(.orange)
                        case .idle: Text("Idle for \(user?.idleMinutes(now: store.now) ?? 0) minutes").foregroundStyle(.gray)
                        case .offline:
                            if let u = user, u.lastSeen > 0 {
                                Text("Offline — last seen \(Date(timeIntervalSince1970: u.lastSeen / 1000).formatted(.relative(presentation: .named)))")
                                    .foregroundStyle(.gray)
                            } else {
                                Text("Offline").foregroundStyle(.gray)
                            }
                        }
                        if let away = user?.awayMessage {
                            box(title: "Away Message", text: store.expandAway(away, for: nil))
                        }
                        box(title: "Profile", text: (user?.profile.isEmpty ?? true) ? "(no profile)" : user!.profile)
                        HStack {
                            Button(store.blocked.contains(buddyID) ? "Unblock" : "Block") {
                                Task { await store.setBlocked(buddyID, !store.blocked.contains(buddyID)) }
                            }
                            .buttonStyle(RetroButtonStyle())
                            Spacer()
                            Button("Close") { dismiss() }.buttonStyle(RetroButtonStyle(bold: true))
                        }
                    }
                    .font(Retro.body(13))
                    .padding(20)
                }
            }
            .padding(16)
        }
    }

    private func box(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(Retro.titleFont(12)).foregroundStyle(Retro.ink)
            Text(text).font(Retro.body(13)).foregroundStyle(Retro.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8).background(Retro.field).bevel(sunken: true)
        }
    }
}
