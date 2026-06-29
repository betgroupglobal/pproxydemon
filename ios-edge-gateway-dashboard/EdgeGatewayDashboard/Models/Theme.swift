import SwiftUI

/// Edge Gateway Dashboard theme — dark developer-tool aesthetic with an electric-lime accent.
enum GatewayTheme {
    // MARK: Colors
    static let bg = Color(hex: "08090C")
    static let bgElevated = Color(hex: "0E1014")
    static let surface = Color(hex: "121620")
    static let surfaceAlt = Color(hex: "171C28")
    static let border = Color(hex: "222836")
    static let borderStrong = Color(hex: "303749")
    static let text = Color(hex: "EDF1F7")
    static let textDim = Color(hex: "9AA4B6")
    static let textFaint = Color(hex: "5C6679")
    static let accent = Color(hex: "B8FF3C")
    static let accentDim = Color(hex: "7FAE2C")
    static let accentGlow = Color(hex: "B8FF3C").opacity(0.16)
    static let cyan = Color(hex: "46E0FF")
    static let danger = Color(hex: "FF5C72")
    static let warn = Color(hex: "FFB23E")
    static let ok = Color(hex: "3CE08A")

    // MARK: Spacing
    static func spacing(_ n: CGFloat) -> CGFloat { n * 4 }

    // MARK: Radius
    static let radiusSm: CGFloat = 10
    static let radiusMd: CGFloat = 16
    static let radiusLg: CGFloat = 22

    // MARK: Card style — single parameterized modifier replacing CardSurface/CardElevated/CardDepth
    struct CardStyle: ViewModifier {
        let bg: Color
        let border: Color
        let borderWidth: CGFloat

        func body(content: Content) -> some View {
            content
                .background(bg)
                .clipShape(.rect(cornerRadius: GatewayTheme.radiusMd))
                .overlay(
                    RoundedRectangle(cornerRadius: GatewayTheme.radiusMd)
                        .stroke(border, lineWidth: borderWidth)
                )
        }
    }

    // MARK: HTTP status helpers

    static func statusColor(_ status: Int) -> Color {
        if status >= 500 { return danger }
        if status >= 400 { return warn }
        if status >= 300 { return cyan }
        return ok
    }

    static func methodColor(_ method: String) -> Color {
        switch method {
        case "GET": return cyan
        case "POST": return ok
        case "PUT": return warn
        case "DELETE": return danger
        default: return textDim
        }
    }

    // MARK: Shared time formatter

    static func ago(_ ts: Int) -> String {
        let diff = max(0, Int(Date().timeIntervalSince1970 * 1000) - ts)
        let s = diff / 1000
        if s < 1 { return "now" }
        if s < 60 { return "\(s)s" }
        let m = s / 60
        if m < 60 { return "\(m)m" }
        return "\(m / 60)h"
    }

    static func formatUptime(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let m = seconds / 60
        if m < 60 { return "\(m)m \(seconds % 60)s" }
        let h = m / 60
        return "\(h)h \(m % 60)m"
    }

    // MARK: Shared date formatter for timestamps

    nonisolated static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    struct MonoFont: ViewModifier {
        let size: CGFloat
        let weight: Font.Weight

        func body(content: Content) -> some View {
            content
                .font(.system(size: size, weight: weight, design: .monospaced))
        }
    }

    struct FieldLabel: ViewModifier {
        func body(content: Content) -> some View {
            content
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(GatewayTheme.textFaint)
                .kerning(1)
                .textCase(.uppercase)
        }
    }

    struct Eyebrow: ViewModifier {
        func body(content: Content) -> some View {
            content
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(GatewayTheme.accent)
                .kerning(2)
                .textCase(.uppercase)
        }
    }

    struct SectionTitle: ViewModifier {
        func body(content: Content) -> some View {
            content
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(GatewayTheme.textDim)
                .kerning(1.5)
                .textCase(.uppercase)
        }
    }
}

// MARK: - View extensions

extension View {
    func cardSurface() -> some View {
        modifier(GatewayTheme.CardStyle(bg: GatewayTheme.surface, border: GatewayTheme.border, borderWidth: 1))
    }

    func cardElevated() -> some View {
        modifier(GatewayTheme.CardStyle(bg: GatewayTheme.bgElevated, border: GatewayTheme.border, borderWidth: 1))
    }

    func cardDepth() -> some View {
        modifier(GatewayTheme.CardStyle(bg: GatewayTheme.surface, border: GatewayTheme.accent.opacity(0.18), borderWidth: 1.5))
    }

    func monoFont(size: CGFloat, weight: Font.Weight = .regular) -> some View {
        modifier(GatewayTheme.MonoFont(size: size, weight: weight))
    }

    func fieldLabelStyle() -> some View {
        modifier(GatewayTheme.FieldLabel())
    }

    func eyebrowStyle() -> some View {
        modifier(GatewayTheme.Eyebrow())
    }

    func sectionTitleStyle() -> some View {
        modifier(GatewayTheme.SectionTitle())
    }
}

// MARK: - Color hex init

private nonisolated let hexInverted = CharacterSet.alphanumerics.inverted

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: hexInverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
