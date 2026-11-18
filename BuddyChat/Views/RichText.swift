import SwiftUI
import UIKit

// MARK: Smileys (BuddyChat's own little faces, drawn in code)

enum Smiley: String, CaseIterable, Identifiable {
    case smile, wink, grin, tongue, frown, cry, surprised, cool, kiss, angry, unsure, angel, embarrassed, heart
    var id: String { rawValue }

    /// The code the smiley picker types for you.
    var code: String {
        switch self {
        case .smile: return ":-)"
        case .wink: return ";-)"
        case .grin: return ":-D"
        case .tongue: return ":-P"
        case .frown: return ":-("
        case .cry: return ":'("
        case .surprised: return ":-O"
        case .cool: return "8-)"
        case .kiss: return ":-*"
        case .angry: return ">:-("
        case .unsure: return ":-/"
        case .angel: return "O:-)"
        case .embarrassed: return ":-["
        case .heart: return "<3"
        }
    }

    /// Every code that turns into a face, longest first so ">:-(" wins over ":-(".
    static let codes: [(String, Smiley)] = {
        let list: [(String, Smiley)] = [
            (":-)", .smile), (":)", .smile), (";-)", .wink), (";)", .wink), (":-D", .grin), (":D", .grin),
            (":-P", .tongue), (":P", .tongue), (":-p", .tongue), (":p", .tongue), (":-(", .frown), (":(", .frown),
            (":'(", .cry), (":-O", .surprised), (":O", .surprised), (":-o", .surprised), ("8-)", .cool), ("B-)", .cool),
            (":-*", .kiss), (":*", .kiss), (">:-(", .angry), (">:(", .angry), (":-/", .unsure), ("O:-)", .angel),
            ("O:)", .angel), (":-[", .embarrassed), ("<3", .heart),
        ]
        return list.sorted { $0.0.count > $1.0.count }
    }()

    private static var cache: [String: UIImage] = [:]

    func image(size: CGFloat) -> UIImage {
        let key = "\(rawValue).\(Int(size))"
        if let img = Self.cache[key] { return img }
        let img = draw(size: size)
        Self.cache[key] = img
        return img
    }

