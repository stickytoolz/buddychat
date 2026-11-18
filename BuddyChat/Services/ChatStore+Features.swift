import SwiftUI
import UIKit

struct ChatInvite: Identifiable, Equatable {
    let id: String
    let from: String
    let room: String
    let message: String
}

extension ChatStore {

    // MARK: Streams for icons, warnings, invites

    func startFeatureStreams() {
        listenFeature("icons", path: "icons") { [weak self] value in self?.handleIcons(value) }
        listenFeature("warnings", path: "warnings") { [weak self] value in
            var out: [String: [String: Double]] = [:]
            for (target, v) in (value as? [String: Any]) ?? [:] {
                out[target] = ((v as? [String: Any]) ?? [:]).compactMapValues { ($0 as? NSNumber)?.doubleValue }
            }
            self?.warnings = out
        }
        listenFeature("invites", path: "invites/\(myUID)") { [weak self] value in
            guard let self else { return }
            let old = Set(self.invites.map(\.id))
            self.invites = ((value as? [String: Any]) ?? [:]).compactMap { k, v in
                guard let d = v as? [String: Any], let from = d["from"] as? String, let room = d["room"] as? String else { return nil }
                return ChatInvite(id: k, from: from, room: room, message: d["message"] as? String ?? "")
            }
            .filter { !self.blocked.contains($0.from) }
            if self.invites.contains(where: { !old.contains($0.id) }) {
                Sounds.shared.play(.receive)
                self.windows.open(.invites)
            }
        }
    }

    private func listenFeature(_ key: String, path: String, onChange: @escaping @MainActor (Any?) -> Void) {
        let q = db.listen(path, onChange: onChange)
        registerStream(key, q)
    }

    private func handleIcons(_ value: Any?) {
        var next = icons
        let raw = (value as? [String: Any]) ?? [:]
        for (uid, v) in raw {
            guard let b64 = v as? String else { continue }
            if iconCache[uid] == b64 { continue }
            iconCache[uid] = b64
            if let data = Data(base64Encoded: b64), let img = UIImage(data: data) { next[uid] = img }
        }
        for uid in next.keys where raw[uid] == nil { next[uid] = nil; iconCache[uid] = nil }
        icons = next
    }

    // MARK: Buddy icon

    func setMyIcon(_ image: UIImage?) async {
        guard let image else {
            try? await db.delete("icons/\(myUID)")
            return
        }
        let side = min(image.size.width, image.size.height)
        let crop = CGRect(x: (image.size.width - side) / 2, y: (image.size.height - side) / 2, width: side, height: side)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let small = UIGraphicsImageRenderer(size: CGSize(width: 96, height: 96), format: format).image { _ in
            image.draw(in: CGRect(x: -crop.minX * 96 / side, y: -crop.minY * 96 / side,
                                  width: image.size.width * 96 / side, height: image.size.height * 96 / side))
        }
        guard let jpeg = small.jpegData(compressionQuality: 0.7) else { return }
        try? await db.put("icons/\(myUID)", jpeg.base64EncodedString())
    }

    // MARK: Account preferences (aliases, pounces, privacy)

    func loadPrefs() async {
        if let raw = try? await db.get("prefs/\(myUID)") as? String,
           let data = raw.data(using: .utf8),
           let p = try? JSONDecoder().decode(AccountPrefs.self, from: data) {
            prefs = p
        } else {
            prefs = AccountPrefs()
        }
    }

    func savePrefs() {
        let snapshot = prefs
        Task {
            guard let data = try? JSONEncoder().encode(snapshot), let s = String(data: data, encoding: .utf8) else { return }
            try? await db.put("prefs/\(myUID)", s)
        }
    }

    func setAlias(_ alias: String, for uid: String) {
        let a = alias.trimmingCharacters(in: .whitespaces)
        prefs.aliases[uid] = a.isEmpty ? nil : a
        savePrefs()
    }

    // MARK: Invisible

    func setInvisible(_ on: Bool) async {
        invisible = on
        try? await db.patch("users/\(myUID)", ["invisible": on])
    }

    // MARK: Warnings

    /// Each warning from a different person in the last 24 hours adds 10%.
    func warningLevel(_ uid: String) -> Int {
        let dayAgo = (Date().timeIntervalSince1970 - 86_400) * 1000
        let count = (warnings[uid] ?? [:]).values.filter { $0 > dayAgo }.count
        return min(100, count * 10)
    }

    func warn(_ uid: String) async throws {
        guard uid != myUID else { return }
        try await db.put("warnings/\(uid)/\(myUID)", Database.serverTimestamp)
    }

    func alreadyWarned(_ uid: String) -> Bool {
        let dayAgo = (Date().timeIntervalSince1970 - 86_400) * 1000
        return (warnings[uid]?[myUID] ?? 0) > dayAgo
    }

    // MARK: Chat invites

    func invite(_ uid: String, to room: String, message: String) async {
        try? await db.push("invites/\(uid)", [
            "from": myUID, "room": room, "message": message, "ts": Database.serverTimestamp,
        ] as [String: Any])
    }

    func dismissInvite(_ invite: ChatInvite) async {
        invites.removeAll { $0.id == invite.id }
        try? await db.delete("invites/\(myUID)/\(invite.id)")
    }

    // MARK: Buddy Pounce

    func presenceChanged(_ uid: String, from before: Presence, to after: Presence) {
        var fired: [UUID] = []
        for pounce in prefs.pounces where pounce.buddy == uid {
            let hit = (pounce.triggers.contains(.signsOn) && before == .offline && after != .offline)
                || (pounce.triggers.contains(.returnsFromAway) && before == .away && (after == .online || after == .idle))
                || (pounce.triggers.contains(.returnsFromIdle) && before == .idle && after == .online)
            guard hit else { continue }
            fired.append(pounce.id)
            if pounce.playSound { Sounds.shared.play(.receive) }
            if pounce.openIM { windows.open(.im(uid)) }
            let msg = pounce.sendMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            if !msg.isEmpty { Task { try? await send(msg, to: uid, style: TextStyle()) } }
            banner = "Homie Pounce: \(name(uid)) \(after == .offline ? "signed off" : "is here")!"
        }
        let oneShots = prefs.pounces.filter { fired.contains($0.id) && !$0.keep }.map(\.id)
        if !oneShots.isEmpty {
            prefs.pounces.removeAll { oneShots.contains($0.id) }
            savePrefs()
        }
    }

    // MARK: History & directory

    func history(with uid: String) async -> [ChatMessage] {
        let conv = conversationID(myUID, uid)
        let value = try? await db.get("messages/\(conv)", query: ["orderBy": "\"$key\"", "limitToLast": "1000"])
        return ((value as? [String: Any]) ?? [:]).compactMap { k, v in
            (v as? [String: Any]).map { ChatMessage(id: k, dict: $0) }
        }
        .sorted { $0.id < $1.id }
    }

    func directorySearch(_ query: String) -> [UserInfo] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        return users.values
            .filter { $0.id != myUID }
            .filter { u in
                q.isEmpty || u.screenName.lowercased().contains(q) || u.interests.lowercased().contains(q)
                    || u.location.lowercased().contains(q) || u.profile.lowercased().contains(q)
            }
            .sorted { $0.screenName.localizedCaseInsensitiveCompare($1.screenName) == .orderedAscending }
    }

    func setDirectoryInfo(interests: String, location: String) async {
        try? await db.patch("users/\(myUID)", ["interests": interests, "location": location])
    }
}
