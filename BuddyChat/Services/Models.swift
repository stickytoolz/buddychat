import SwiftUI

enum Presence: Int, Comparable {
    case offline = 0, idle = 1, away = 2, online = 3
    static func < (a: Presence, b: Presence) -> Bool { a.rawValue < b.rawValue }
}

struct UserInfo: Identifiable, Equatable {
    let id: String          // uid
    var screenName: String
    var profile: String
    var awayMessage: String?
    var lastSeen: Double    // ms since 1970
    var idleSince: Double?
    var signedOn: Bool

    init(uid: String, dict: [String: Any]) {
        id = uid
        screenName = dict["screenName"] as? String ?? "Unknown"
        profile = dict["profile"] as? String ?? ""
        let away = dict["away"] as? String
        awayMessage = (away?.isEmpty ?? true) ? nil : away
        lastSeen = (dict["lastSeen"] as? NSNumber)?.doubleValue ?? 0
        idleSince = (dict["idleSince"] as? NSNumber)?.doubleValue
        signedOn = dict["signedOn"] as? Bool ?? false
    }

    func presence(now: Date = Date()) -> Presence {
        guard signedOn else { return .offline }
        let age = now.timeIntervalSince1970 * 1000 - lastSeen
        if idleSince == nil && age < 150_000 { return awayMessage != nil ? .away : .online }
        if idleSince != nil && age < 2 * 3600_000 { return awayMessage != nil ? .away : .idle }
        return .offline
    }

    func idleMinutes(now: Date = Date()) -> Int? {
        guard let idleSince else { return nil }
        return max(1, Int((now.timeIntervalSince1970 * 1000 - idleSince) / 60_000))
    }
}

struct TextStyle: Equatable, Codable {
    var font: String = "Verdana"
    var size: Double = 15
    var color: String = "#000000"
    var bold = false
    var italic = false
    var underline = false

    static let fonts = ["Verdana", "Arial", "Times New Roman", "Courier New", "Georgia", "Trebuchet MS", "Marker Felt", "Chalkboard SE"]
    static let colors = ["#000000", "#C00000", "#0040C0", "#008000", "#800080", "#FF6600", "#FF00CC", "#008080"]

    var dict: [String: Any] {
        ["font": font, "size": size, "color": color, "bold": bold, "italic": italic, "underline": underline]
    }

    init() {}
    init(dict: [String: Any]?) {
        guard let d = dict else { return }
        font = d["font"] as? String ?? font
        size = (d["size"] as? NSNumber)?.doubleValue ?? size
        color = d["color"] as? String ?? color
        bold = d["bold"] as? Bool ?? false
        italic = d["italic"] as? Bool ?? false
        underline = d["underline"] as? Bool ?? false
    }

    var swiftUIFont: Font {
        var f = Font.custom(font, size: size)
        if bold { f = f.bold() }
        if italic { f = f.italic() }
        return f
    }
}

struct ChatMessage: Identifiable, Equatable {
    let id: String
    let from: String
    let text: String
    let ts: Double
    let style: TextStyle
    let isAuto: Bool
    let fromName: String?

    init(id: String, dict: [String: Any]) {
        self.id = id
        from = dict["from"] as? String ?? ""
        text = dict["text"] as? String ?? ""
        ts = (dict["ts"] as? NSNumber)?.doubleValue ?? 0
        style = TextStyle(dict: dict["style"] as? [String: Any])
        isAuto = dict["auto"] as? Bool ?? false
        fromName = dict["name"] as? String
    }

    var date: Date { Date(timeIntervalSince1970: ts / 1000) }
}

struct InboxEntry: Identifiable, Equatable {
    let id: String      // conversation id
    let with: String    // the other person
    let from: String    // who sent the last message
    let ts: Double
    let preview: String
}

struct BuddyGroup: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var members: [String]   // uids
    var collapsed = false
}

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

func conversationID(_ a: String, _ b: String) -> String {
    [a, b].sorted().joined(separator: "_")
}
