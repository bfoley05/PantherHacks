//
//  StrideTheme.swift
//  PTApp
//

import SwiftUI

enum StrideTheme {
    static let accent = Color(red: 0.18, green: 0.52, blue: 0.98)
    static let accentDeep = Color(red: 0.10, green: 0.36, blue: 0.78)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let card = Color(uiColor: .systemBackground)
    static let success = Color(red: 0.20, green: 0.78, blue: 0.45)
    static let warning = Color(red: 1.0, green: 0.72, blue: 0.20)
    static let danger = Color(red: 0.95, green: 0.35, blue: 0.35)
    static let streakFire = Color(red: 1.0, green: 0.45, blue: 0.15)

    /// Light appearance (used when user chooses Light in Profile).
    static let gradientBackgroundLight = LinearGradient(
        colors: [
            Color(red: 0.93, green: 0.96, blue: 1.0),
            Color(uiColor: .systemGroupedBackground),
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Default dark appearance.
    static let gradientBackgroundDark = LinearGradient(
        colors: [
            Color(red: 0.05, green: 0.06, blue: 0.09),
            Color(red: 0.09, green: 0.10, blue: 0.14),
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    static func gradientBackground(for colorScheme: ColorScheme) -> LinearGradient {
        colorScheme == .dark ? gradientBackgroundDark : gradientBackgroundLight
    }
}
