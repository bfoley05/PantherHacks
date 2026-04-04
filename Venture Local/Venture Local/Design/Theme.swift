//
//  Theme.swift
//  Venture Local
//

import SwiftUI

enum VLColor {
    static let burgundy = Color(red: 0x7B / 255, green: 0x2D / 255, blue: 0x26 / 255)
    static let darkTeal = Color(red: 0x2E / 255, green: 0x5E / 255, blue: 0x5A / 255)
    static let cream = Color(red: 0xF5 / 255, green: 0xE9 / 255, blue: 0xD3 / 255)
    static let mutedGold = Color(red: 0xC8 / 255, green: 0x9B / 255, blue: 0x3C / 255)
    static let dustyBlue = Color(red: 0x8F / 255, green: 0xA9 / 255, blue: 0xBF / 255)
    static let parchmentFog = Color(red: 0x4A / 255, green: 0x38 / 255, blue: 0x2A / 255).opacity(0.35)
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

struct PaperBackground: View {
    var body: some View {
        VLColor.cream
            .ignoresSafeArea()
    }
}
