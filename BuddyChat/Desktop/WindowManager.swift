import SwiftUI
import UIKit

/// Every kind of window that can appear on the BuddyChat desktop.
enum WindowKind: Hashable {
    case buddyList
    case im(String)          // buddy uid
    case info(String)
    case room(String)
    case rooms
    case away
    case profile
    case addBuddy
    case setup
    case pounce
    case history(String)
    case directory
    case catcher
    case invites
    case privacy

    var id: String {
        switch self {
        case .buddyList: return "buddylist"
        case .im(let u): return "im.\(u)"
        case .info(let u): return "info.\(u)"
        case .room(let r): return "room.\(r)"
        case .history(let u): return "history.\(u)"
        case .rooms: return "rooms"
        case .away: return "away"
        case .profile: return "profile"
        case .addBuddy: return "addbuddy"
        case .setup: return "setup"
        case .pounce: return "pounce"
        case .directory: return "directory"
        case .catcher: return "catcher"
        case .invites: return "invites"
        case .privacy: return "privacy"
        }
    }

    /// Starting size for each kind of window.
    var preferredSize: CGSize {
        switch self {
        case .buddyList: return CGSize(width: 175, height: 600)
        case .im, .room: return CGSize(width: 330, height: 330)
        case .info, .history: return CGSize(width: 300, height: 380)
        default: return CGSize(width: 320, height: 430)
        }
    }
}

struct DeskWindow: Identifiable, Equatable {
    var id: String { kind.id }
    let kind: WindowKind
    var frame: CGRect
    var minimized = false
    var maximized = false
    var z: Int
}

/// Keeps track of the open windows: where they are, which is on top, which are minimized.
@MainActor
final class WindowManager: ObservableObject {
    @Published var windows: [DeskWindow] = []
    @Published var flashing: Set<String> = []
    @Published var keyboardHeight: CGFloat = 0
    var desk = CGSize(width: 390, height: 760)
    private var topZ = 0
    private var cascade = 0

    init() {
        NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main) { [weak self] note in
            guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let screen = UIScreen.main.bounds.height
            Task { @MainActor in
                withAnimation(.easeOut(duration: 0.25)) { self?.keyboardHeight = max(0, screen - frame.minY) }
            }
        }
    }

    var frontID: String? { windows.filter { !$0.minimized }.max(by: { $0.z < $1.z })?.id }

    func find(_ kind: WindowKind) -> DeskWindow? { windows.first { $0.kind == kind } }

    func open(_ kind: WindowKind, focus: Bool = true) {
        if let i = windows.firstIndex(where: { $0.kind == kind }) {
            if focus {
                windows[i].minimized = false
                bringToFront(windows[i].id)
            }
            return
        }
        topZ += 1
        windows.append(DeskWindow(kind: kind, frame: startFrame(for: kind), z: focus ? topZ : 0))
        if !focus, let i = windows.firstIndex(where: { $0.kind == kind }) {
            windows[i].z = topZ - 2
            flash(windows[i].id)
        }
    }

    func close(_ id: String) {
        windows.removeAll { $0.id == id }
        flashing.remove(id)
    }

    func closeAll() {
        windows = []
        flashing = []
        cascade = 0
    }

    func bringToFront(_ id: String) {
        guard let i = windows.firstIndex(where: { $0.id == id }) else { return }
        topZ += 1
        windows[i].z = topZ
        flashing.remove(id)
    }

    func toggleMinimize(_ id: String) {
        guard let i = windows.firstIndex(where: { $0.id == id }) else { return }
        windows[i].minimized.toggle()
        if !windows[i].minimized { bringToFront(id) }
    }

    func toggleMaximize(_ id: String) {
        guard let i = windows.firstIndex(where: { $0.id == id }) else { return }
        windows[i].maximized.toggle()
        bringToFront(id)
    }

    func move(_ id: String, to origin: CGPoint) {
        guard let i = windows.firstIndex(where: { $0.id == id }) else { return }
        var f = windows[i].frame
        f.origin.x = min(max(origin.x, -f.width + 80), desk.width - 60)
        f.origin.y = min(max(origin.y, 0), desk.height - 40)
        windows[i].frame = f
    }

    func resize(_ id: String, to size: CGSize) {
        guard let i = windows.firstIndex(where: { $0.id == id }) else { return }
        windows[i].frame.size = CGSize(width: max(170, min(size.width, desk.width)), height: max(160, min(size.height, desk.height)))
    }

    func flash(_ id: String) {
        guard frontID != id else { return }
        flashing.insert(id)
    }

    /// The Buddy List starts docked on the right side; other windows cascade from the top left.
    private func startFrame(for kind: WindowKind) -> CGRect {
        let size = kind.preferredSize
        if kind == .buddyList {
            let w = min(size.width, desk.width * 0.5)
            return CGRect(x: desk.width - w - 4, y: 4, width: w, height: desk.height - 8)
        }
        let w = min(size.width, desk.width - 16)
        var h = min(size.height, desk.height - 16)
        if case .im = kind { h = min(w, h) }      // IM and chat windows start out square
        if case .room = kind { h = min(w, h) }
        let step = CGFloat(cascade % 6) * 22
        cascade += 1
        return CGRect(x: 8 + step, y: 8 + step, width: w, height: h)
    }

    /// Where a window actually draws: maximized fills the desk, and the front window moves above the keyboard.
    func displayFrame(_ w: DeskWindow) -> CGRect {
        var f = w.maximized ? CGRect(origin: .zero, size: desk) : w.frame
        if keyboardHeight > 0, w.id == frontID {
            let limit = desk.height - keyboardHeight + 30   // the taskbar hides under the keyboard
            if f.maxY > limit {
                f.origin.y = max(0, limit - f.height)
                if f.maxY > limit { f.size.height = max(150, limit - f.origin.y) }
            }
        }
        return f
    }
}

/// Lets a window's contents close their own window.
struct CloseWindowKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var closeWindow: () -> Void {
        get { self[CloseWindowKey.self] }
        set { self[CloseWindowKey.self] = newValue }
    }
}