    private func draw(size s: CGFloat) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: s, height: s)).image { ctx in
            let c = ctx.cgContext
            let line = max(1, s / 15)
            c.setLineCap(.round)
            c.setLineJoin(.round)

            if self == .heart {
                let p = UIBezierPath()
                p.move(to: CGPoint(x: s / 2, y: s * 0.88))
                p.addCurve(to: CGPoint(x: s * 0.06, y: s * 0.36), controlPoint1: CGPoint(x: s * 0.3, y: s * 0.72),
                           controlPoint2: CGPoint(x: s * 0.06, y: s * 0.56))
                p.addArc(withCenter: CGPoint(x: s * 0.28, y: s * 0.32), radius: s * 0.22, startAngle: .pi * 1.05, endAngle: .pi * 1.95, clockwise: true)
                p.addArc(withCenter: CGPoint(x: s * 0.72, y: s * 0.32), radius: s * 0.22, startAngle: .pi * 1.05, endAngle: .pi * 1.95, clockwise: true)
                p.addCurve(to: CGPoint(x: s / 2, y: s * 0.88), controlPoint1: CGPoint(x: s * 0.94, y: s * 0.56),
                           controlPoint2: CGPoint(x: s * 0.7, y: s * 0.72))
                UIColor(red: 0.9, green: 0.1, blue: 0.2, alpha: 1).setFill()
                p.fill()
                UIColor(red: 0.5, green: 0, blue: 0.05, alpha: 1).setStroke()
                p.lineWidth = line
                p.stroke()
                return
            }

            // Face
            let face = CGRect(x: line, y: line, width: s - 2 * line, height: s - 2 * line)
            let faceColor = self == .angry ? UIColor(red: 1, green: 0.45, blue: 0.2, alpha: 1)
                : UIColor(red: 1, green: 0.86, blue: 0.1, alpha: 1)
            c.setFillColor(faceColor.cgColor)
            c.fillEllipse(in: face)
            c.setStrokeColor(UIColor.black.cgColor)
            c.setLineWidth(line)
            c.strokeEllipse(in: face)

            if self == .embarrassed {
                c.setFillColor(UIColor(red: 1, green: 0.45, blue: 0.5, alpha: 0.8).cgColor)
                c.fillEllipse(in: CGRect(x: s * 0.16, y: s * 0.5, width: s * 0.18, height: s * 0.12))
                c.fillEllipse(in: CGRect(x: s * 0.66, y: s * 0.5, width: s * 0.18, height: s * 0.12))
            }

            // Eyes
            let ey = s * 0.38, lx = s * 0.35, rx = s * 0.65
            func dot(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
                c.setFillColor(UIColor.black.cgColor)
                c.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            }
            switch self {
            case .wink:
                dot(lx, ey, s * 0.065)
                stroke([CGPoint(x: rx - s * 0.08, y: ey), CGPoint(x: rx + s * 0.08, y: ey)], c, line)
            case .cool:
                c.setFillColor(UIColor.black.cgColor)
                c.fill(CGRect(x: s * 0.2, y: ey - s * 0.08, width: s * 0.25, height: s * 0.14))
                c.fill(CGRect(x: s * 0.55, y: ey - s * 0.08, width: s * 0.25, height: s * 0.14))
                stroke([CGPoint(x: s * 0.42, y: ey - s * 0.04), CGPoint(x: s * 0.58, y: ey - s * 0.04)], c, line)
            case .surprised:
                dot(lx, ey, s * 0.085)
                dot(rx, ey, s * 0.085)
            case .grin:
                stroke([CGPoint(x: lx - s * 0.07, y: ey + s * 0.03), CGPoint(x: lx, y: ey - s * 0.04), CGPoint(x: lx + s * 0.07, y: ey + s * 0.03)], c, line)
                stroke([CGPoint(x: rx - s * 0.07, y: ey + s * 0.03), CGPoint(x: rx, y: ey - s * 0.04), CGPoint(x: rx + s * 0.07, y: ey + s * 0.03)], c, line)
            default:
                dot(lx, ey, s * 0.065)
                dot(rx, ey, s * 0.065)
            }
            if self == .angry {
                stroke([CGPoint(x: s * 0.22, y: s * 0.24), CGPoint(x: s * 0.43, y: s * 0.31)], c, line * 1.3)
                stroke([CGPoint(x: s * 0.78, y: s * 0.24), CGPoint(x: s * 0.57, y: s * 0.31)], c, line * 1.3)
            }

            // Mouth
            let mouth = UIBezierPath()
            mouth.lineWidth = line * 1.2
            mouth.lineCapStyle = .round
            UIColor.black.setStroke()
            switch self {
            case .smile, .wink, .cool, .angel, .embarrassed:
                mouth.addArc(withCenter: CGPoint(x: s / 2, y: s * 0.5), radius: s * 0.24, startAngle: .pi * 0.2, endAngle: .pi * 0.8, clockwise: true)
                mouth.stroke()
            case .grin:
                mouth.addArc(withCenter: CGPoint(x: s / 2, y: s * 0.56), radius: s * 0.22, startAngle: 0, endAngle: .pi, clockwise: true)
                mouth.close()
                UIColor.white.setFill()
                mouth.fill()
                mouth.stroke()
            case .tongue:
                UIColor(red: 0.95, green: 0.3, blue: 0.4, alpha: 1).setFill()
                UIBezierPath(ovalIn: CGRect(x: s * 0.46, y: s * 0.64, width: s * 0.18, height: s * 0.2)).fill()
                mouth.move(to: CGPoint(x: s * 0.3, y: s * 0.66))
                mouth.addLine(to: CGPoint(x: s * 0.7, y: s * 0.66))
                mouth.stroke()
            case .frown, .cry, .angry:
                mouth.addArc(withCenter: CGPoint(x: s / 2, y: s * 0.86), radius: s * 0.22, startAngle: .pi * 1.2, endAngle: .pi * 1.8, clockwise: true)
                mouth.stroke()
            case .surprised:
                UIColor.black.setFill()
                UIBezierPath(ovalIn: CGRect(x: s * 0.41, y: s * 0.58, width: s * 0.18, height: s * 0.22)).fill()
            case .kiss:
                UIColor(red: 0.9, green: 0.1, blue: 0.3, alpha: 1).setFill()
                UIBezierPath(ovalIn: CGRect(x: s * 0.4, y: s * 0.6, width: s * 0.2, height: s * 0.15)).fill()
            case .unsure:
                mouth.move(to: CGPoint(x: s * 0.32, y: s * 0.7))
                mouth.addLine(to: CGPoint(x: s * 0.68, y: s * 0.62))
                mouth.stroke()
            case .heart:
                break
            }

            if self == .cry {
                UIColor(red: 0.3, green: 0.6, blue: 1, alpha: 1).setFill()
                UIBezierPath(ovalIn: CGRect(x: rx - s * 0.04, y: ey + s * 0.08, width: s * 0.09, height: s * 0.16)).fill()
            }
            if self == .angel {
                UIColor(red: 0.2, green: 0.6, blue: 1, alpha: 1).setStroke()
                let halo = UIBezierPath(ovalIn: CGRect(x: s * 0.25, y: line, width: s * 0.5, height: s * 0.14))
                halo.lineWidth = line * 1.2
                halo.stroke()
            }
        }
    }

    private func stroke(_ points: [CGPoint], _ c: CGContext, _ width: CGFloat) {
        guard let first = points.first else { return }
        c.setStrokeColor(UIColor.black.cgColor)
        c.setLineWidth(width)
        c.beginPath()
        c.move(to: first)
        for p in points.dropFirst() { c.addLine(to: p) }
        c.strokePath()
    }
}

// MARK: Turning message text into styled Text with faces and tappable links

