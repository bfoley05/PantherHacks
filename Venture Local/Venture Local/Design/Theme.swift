//
//  Theme.swift
//  Venture Local
//

import Combine
import SwiftUI

final class ThemeSettings: ObservableObject {
    static let shared = ThemeSettings()

    private let storageKey = "useDarkVintagePalette"

    @Published var useDarkVintagePalette: Bool {
        didSet {
            UserDefaults.standard.set(useDarkVintagePalette, forKey: storageKey)
        }
    }

    private init() {
        self.useDarkVintagePalette = UserDefaults.standard.object(forKey: storageKey) as? Bool ?? false
    }

    /// Solid screen backdrop; matches `VLColor.paperBackground` but reads the observed theme so SwiftUI updates on toggle.
    var paperBackdropColor: Color {
        useDarkVintagePalette
            ? Color(red: 0x09 / 255, green: 0x0E / 255, blue: 0x0B / 255)
            : Color(red: 0xF5 / 255, green: 0xE9 / 255, blue: 0xD3 / 255)
    }
}

/// Vintage palette colors. These read ``ThemeSettings/shared``, which SwiftUI does **not** track automatically.
/// Any screen that uses `VLColor` should declare `@EnvironmentObject private var theme: ThemeSettings`
/// and read `theme.useDarkVintagePalette` in `body` (for example `let _ = theme.useDarkVintagePalette`)
/// so toggling the palette invalidates that view and refreshes icons and text.
enum VLColor {
    private static var darkVintage: Bool { ThemeSettings.shared.useDarkVintagePalette }

    static var burgundy: Color {
        darkVintage
            ? Color(red: 0x3A / 255, green: 0xB8 / 255, blue: 0x58 / 255)
            : Color(red: 0x7B / 255, green: 0x2D / 255, blue: 0x26 / 255)
    }

    static var darkTeal: Color {
        darkVintage
            ? Color(red: 0xD7 / 255, green: 0xE8 / 255, blue: 0xD0 / 255)
            : Color(red: 0x2E / 255, green: 0x5E / 255, blue: 0x5A / 255)
    }

    static var cream: Color {
        darkVintage
            ? Color(red: 0xE7 / 255, green: 0xDE / 255, blue: 0xC7 / 255)
            : Color(red: 0xF5 / 255, green: 0xE9 / 255, blue: 0xD3 / 255)
    }

    static var mutedGold: Color {
        darkVintage
            ? Color(red: 0x9C / 255, green: 0xD4 / 255, blue: 0x8B / 255)
            : Color(red: 0xC8 / 255, green: 0x9B / 255, blue: 0x3C / 255)
    }

    static var dustyBlue: Color {
        darkVintage
            ? Color(red: 0x9F / 255, green: 0xB7 / 255, blue: 0xA1 / 255)
            : Color(red: 0x8F / 255, green: 0xA9 / 255, blue: 0xBF / 255)
    }

    static var parchmentFog: Color {
        darkVintage
            ? Color(red: 0x02 / 255, green: 0x08 / 255, blue: 0x05 / 255).opacity(0.46)
            : Color(red: 0x4A / 255, green: 0x38 / 255, blue: 0x2A / 255).opacity(0.35)
    }

    static var paperBackground: Color {
        darkVintage
            ? Color(red: 0x09 / 255, green: 0x0E / 255, blue: 0x0B / 255)
            : cream
    }

    static var paperSurface: Color {
        darkVintage
            ? Color(red: 0x14 / 255, green: 0x1A / 255, blue: 0x15 / 255)
            : cream
    }

    /// Ledger cards and panels (not text on burgundy — use `cream` for that).
    static var cardBackground: Color {
        darkVintage ? paperSurface : cream
    }

    /// Area behind the map (safe zones, tab alignment).
    static var mapSafeAreaFill: Color {
        darkVintage ? paperBackground : cream
    }

    /// Floating bars on the map (hints, city chip, category strip).
    static var mapOverlayBar: Color {
        darkVintage
            ? Color(red: 0x14 / 255, green: 0x1A / 255, blue: 0x15 / 255).opacity(0.96)
            : cream.opacity(0.92)
    }

    /// Unselected category chip on map.
    static var mapChipIdleFill: Color {
        darkVintage ? paperSurface : cream
    }

