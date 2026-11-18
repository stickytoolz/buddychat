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
    var invisible: Bool
    var interests: String
    var location: String

    init(uid: String, dict: [String: Any]) {
        id = uid
        screenName = dict["screenName"] as? String ?? "Unknown"
        profile = dict["profile"] as? String ?? ""
        let away = dict["away"] as? String
        awayMessage = (away?.isEmpty ?? true) ? nil : away
        lastSeen = (dict["lastSeen"] as? NSNumber)?.doubleValue ?? 0
        idleSince = (dict["idleSince"] as? NSNumber)?.doubleValue
        signedOn = dict["signedOn"] as? Bool ?? false
        invisible = dict["invisible"] as? Bool ?? false
        interests = dict["interests"] as? String ?? ""
        location = dict["location"] as? String ?? ""
    }

    func presence(now: Date = Date()) -> Presence {
        guard signedOn, !invisible else { return .offline }
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
    let file: FileOffer?
    let rich: [RichSegment]?

    init(id: String, dict: [String: Any]) {
        self.id = id
        from = dict["from"] as? String ?? ""
        text = dict["text"] as? String ?? ""
        ts = (dict["ts"] as? NSNumber)?.doubleValue ?? 0
        style = TextStyle(dict: dict["style"] as? [String: Any])
        isAuto = dict["auto"] as? Bool ?? false
        fromName = dict["name"] as? String
        file = (dict["file"] as? [String: Any]).flatMap(FileOffer.init(dict:))
        rich = (dict["rich"] as? [[String: Any]])?.map(RichSegment.init(dict:))
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


/// One run of text with its own style (for per-word formatting).
struct RichSegment: Equatable {
    var text: String
    var style: TextStyle

    init(text: String, style: TextStyle) {
        self.text = text
        self.style = style
    }

    init(dict: [String: Any]) {
        text = dict["t"] as? String ?? ""
        style = TextStyle(dict: dict["s"] as? [String: Any])
    }

    var dict: [String: Any] { ["t": text, "s": style.dict] }
}

/// Things that live only on your account: nicknames for buddies, pounces, privacy.
struct BuddyPounce: Codable, Identifiable, Equatable {
    enum Trigger: String, Codable, CaseIterable, Identifiable {
        case signsOn, returnsFromAway, returnsFromIdle
        var id: String { rawValue }
        var label: String {
            switch self {
            case .signsOn: return "Signs on"
            case .returnsFromAway: return "Returns from away"
            case .returnsFromIdle: return "Returns from idle"
            }
        }
    }
    var id = UUID()
    var buddy: String
    var triggers: Set<Trigger> = [.signsOn]
    var openIM = true
    var sendMessage = ""
    var playSound = true
    var keep = false
}

struct AccountPrefs: Codable, Equatable {
    enum Privacy: String, Codable, CaseIterable, Identifiable {
        case everyone, buddiesOnly
        var id: String { rawValue }
        var label: String { self == .everyone ? "Anyone can IM me" : "Only people on my Buddy List" }
    }
    var aliases: [String: String] = [:]
    var pounces: [BuddyPounce] = []
    var privacy: Privacy = .everyone
    var imCatcher = true
}
