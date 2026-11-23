import SwiftUI

/// SwiftUI's classic `State` property wrapper. In the macOS 27 SDK, `@State` resolves to a macro
/// whose plugin ships only with Xcode, so building with just the Command Line Tools needs this alias.
typealias ViewState<Value> = SwiftUI.State<Value>

struct CellarApp: App {
    @ViewState private var store = BottleStore()

    var body: some Scene {
        WindowGroup("Cellar") {
            ContentView()
                .environment(store)
                .tint(Theme.accent)
                .frame(minWidth: 880, minHeight: 560)
        }
        .defaultSize(width: 1120, height: 740)
    }
}

/// Warm monochrome palette with one wine accent, in light and dark variants.
enum Theme {
    static let canvas = Color(light: 0xF7F6F3, dark: 0x1B1A18)
    static let surface = Color(light: 0xFFFFFF, dark: 0x242321)
    static let surfaceRaised = Color(light: 0xF1F0EC, dark: 0x2C2B28)
    static let ink = Color(light: 0x161513, dark: 0xF1EFEA)
    static let inkMuted = Color(light: 0x7A7772, dark: 0x9C9993)
    static let hairline = Color(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.08, darkAlpha: 0.10)
    static let accent = Color(light: 0x7D2E3C, dark: 0xD07A8A)
    static let accentPale = Color(light: 0xF6E8EA, dark: 0x3B2429)
    static let okPale = Color(light: 0xE9F1E8, dark: 0x22311F)
    static let ok = Color(light: 0x346538, dark: 0x8FC98F)

    static let cornerSmall: CGFloat = 6
    static let corner: CGFloat = 10
}

extension Color {
    /// A color that follows the window's light or dark appearance.
    init(light: UInt32, dark: UInt32, lightAlpha: Double = 1, darkAlpha: Double = 1) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light, alpha: isDark ? darkAlpha : lightAlpha)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: Double) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension Font {
    /// Serif display face for names and sheet titles.
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .medium, design: .serif) }
    /// Monospace for technical details: engine, renderer, sizes.
    static let meta = Font.system(size: 12, weight: .regular, design: .monospaced)
    /// Small tracked label for section headers.
    static let label = Font.system(size: 11, weight: .semibold)
}

/// Solid ink button for the one main action on a screen.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.canvas)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Theme.ink.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Hairline-bordered button for secondary actions.
struct QuietButtonStyle: ButtonStyle {
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(destructive ? Theme.accent : Theme.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(configuration.isPressed ? Theme.surfaceRaised : Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous).strokeBorder(Theme.hairline))
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
