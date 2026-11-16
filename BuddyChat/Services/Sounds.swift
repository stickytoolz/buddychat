import AVFoundation
import SwiftUI

/// Plays BuddyChat's sounds. Each sound can be replaced with your own file in Settings → Skin.
final class Sounds {
    enum Slot: String, CaseIterable, Identifiable {
        case signOn, signOff, receive, send
        var id: String { rawValue }
        var label: String {
            switch self {
            case .signOn: return "Buddy signs on"
            case .signOff: return "Buddy signs off"
            case .receive: return "Message received"
            case .send: return "Message sent"
            }
        }
        var bundled: String {
            switch self {
            case .signOn: return "door_in"
            case .signOff: return "door_out"
            case .receive: return "msg_in"
            case .send: return "msg_out"
            }
        }
    }

    static let shared = Sounds()
    private var players: [Slot: AVAudioPlayer] = [:]
    @AppStorage("soundsOn") var enabled = true

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        reload()
    }

    static var skinFolder: URL {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Skin", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func customURL(_ slot: Slot) -> URL? {
        let files = (try? FileManager.default.contentsOfDirectory(at: skinFolder, includingPropertiesForKeys: nil)) ?? []
        return files.first { $0.deletingPathExtension().lastPathComponent == "sound_\(slot.rawValue)" }
    }

    func reload() {
        players = [:]
        for slot in Slot.allCases {
            let url = Self.customURL(slot) ?? Bundle.main.url(forResource: slot.bundled, withExtension: "wav")
            if let url, let p = try? AVAudioPlayer(contentsOf: url) {
                p.prepareToPlay()
                players[slot] = p
            }
        }
    }

    func play(_ slot: Slot) {
        guard enabled, let p = players[slot] else { return }
        p.currentTime = 0
        p.play()
    }

    /// Copies a file the person picked into the skin folder for that sound.
    static func setCustom(_ slot: Slot, from source: URL) throws {
        if let old = customURL(slot) { try? FileManager.default.removeItem(at: old) }
        let ext = source.pathExtension.isEmpty ? "m4a" : source.pathExtension
        let dest = skinFolder.appendingPathComponent("sound_\(slot.rawValue).\(ext)")
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        try FileManager.default.copyItem(at: source, to: dest)
        shared.reload()
    }

    static func resetCustom(_ slot: Slot) {
        if let old = customURL(slot) { try? FileManager.default.removeItem(at: old) }
        shared.reload()
    }
}