enum RichText {
    enum Token {
        case plain(String)
        case link(String, URL)
        case smiley(Smiley)
    }

    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    /// The styled runs of a message (one run for ordinary messages).
    static func segments(of m: ChatMessage) -> [RichSegment] {
        if let rich = m.rich, !rich.isEmpty { return rich }
        return [RichSegment(text: m.text, style: m.style)]
    }

    static func text(_ segments: [RichSegment]) -> Text {
        var out = Text("")
        for seg in segments { out = out + render(seg) }
        return out
    }

    static func text(_ plain: String, style: TextStyle) -> Text {
        render(RichSegment(text: plain, style: style))
    }

    private static func render(_ seg: RichSegment) -> Text {
        var out = Text("")
        let st = seg.style
        for token in tokenize(seg.text) {
            switch token {
            case .plain(let s):
                out = out + Text(s).font(st.swiftUIFont).foregroundColor(Color(hex: st.color)).underline(st.underline)
            case .link(let s, let url):
                var a = AttributedString(s)
                a.link = url
                out = out + Text(a).font(st.swiftUIFont).underline()
            case .smiley(let sm):
                out = out + Text(Image(uiImage: sm.image(size: CGFloat(st.size) + 3))).baselineOffset(-CGFloat(st.size) * 0.18)
            }
        }
        return out
    }

    static func tokenize(_ s: String) -> [Token] {
        let ns = s as NSString
        var tokens: [Token] = []
        var cursor = 0
        for m in detector?.matches(in: s, range: NSRange(location: 0, length: ns.length)) ?? [] {
            guard m.range.location >= cursor else { continue }
            if m.range.location > cursor {
                tokens += faces(ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor)))
            }
            let piece = ns.substring(with: m.range)
            if let url = m.url { tokens.append(.link(piece, url)) } else { tokens += faces(piece) }
            cursor = m.range.location + m.range.length
        }
        if cursor < ns.length { tokens += faces(ns.substring(from: cursor)) }
        return tokens
    }

    private static func faces(_ s: String) -> [Token] {
        var out: [Token] = []
        var buffer = ""
        var i = s.startIndex
        scan: while i < s.endIndex {
            let rest = s[i...]
            for (code, face) in Smiley.codes where rest.hasPrefix(code) {
                if !buffer.isEmpty { out.append(.plain(buffer)); buffer = "" }
                out.append(.smiley(face))
                i = s.index(i, offsetBy: code.count)
                continue scan
            }
            buffer.append(s[i])
            i = s.index(after: i)
        }
        if !buffer.isEmpty { out.append(.plain(buffer)) }
        return out
    }
}

/// Plain text (profiles, away messages) with faces and tappable links.
struct LinkedText: View {
    let text: String
    var size: Double = 13

    var body: some View {
        var style = TextStyle()
        style.size = size
        return RichText.text(text, style: style)
    }
}

// MARK: IM window backgrounds

enum IMBackground: String, CaseIterable, Identifiable {
    case plain, sky, notebook, bubblegum, mint, sunshine, stars
    var id: String { rawValue }
    var label: String {
        switch self {
        case .plain: return "Plain White"
        case .sky: return "Sky"
        case .notebook: return "Notebook"
        case .bubblegum: return "Bubblegum"
        case .mint: return "Mint"
        case .sunshine: return "Sunshine"
        case .stars: return "Starry"
        }
    }
}

struct IMBackgroundView: View {
    let background: IMBackground

    var body: some View {
        switch background {
        case .plain:
            Retro.field
        case .sky:
            LinearGradient(colors: [Color(red: 0.75, green: 0.88, blue: 1.0), .white], startPoint: .top, endPoint: .bottom)
        case .notebook:
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
                var y: CGFloat = 22
                while y < size.height {
                    ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(Color(red: 0.6, green: 0.75, blue: 0.95)))
                    y += 20
                }
                ctx.fill(Path(CGRect(x: 26, y: 0, width: 1.5, height: size.height)), with: .color(Color(red: 0.95, green: 0.5, blue: 0.5)))
            }
        case .bubblegum:
            LinearGradient(colors: [Color(red: 1.0, green: 0.85, blue: 0.93), Color(red: 1.0, green: 0.95, blue: 0.98)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        case .mint:
            Color(red: 0.86, green: 0.98, blue: 0.9)
        case .sunshine:
            LinearGradient(colors: [Color(red: 1.0, green: 0.95, blue: 0.7), Color(red: 1.0, green: 0.99, blue: 0.9)],
                           startPoint: .top, endPoint: .bottom)
        case .stars:
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.93, green: 0.92, blue: 1.0)))
                let star = ctx.resolve(Text("★").font(.system(size: 10)).foregroundColor(Color(red: 0.7, green: 0.65, blue: 0.95)))
                var i = 0
                var y: CGFloat = 12
                while y < size.height {
                    var x: CGFloat = CGFloat((i * 37) % 50)
                    while x < size.width {
                        ctx.draw(star, at: CGPoint(x: x, y: y))
                        x += 56
                    }
                    y += 34
                    i += 1
                }
            }
        }
    }
}
