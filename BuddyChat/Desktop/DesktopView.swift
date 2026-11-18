import SwiftUI

/// BuddyChat's own wallpapers (or your own picture from Setup).
enum Wallpaper: String, CaseIterable, Identifiable {
    case teal, dusk, grid, bubbles, custom
    var id: String { rawValue }
    var label: String {
        switch self {
        case .teal: return "Classic Teal"
        case .dusk: return "Dusk"
        case .grid: return "Retro Grid"
        case .bubbles: return "Bubbles"
        case .custom: return "My Picture"
        }
    }

    static var customURL: URL { Sounds.skinFolder.appendingPathComponent("wallpaper.jpg") }
}

struct WallpaperView: View {
    @AppStorage("wallpaper") private var wallpaper: Wallpaper = .teal

    var body: some View {
        GeometryReader { g in
            switch wallpaper {
            case .teal:
                Color(red: 0.0, green: 0.5, blue: 0.5)
            case .dusk:
                LinearGradient(colors: [Color(red: 0.12, green: 0.10, blue: 0.35), Color(red: 0.75, green: 0.35, blue: 0.45),
                                        Color(red: 0.98, green: 0.70, blue: 0.40)], startPoint: .top, endPoint: .bottom)
            case .grid:
                ZStack {
                    LinearGradient(colors: [Color(red: 0.08, green: 0.0, blue: 0.2), Color(red: 0.35, green: 0.0, blue: 0.45)],
                                   startPoint: .top, endPoint: .bottom)
                    Path { p in
                        let step: CGFloat = 32
                        var x: CGFloat = 0
                        while x < g.size.width { p.move(to: .init(x: x, y: 0)); p.addLine(to: .init(x: x, y: g.size.height)); x += step }
                        var y: CGFloat = 0
                        while y < g.size.height { p.move(to: .init(x: 0, y: y)); p.addLine(to: .init(x: g.size.width, y: y)); y += step }
                    }
                    .stroke(Color(red: 1.0, green: 0.3, blue: 0.8).opacity(0.35), lineWidth: 1)
                }
            case .bubbles:
                ZStack {
                    LinearGradient(colors: [Color(red: 0.2, green: 0.55, blue: 0.9), Color(red: 0.55, green: 0.85, blue: 1.0)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    ForEach(0..<14, id: \.self) { i in
                        let r = CGFloat(30 + (i * 37) % 90)
                        Circle().fill(.white.opacity(0.12)).frame(width: r, height: r)
                            .position(x: CGFloat((i * 97) % 360) / 360 * g.size.width,
                                      y: CGFloat((i * 151) % 700) / 700 * g.size.height)
                    }
                }
            case .custom:
                if let img = UIImage(contentsOfFile: Wallpaper.customURL.path) {
                    Image(uiImage: img).resizable().scaledToFill().frame(width: g.size.width, height: g.size.height).clipped()
                } else {
                    Color(red: 0.0, green: 0.5, blue: 0.5)
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// The signed-on screen: wallpaper, floating windows and a taskbar.
struct DesktopView: View {
    @EnvironmentObject var store: ChatStore
    @ObservedObject var wm: WindowManager
    static let taskbarHeight: CGFloat = 40

    var body: some View {
        GeometryReader { g in
            let desk = CGSize(width: g.size.width, height: g.size.height - Self.taskbarHeight)
            ZStack(alignment: .topLeading) {
                WallpaperView()
                ForEach(wm.windows.filter { !$0.minimized }.sorted { $0.z < $1.z }) { w in
                    let f = wm.displayFrame(w)
                    DeskWindowView(window: w, wm: wm) { WindowContent(kind: w.kind) }
                        .frame(width: f.width, height: f.height)
                        .offset(x: f.minX, y: f.minY)
                        .environment(\.closeWindow, { wm.close(w.id) })
                }
                if let text = store.banner {
                    Text(text)
                        .font(Retro.body(13)).foregroundStyle(Retro.ink).lineLimit(2)
                        .padding(10).frame(width: desk.width - 32, alignment: .leading)
                        .background(Color(red: 1, green: 1, blue: 0.85)).bevel()
                        .offset(x: 16, y: 8)
                        .task {
                            try? await Task.sleep(nanoseconds: 4_000_000_000)
                            store.banner = nil
                        }
                }
                TaskbarView(wm: wm)
                    .frame(width: g.size.width, height: Self.taskbarHeight)
                    .offset(y: desk.height)
            }
            .onAppear {
                wm.desk = desk
                if wm.find(.buddyList) == nil { wm.open(.buddyList) }
            }
            .onChange(of: g.size) { _, new in
                wm.desk = CGSize(width: new.width, height: new.height - Self.taskbarHeight)
            }
        }
        .ignoresSafeArea(.keyboard)
    }
}

/// Window frame: gradient title bar you can drag, minimize / maximize / close buttons, resize corner.
struct DeskWindowView<Content: View>: View {
    let window: DeskWindow
    @ObservedObject var wm: WindowManager
    @ViewBuilder var content: () -> Content
    @EnvironmentObject var store: ChatStore
    @AppStorage("theme") private var theme: RetroTheme = .ocean
    @State private var dragStart: CGPoint?
    @State private var resizeStart: CGSize?

    private var isFront: Bool { wm.frontID == window.id }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Retro.face)
                .clipped()
        }
        .overlay(alignment: .bottomTrailing) { if !window.maximized { resizeHandle } }
        .bevel()
        .shadow(color: .black.opacity(isFront ? 0.45 : 0.2), radius: isFront ? 8 : 3, x: 2, y: 3)
        .simultaneousGesture(TapGesture().onEnded { wm.bringToFront(window.id) })
    }

    private var titleBar: some View {
        HStack(spacing: 5) {
            WindowIcon(kind: window.kind)
            Text(WindowTitle.text(window.kind, store: store))
                .font(Retro.titleFont(12)).lineLimit(1)
            Spacer(minLength: 4)
            chromeButton("minus") { wm.toggleMinimize(window.id) }
            if window.kind != .buddyList {
                chromeButton(window.maximized ? "arrow.down.right.and.arrow.up.left" : "square") { wm.toggleMaximize(window.id) }
            }
            if window.kind != .buddyList {
                chromeButton("xmark", red: true) { wm.close(window.id) }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .frame(height: 28)
        .background(LinearGradient(colors: isFront ? theme.colors : [Color.gray, Color.gray.opacity(0.7)],
                                   startPoint: .leading, endPoint: .trailing))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2, coordinateSpace: .global)
                .onChanged { v in
                    guard !window.maximized else { return }
                    if dragStart == nil { dragStart = window.frame.origin; wm.bringToFront(window.id) }
                    if let s = dragStart {
                        wm.move(window.id, to: CGPoint(x: s.x + v.translation.width, y: s.y + v.translation.height))
                    }
                }
                .onEnded { _ in dragStart = nil }
        )
        .onTapGesture(count: 2) { if window.kind != .buddyList { wm.toggleMaximize(window.id) } }
    }

    private func chromeButton(_ icon: String, red: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 9, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 22, height: 20)
                .background(red ? Color(red: 0.85, green: 0.25, blue: 0.2) : Color.white.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(.white.opacity(0.8), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var resizeHandle: some View {
        Image(systemName: "arrow.down.right")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Retro.dark)
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { v in
                        if resizeStart == nil { resizeStart = window.frame.size }
                        if let s = resizeStart {
                            wm.resize(window.id, to: CGSize(width: s.width + v.translation.width, height: s.height + v.translation.height))
                        }
                    }
                    .onEnded { _ in resizeStart = nil }
            )
    }
}

struct WindowIcon: View {
    let kind: WindowKind
    @EnvironmentObject var store: ChatStore

    var body: some View {
        if case .im(let uid) = kind, let icon = store.icons[uid] {
            Image(uiImage: icon).resizable().scaledToFill().frame(width: 16, height: 16).clipShape(RoundedRectangle(cornerRadius: 2))
        } else {
            Image(systemName: symbol).font(.system(size: 11, weight: .bold))
        }
    }

    private var symbol: String {
        switch kind {
        case .buddyList: return "list.bullet.rectangle.fill"
        case .im: return "bubble.left.and.bubble.right.fill"
        case .info: return "info.circle.fill"
        case .room, .rooms: return "person.3.fill"
        case .away: return "note.text"
        case .profile: return "person.text.rectangle"
        case .addBuddy: return "person.badge.plus"
        case .setup: return "gearshape.fill"
        case .pounce: return "bell.badge.fill"
        case .history: return "clock.arrow.circlepath"
        case .directory: return "magnifyingglass"
        case .catcher: return "tray.full.fill"
        case .invites: return "envelope.open.fill"
        case .privacy: return "lock.fill"
        }
    }
}

enum WindowTitle {
    @MainActor
    static func text(_ kind: WindowKind, store: ChatStore) -> String {
        switch kind {
        case .buddyList: return "\(store.myScreenName)'s Buddy List"
        case .im(let u): return "\(store.name(u)) - IM"
        case .info(let u): return "Info: \(store.name(u))"
        case .room(let r): return "Chat: \(r)"
        case .history(let u): return "History: \(store.name(u))"
        case .rooms: return "Chat Rooms"
        case .away: return "Away Message"
        case .profile: return "My Profile"
        case .addBuddy: return "Add Buddy"
        case .setup: return "Setup"
        case .pounce: return "Buddy Pounce"
        case .directory: return "Member Directory"
        case .catcher: return "IM Catcher"
        case .invites: return "Chat Invitations"
        case .privacy: return "Privacy"
        }
    }
}

struct TaskbarView: View {
    @ObservedObject var wm: WindowManager
    @EnvironmentObject var store: ChatStore

    var body: some View {
        HStack(spacing: 4) {
            Button { wm.open(.buddyList) } label: {
                HStack(spacing: 4) {
                    BuddyMascot(size: 22)
                    Text("Buddies").font(Retro.titleFont(12)).foregroundStyle(Retro.ink)
                }
                .padding(.horizontal, 6).frame(height: 30).background(Retro.face).bevel()
            }
            .buttonStyle(.plain)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(wm.windows.filter { $0.kind != .buddyList }) { w in
                        let flashing = wm.flashing.contains(w.id)
                        Button {
                            if w.minimized || wm.frontID != w.id { wm.open(w.kind) } else { wm.toggleMinimize(w.id) }
                        } label: {
                            HStack(spacing: 3) {
                                WindowIcon(kind: w.kind)
                                Text(WindowTitle.text(w.kind, store: store)).font(Retro.body(11)).lineLimit(1)
                            }
                            .foregroundStyle(flashing ? .white : Retro.ink)
                            .padding(.horizontal, 6).frame(maxWidth: 130, minHeight: 30)
                            .background(flashing ? Color.orange : (wm.frontID == w.id ? Retro.light : Retro.face))
                            .bevel(sunken: wm.frontID == w.id && !w.minimized)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Text(Date().formatted(date: .omitted, time: .shortened))
                .font(Retro.body(11)).foregroundStyle(Retro.ink)
                .padding(.horizontal, 6).frame(height: 30).bevel(sunken: true)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Retro.face)
        .overlay(alignment: .top) { Rectangle().fill(Retro.light).frame(height: 1) }
    }
}
