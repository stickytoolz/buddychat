import SwiftUI

/// BuddyChat's own early-2000s desktop look: beveled gray panels, gradient title bars, chunky buttons.
enum Retro {
    static let face = Color(red: 0.83, green: 0.82, blue: 0.78)        // classic gray panel
    static let light = Color.white
    static let shadow = Color(red: 0.50, green: 0.50, blue: 0.48)
    static let dark = Color(red: 0.25, green: 0.25, blue: 0.24)
    static let field = Color.white
    static let ink = Color.black
    static let me = Color(red: 0.80, green: 0.0, blue: 0.0)
    static let them = Color(red: 0.0, green: 0.15, blue: 0.75)

    static func titleFont(_ size: CGFloat = 13) -> Font { .custom("Verdana-Bold", size: size) }
    static func body(_ size: CGFloat = 13) -> Font { .custom("Verdana", size: size) }
}

/// Selectable title-bar color themes.
enum RetroTheme: String, CaseIterable, Identifiable {
    case ocean, grape, lime, cherry, midnight
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var colors: [Color] {
        switch self {
        case .ocean: return [Color(red: 0.05, green: 0.25, blue: 0.65), Color(red: 0.35, green: 0.65, blue: 0.95)]
        case .grape: return [Color(red: 0.35, green: 0.10, blue: 0.55), Color(red: 0.70, green: 0.45, blue: 0.90)]
        case .lime: return [Color(red: 0.10, green: 0.45, blue: 0.15), Color(red: 0.55, green: 0.85, blue: 0.35)]
        case .cherry: return [Color(red: 0.60, green: 0.05, blue: 0.10), Color(red: 0.95, green: 0.45, blue: 0.45)]
        case .midnight: return [Color(red: 0.05, green: 0.05, blue: 0.15), Color(red: 0.30, green: 0.30, blue: 0.45)]
        }
    }
}

struct Bevel: ViewModifier {
    var sunken = false
    func body(content: Content) -> some View {
        content.overlay(
            GeometryReader { g in
                let w = g.size.width, h = g.size.height
                ZStack {
                    Path { p in p.move(to: .init(x: 0, y: h)); p.addLine(to: .zero); p.addLine(to: .init(x: w, y: 0)) }
                        .stroke(sunken ? Retro.shadow : Retro.light, lineWidth: 2)
                    Path { p in p.move(to: .init(x: w, y: 0)); p.addLine(to: .init(x: w, y: h)); p.addLine(to: .init(x: 0, y: h)) }
                        .stroke(sunken ? Retro.light : Retro.dark, lineWidth: 2)
                }
            }
            .allowsHitTesting(false)
        )
    }
}

extension View {
    func bevel(sunken: Bool = false) -> some View { modifier(Bevel(sunken: sunken)) }
}

struct RetroButtonStyle: ButtonStyle {
    var bold = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(bold ? Retro.titleFont(13) : Retro.body(13))
            .foregroundStyle(Retro.ink)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Retro.face)
            .bevel(sunken: configuration.isPressed)
            .offset(x: configuration.isPressed ? 1 : 0, y: configuration.isPressed ? 1 : 0)
    }
}

/// A desktop-style "window" with a gradient title bar.
struct RetroWindow<Content: View, Trailing: View>: View {
    let title: String
    var icon: String = "bubble.left.and.bubble.right.fill"
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content
    @AppStorage("theme") private var theme: RetroTheme = .ocean

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 13, weight: .bold))
                Text(title).font(Retro.titleFont(14)).lineLimit(1)
                Spacer()
                trailing()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 7)
            .background(LinearGradient(colors: theme.colors, startPoint: .leading, endPoint: .trailing))
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Retro.face)
        }
        .bevel()
    }
}

extension RetroWindow where Trailing == EmptyView {
    init(title: String, icon: String = "bubble.left.and.bubble.right.fill", @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.icon = icon
        self.trailing = { EmptyView() }
        self.content = content
    }
}

struct RetroField: View {
    let label: String
    @Binding var text: String
    var secure = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(Retro.body(12)).foregroundStyle(Retro.ink)
            Group {
                if secure { SecureField("", text: $text) } else { TextField("", text: $text) }
            }
            .font(Retro.body(15))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .foregroundStyle(Retro.ink)
            .padding(6)
            .background(Retro.field)
            .bevel(sunken: true)
        }
    }
}

/// BuddyChat's own mascot: a little speech-bubble buddy with a wave. (Can be replaced in Skin.)
struct BuddyMascot: View {
    var size: CGFloat = 120
    @AppStorage("theme") private var theme: RetroTheme = .ocean

    var body: some View {
        if let custom = SkinStore.customLogo {
            Image(uiImage: custom).resizable().scaledToFit().frame(width: size, height: size)
        } else {
            ZStack {
                // bubble body
                RoundedRectangle(cornerRadius: size * 0.28)
                    .fill(LinearGradient(colors: Array(theme.colors.reversed()), startPoint: .top, endPoint: .bottom))
                    .frame(width: size * 0.8, height: size * 0.62)
                    .offset(y: -size * 0.06)
                // bubble tail
                Path { p in
                    p.move(to: CGPoint(x: size * 0.30, y: size * 0.70))
                    p.addLine(to: CGPoint(x: size * 0.22, y: size * 0.92))
                    p.addLine(to: CGPoint(x: size * 0.48, y: size * 0.72))
                }
                .fill(theme.colors[0])
                // face
                HStack(spacing: size * 0.16) {
                    Capsule().fill(.white).frame(width: size * 0.09, height: size * 0.16)
                    Capsule().fill(.white).frame(width: size * 0.09, height: size * 0.16)
                }
                .offset(y: -size * 0.12)
                Path { p in
                    p.addArc(center: CGPoint(x: size / 2, y: size * 0.46), radius: size * 0.14,
                             startAngle: .degrees(20), endAngle: .degrees(160), clockwise: false)
                }
                .stroke(.white, style: StrokeStyle(lineWidth: size * 0.045, lineCap: .round))
                // waving hand
                Circle().fill(Color.yellow).frame(width: size * 0.18).offset(x: size * 0.42, y: -size * 0.32)
            }
            .frame(width: size, height: size)
        }
    }
}

enum SkinStore {
    static var logoURL: URL { Sounds.skinFolder.appendingPathComponent("logo.png") }
    static var customLogo: UIImage? { UIImage(contentsOfFile: logoURL.path) }
}
