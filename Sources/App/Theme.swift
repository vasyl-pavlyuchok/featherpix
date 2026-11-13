import SwiftUI

/// Design tokens. Two tabs, one family: tinted graphite + frosted glass + ONE glowing accent per tab
/// (Photos = mint from the icon, Videos = ember, the red of a recording light). Palettes checked with
/// modern-ui-ux-design-expert/comprobar_paleta.py (13-nov-2026). Vivid colour lives in the atmosphere
/// and the key figure; the chrome stays neutral.
enum AppTab: String, CaseIterable, Identifiable {
    case photos, videos
    var id: String { rawValue }
}

struct TabTheme {
    let base: Color          // window background (L 0.155)
    let surface: Color       // cards (L 0.215)
    let accent: Color        // the one glowing colour
    let accentHi: Color      // lighter neighbour, for gradients on the key figure
    let haze: Color          // muted second hue, only in the atmosphere
    let ink: Color           // text on the accent (dark, ~10:1)
    let symbol: String       // big faint SF Symbol behind everything

    static let photos = TabTheme(
        base: Color(hex: 0x080E12), surface: Color(hex: 0x131C21),
        accent: Color(hex: 0x43D9BE), accentHi: Color(hex: 0x4CF0C2), haze: Color(hex: 0x474A68),
        ink: Color(hex: 0x06201B), symbol: "camera.aperture")
    static let videos = TabTheme(
        base: Color(hex: 0x110A0A), surface: Color(hex: 0x201716),
        accent: Color(hex: 0xF66E60), accentHi: Color(hex: 0xFF9661), haze: Color(hex: 0x573E55),
        ink: Color(hex: 0x2A0C08), symbol: "film")

    static func of(_ t: AppTab) -> TabTheme { t == .photos ? .photos : .videos }
}

enum Ink {
    static let title = Color.white
    static let lead = Color.white.opacity(0.72)
    static let body = Color.white.opacity(0.52)
    static let label = Color.white.opacity(0.34)
    static let hairline = Color.white.opacity(0.09)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }
}
