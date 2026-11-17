import SwiftUI
import UIKit

/// The whole app's live state: who you are, your buddies, and your conversations.
@MainActor
final class ChatStore: ObservableObject {
    enum Phase { case signedOut, signingOn, signedOn }

    @Published var phase: Phase = .signedOut
    @Published var myUID = ""
    @Published var myScreenName = ""
    @Published var users: [String: UserInfo] = [:]
    @Published var groups: [BuddyGroup] = []
    @Published var inbox: [String: InboxEntry] = [:]
    @Published var blocked: Set<String> = []
    @Published var messages: [String: [ChatMessage]] = [:]
    @Published var typing: [String: Set<String>] = [:]
    @Published var awayMessage: String? = nil
    @Published var openConversation: String? = nil
    @Published var banner: String? = nil
    @Published var flash: [String: Date] = [:]   // buddy uid → time they signed on/off (for the door icon)
    @Published var now = Date()

    let db = Database()
    private var session: AuthSession?
    private var streams: [String: LiveQuery] = [:]
    private var heartbeat: Timer?
    private var clock: Timer?
    private var knownPresence: [String: Presence] = [:]
    private var usersLoaded = false
    private var inboxLoaded = false
    private var lastAutoReply: [String: Date] = [:]
    private var typingSentAt: Date = .distantPast

    @AppStorage("savedAwayMessages") private var savedAwayData: Data = Data()
    @AppStorage("lastScreenName") var lastScreenName = ""
    @AppStorage("autoSignOn") var autoSignOn = false