    /// Passport stamp tile “paper” center.
    static var stampMatte: Color {
        darkVintage
            ? Color(red: 0x22 / 255, green: 0x2C / 255, blue: 0x26 / 255)
            : Color(red: 0xFA / 255, green: 0xF3 / 255, blue: 0xE8 / 255)
    }

    /// Grouped city section behind stamp grid.
    static var passportCityPanel: Color {
        darkVintage ? paperSurface : cream.opacity(0.65)
    }

    /// Outer frame around each stamp tile.
    static var stampTileOuter: Color {
        darkVintage ? paperSurface.opacity(0.97) : cream.opacity(0.9)
    }

    static var ink: Color {
        darkVintage
            ? Color(red: 0xE5 / 255, green: 0xEE / 255, blue: 0xE0 / 255)
            : Color.black
    }

    static var subtleInk: Color {
        darkVintage
            ? Color(red: 0xA5 / 255, green: 0xB5 / 255, blue: 0xA3 / 255)
            : Color.black.opacity(0.55)
    }

    // MARK: - Profile actions (light vs dark vintage)

    /// Primary fill for the sign-out control (destructive, readable on both palettes).
    static var profileSignOutFill: Color {
        darkVintage
            ? Color(red: 0xC4 / 255, green: 0x3E / 255, blue: 0x4E / 255)
            : Color(red: 0x9E / 255, green: 0x2A / 255, blue: 0x36 / 255)
    }

    static var profileSignOutLabel: Color {
        darkVintage
            ? Color(red: 0xFF / 255, green: 0xFA / 255, blue: 0xF7 / 255)
            : cream
    }

    static var profileSignOutBorder: Color {
        darkVintage
            ? Color(red: 0xFF / 255, green: 0x8A / 255, blue: 0x95 / 255).opacity(0.45)
            : Color(red: 0x5C / 255, green: 0x18 / 255, blue: 0x22 / 255).opacity(0.55)
    }

    /// Friends & requests — distinct green in each palette.
    static var profileFriendsFill: Color {
        darkVintage
            ? Color(red: 0x2F / 255, green: 0x8F / 255, blue: 0x5C / 255)
            : Color(red: 0x2A / 255, green: 0x72 / 255, blue: 0x4A / 255)
    }

    static var profileFriendsLabel: Color {
        darkVintage
            ? Color(red: 0xF2 / 255, green: 0xFB / 255, blue: 0xF4 / 255)
            : cream
    }

    static var profileFriendsBorder: Color {
        darkVintage
            ? Color(red: 0x9C / 255, green: 0xD4 / 255, blue: 0x8B / 255).opacity(0.55)
            : Color(red: 0x1F / 255, green: 0x4D / 255, blue: 0x32 / 255).opacity(0.45)
    }
}

extension Font {
    static func vlTitle(_ size: CGFloat = 28) -> Font {
        .system(size: size, weight: .semibold, design: .serif)
    }

    static func vlBody(_ size: CGFloat = 16) -> Font {
        .system(size: size, weight: .regular, design: .default)
    }

    static func vlCaption(_ size: CGFloat = 13) -> Font {
        .system(size: size, weight: .medium, design: .monospaced)
    }
}

// MARK: - Screen backdrop

/// Flat fill using the same palette as cards and nav chrome (no texture).
struct PaperBackground: View {
    @EnvironmentObject private var theme: ThemeSettings

    var body: some View {
        theme.paperBackdropColor
            .ignoresSafeArea()
    }
}

/// Matches `PaperBackground` and sets navigation bar material so large titles stay legible.
struct VintageNavigationChromeModifier: ViewModifier {
    @EnvironmentObject private var theme: ThemeSettings

    func body(content: Content) -> some View {
        let _ = theme.useDarkVintagePalette
        let bar = theme.paperBackdropColor
        content
            // Large titles reserve a tall empty band under the status bar; tab roots use a compact bar like the Map tab.
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(bar, for: .navigationBar)
            .toolbarColorScheme(theme.useDarkVintagePalette ? .dark : .light, for: .navigationBar)
    }
}

extension View {
    func vintageNavigationChrome() -> some View {
        modifier(VintageNavigationChromeModifier())
    }
}