    init() {
        db.tokenProvider = { [weak self] in await self?.validToken() }
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.wentToBackground() }
        }
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.cameToForeground() }
        }
    }

    // MARK: Signing on and off

    func validToken() async -> String? {
        guard var s = session else { return nil }
        if s.expiresAt < Date() {
            if let fresh = try? await AuthService.refresh(s) {
                s = fresh
                session = fresh
                saveSession()
            }
        }
        return s.idToken
    }

    private func saveSession() {
        Keychain.set(session.flatMap { try? JSONEncoder().encode($0) }, for: "session")
    }

    func tryAutoSignOn() async {
        guard autoSignOn, phase == .signedOut,
              let data = Keychain.get("session"),
              let s = try? JSONDecoder().decode(AuthSession.self, from: data) else { return }
        phase = .signingOn
        session = s
        do { try await finishSignOn(uid: s.uid) } catch { phase = .signedOut }
    }

    func signUp(screenName: String, password: String) async throws {
        let name = screenName.trimmingCharacters(in: .whitespaces)
        guard AuthService.isValidScreenName(name) else {
            throw AuthError.message("Screen names are 3–16 letters or numbers (spaces are OK).")
        }
        let key = AuthService.normalize(name)
        phase = .signingOn
        do {
            session = nil
            if (try? await db.get("screennames/\(key)")) != nil {
                throw AuthError.message("That screen name is already taken.")
            }
            let s = try await AuthService.signUp(screenName: name, password: password)
            session = s
            myUID = s.uid
            do {
                try await db.put("screennames/\(key)", s.uid)
            } catch {
                await AuthService.deleteAccount(s)
                session = nil
                throw AuthError.message("That screen name is already taken.")
            }
            try await db.put("users/\(s.uid)", [
                "screenName": name, "profile": "", "away": "",
                "signedOn": true, "lastSeen": Database.serverTimestamp,
            ] as [String: Any])
            let starter = [BuddyGroup(name: "Buddies", members: []), BuddyGroup(name: "Family", members: []),
                           BuddyGroup(name: "Co-Workers", members: [])]
            groups = starter
            try? await saveGroups()   // not worth failing sign-up over
            saveSession()
            lastScreenName = name
            try await finishSignOn(uid: s.uid)
        } catch {
            phase = .signedOut
            throw error
        }
    }

    func signIn(screenName: String, password: String) async throws {
        phase = .signingOn
        do {
            let s = try await AuthService.signIn(screenName: screenName, password: password)
            session = s
            saveSession()
            lastScreenName = screenName
            try await finishSignOn(uid: s.uid)
        } catch {
            phase = .signedOut
            throw error
        }
    }

    private func finishSignOn(uid: String) async throws {
        myUID = uid
        usersLoaded = false
        inboxLoaded = false
        knownPresence = [:]
        let me = try await db.get("users/\(uid)") as? [String: Any] ?? [:]
        myScreenName = me["screenName"] as? String ?? lastScreenName
        let away = me["away"] as? String ?? ""
        awayMessage = away.isEmpty ? nil : away
        if let raw = try? await db.get("buddylists/\(uid)") as? String,
           let data = raw.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([BuddyGroup].self, from: data) {
            groups = decoded
        } else if groups.isEmpty {
            groups = [BuddyGroup(name: "Buddies", members: [])]
        }
        try await db.patch("users/\(uid)", ["signedOn": true, "lastSeen": Database.serverTimestamp, "idleSince": NSNull()])
        startStreams()
        startTimers()
        phase = .signedOn
        Sounds.shared.play(.signOn)
    }

    func signOff() async {
        if !myUID.isEmpty {
            try? await db.patch("users/\(myUID)", ["signedOn": false, "lastSeen": Database.serverTimestamp])
        }
        Sounds.shared.play(.signOff)
        streams.values.forEach { $0.stop() }
        streams = [:]
        heartbeat?.invalidate()
        clock?.invalidate()
        if !autoSignOn {
            session = nil
            saveSession()
        }
        users = [:]; inbox = [:]; messages = [:]; typing = [:]; groups = []
        openConversation = nil
        myUID = ""
        phase = .signedOut
    }

    // MARK: Live data

    private func startStreams() {
        streams["users"] = db.listen("users") { [weak self] value in self?.handleUsers(value) }
        streams["inbox"] = db.listen("inbox/\(myUID)") { [weak self] value in self?.handleInbox(value) }
        streams["blocks"] = db.listen("blocks/\(myUID)") { [weak self] value in
            self?.blocked = Set((value as? [String: Any])?.keys.map { $0 } ?? [])
        }
    }

    private func startTimers() {
        heartbeat?.invalidate()
        heartbeat = Timer.scheduledTimer(withTimeInterval: 45, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.beat() }
        }
        clock?.invalidate()
        clock = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func beat() {
        guard phase == .signedOn else { return }
        Task { try? await db.patch("users/\(myUID)", ["lastSeen": Database.serverTimestamp, "signedOn": true]) }
    }

    private func tick() {
        now = Date()
        detectPresenceChanges()
        flash = flash.filter { now.timeIntervalSince($0.value) < 8 }
    }

    private func wentToBackground() {
        guard phase == .signedOn else { return }
        Task { try? await db.patch("users/\(myUID)", ["idleSince": Database.serverTimestamp, "lastSeen": Database.serverTimestamp]) }
    }

    private func cameToForeground() {
        guard phase == .signedOn else { return }
        Task { try? await db.patch("users/\(myUID)", ["idleSince": NSNull(), "lastSeen": Database.serverTimestamp, "signedOn": true]) }
        streams.values.forEach { $0.start() }
    }

    private func handleUsers(_ value: Any?) {
        var result: [String: UserInfo] = [:]
        for (uid, v) in (value as? [String: Any]) ?? [:] {
            if let d = v as? [String: Any] { result[uid] = UserInfo(uid: uid, dict: d) }
        }
        users = result
        detectPresenceChanges()
        usersLoaded = true
    }

    private var allBuddyIDs: Set<String> { Set(groups.flatMap(\.members)) }

    private func detectPresenceChanges() {
        let buddies = allBuddyIDs
        for uid in buddies {
            guard let u = users[uid] else { continue }
            let p = u.presence(now: now)
            let before = knownPresence[uid]
            knownPresence[uid] = p
            guard usersLoaded, let before else { continue }
            if before == .offline && p != .offline {
                flash[uid] = now
                Sounds.shared.play(.signOn)
            } else if before != .offline && p == .offline {
                flash[uid] = now
                Sounds.shared.play(.signOff)
            }
        }
    }

    private func handleInbox(_ value: Any?) {
        var result: [String: InboxEntry] = [:]
        for (conv, v) in (value as? [String: Any]) ?? [:] {
            guard let d = v as? [String: Any] else { continue }
            result[conv] = InboxEntry(id: conv, with: d["with"] as? String ?? "", from: d["from"] as? String ?? "",
                                      ts: (d["ts"] as? NSNumber)?.doubleValue ?? 0, preview: d["preview"] as? String ?? "")
        }
        let old = inbox
        inbox = result
        defer { inboxLoaded = true }
        guard inboxLoaded else { return }
        for (conv, entry) in result where entry.from != myUID && entry.ts > (old[conv]?.ts ?? 0) {
            if blocked.contains(entry.from) { continue }
            Sounds.shared.play(.receive)
            if openConversation != conv {
                banner = "\(users[entry.from]?.screenName ?? "Someone"): \(entry.preview)"
            }
            sendAutoReplyIfAway(to: entry.from, conv: conv)
        }
    }

    // MARK: Unread

    func lastRead(_ conv: String) -> Double { UserDefaults.standard.double(forKey: "read.\(conv)") }

    func markRead(_ conv: String) {
        UserDefaults.standard.set(inbox[conv]?.ts ?? Date().timeIntervalSince1970 * 1000, forKey: "read.\(conv)")
        objectWillChange.send()
    }

    func isUnread(_ conv: String) -> Bool {
        guard let e = inbox[conv], e.from != myUID else { return false }
        return e.ts > lastRead(conv)
    }

    func unreadFrom(_ uid: String) -> Bool { isUnread(conversationID(myUID, uid)) }

    // MARK: Conversations

    func open(with uid: String) {
        let conv = conversationID(myUID, uid)
        openConversation = conv
        if streams["m.\(conv)"] == nil {
            streams["m.\(conv)"] = db.listen("messages/\(conv)", query: ["orderBy": "\"$key\"", "limitToLast": "150"]) { [weak self] value in
                guard let self else { return }
                let list = ((value as? [String: Any]) ?? [:]).compactMap { k, v -> ChatMessage? in
                    guard let d = v as? [String: Any] else { return nil }
                    return ChatMessage(id: k, dict: d)
                }.sorted { $0.id < $1.id }
                self.messages[conv] = list
                if self.openConversation == conv { self.markRead(conv) }
            }
            streams["t.\(conv)"] = db.listen("typing/\(conv)") { [weak self] value in
                guard let self else { return }
                let nowMs = Date().timeIntervalSince1970 * 1000
                let active = ((value as? [String: Any]) ?? [:]).compactMap { k, v -> String? in
                    guard k != self.myUID, let t = (v as? NSNumber)?.doubleValue, nowMs - t < 8000 else { return nil }
                    return k
                }
                self.typing[conv] = Set(active)
            }
        }
        markRead(conv)
    }

    func close(_ conv: String) {
        if openConversation == conv { openConversation = nil }
        streams["t.\(conv)"]?.stop()
        streams["t.\(conv)"] = nil
        streams["m.\(conv)"]?.stop()
        streams["m.\(conv)"] = nil
    }

    func send(_ text: String, to uid: String, style: TextStyle, auto: Bool = false) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let conv = conversationID(myUID, uid)
        var msg: [String: Any] = ["from": myUID, "name": myScreenName, "text": trimmed,
                                  "ts": Database.serverTimestamp, "style": style.dict]
        if auto { msg["auto"] = true }
        try await db.push("messages/\(conv)", msg)
        let preview = String(trimmed.prefix(80))
        try? await db.put("inbox/\(uid)/\(conv)", ["with": myUID, "from": myUID, "ts": Database.serverTimestamp, "preview": preview] as [String: Any])
        try? await db.put("inbox/\(myUID)/\(conv)", ["with": uid, "from": myUID, "ts": Database.serverTimestamp, "preview": preview] as [String: Any])
        try? await db.delete("typing/\(conv)/\(myUID)")
        if !auto { Sounds.shared.play(.send) }
    }

    func userIsTyping(to uid: String) {
        guard Date().timeIntervalSince(typingSentAt) > 3 else { return }
        typingSentAt = Date()
        let conv = conversationID(myUID, uid)
        Task { try? await db.put("typing/\(conv)/\(myUID)", Database.serverTimestamp) }
    }

    private func sendAutoReplyIfAway(to uid: String, conv: String) {
        guard let away = awayMessage else { return }
        if let last = lastAutoReply[conv], Date().timeIntervalSince(last) < 300 { return }
        lastAutoReply[conv] = Date()
        let text = expandAway(away, for: uid)
        Task { try? await send(text, to: uid, style: TextStyle(), auto: true) }
    }

    /// %n becomes the other person's screen name, %d the date, %t the time.
    func expandAway(_ text: String, for uid: String?) -> String {
        let f = DateFormatter()
        f.dateStyle = .short
        var t = text.replacingOccurrences(of: "%n", with: uid.flatMap { users[$0]?.screenName } ?? "you")
        t = t.replacingOccurrences(of: "%d", with: f.string(from: Date()))
        f.dateStyle = .none
        f.timeStyle = .short
        return t.replacingOccurrences(of: "%t", with: f.string(from: Date()))
    }

    // MARK: Away and profile

    var savedAwayMessages: [String] {
        get {
            let list = (try? JSONDecoder().decode([String].self, from: savedAwayData)) ?? []
            return list.isEmpty ? ["I am away from my phone right now.", "brb", "Out with friends. Leave a message! %t"] : list
        }
        set { savedAwayData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    func setAway(_ message: String?) async {
        awayMessage = message
        try? await db.patch("users/\(myUID)", ["away": message ?? ""])
    }

    func setProfile(_ text: String) async {
        try? await db.patch("users/\(myUID)", ["profile": text])
    }

    // MARK: Buddy list

    func saveGroups() async throws {
        let data = try JSONEncoder().encode(groups)
        try await db.put("buddylists/\(myUID)", String(data: data, encoding: .utf8) ?? "[]")
    }

    func lookUp(screenName: String) async -> String? {
        let key = AuthService.normalize(screenName)
        guard !key.isEmpty else { return nil }
        return try? await db.get("screennames/\(key)") as? String
    }

    func addBuddy(_ uid: String, toGroup groupID: UUID) async {
        guard uid != myUID else { return }
        for i in groups.indices { groups[i].members.removeAll { $0 == uid } }
        if let i = groups.firstIndex(where: { $0.id == groupID }) { groups[i].members.append(uid) }
        try? await saveGroups()
    }

    func removeBuddy(_ uid: String) async {
        for i in groups.indices { groups[i].members.removeAll { $0 == uid } }
        try? await saveGroups()
    }

    func addGroup(_ name: String) async {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        groups.append(BuddyGroup(name: n, members: []))
        try? await saveGroups()
    }

    func deleteGroup(_ id: UUID) async {
        guard groups.count > 1, let i = groups.firstIndex(where: { $0.id == id }) else { return }
        let orphans = groups[i].members
        groups.remove(at: i)
        groups[0].members.append(contentsOf: orphans)
        try? await saveGroups()
    }

    func toggleCollapsed(_ id: UUID) {
        guard let i = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[i].collapsed.toggle()
        Task { try? await saveGroups() }
    }

    func setBlocked(_ uid: String, _ block: Bool) async {
        if block { try? await db.put("blocks/\(myUID)/\(uid)", true) } else { try? await db.delete("blocks/\(myUID)/\(uid)") }
    }

    func name(_ uid: String) -> String { users[uid]?.screenName ?? "…" }

    /// People who messaged you but aren't on your Buddy List.
    var strangers: [String] {
        let buddies = allBuddyIDs
        return inbox.values.filter { !buddies.contains($0.with) && $0.with != myUID }.sorted { $0.ts > $1.ts }.map(\.with)
    }
}
