//
//  StampTier.swift
//  Venture Local
//
//  Passport stamp outline rank from total scans at a partner.
//

import SwiftUI

enum StampTier: String, CaseIterable {
    case bronze
    case silver
    case gold
    case platinum
    case diamond
    case emerald

    /// 1 bronze · 3 silver · 5 gold · 10 platinum · 15 diamond · 20+ emerald
    static func tier(forTotalScans count: Int) -> StampTier? {
        guard count > 0 else { return nil }
        if count >= 20 { return .emerald }
        if count >= 15 { return .diamond }
        if count >= 10 { return .platinum }
        if count >= 5 { return .gold }
        if count >= 3 { return .silver }
        return .bronze
    }

    var title: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }

    var outlineColors: [Color] {
        switch self {
        case .bronze:
            return [Color(red: 0.72, green: 0.45, blue: 0.20)]
        case .silver:
            return [Color(red: 0.72, green: 0.74, blue: 0.78)]
        case .gold:
            return [Color(red: 0.85, green: 0.65, blue: 0.13)]
        case .platinum:
            return [Color(red: 0.88, green: 0.91, blue: 0.94), Color(red: 0.65, green: 0.78, blue: 0.92)]
        case .diamond:
            return [Color(red: 0.55, green: 0.82, blue: 0.98), Color(red: 0.92, green: 0.95, blue: 1.0)]
        case .emerald:
            return [
                Color(red: 0.45, green: 0.12, blue: 0.65),
                Color(red: 0.05, green: 0.72, blue: 0.52),
            ]
        }
    }

    var lineWidth: CGFloat {
        switch self {
        case .bronze, .silver: return 3
        case .gold, .platinum: return 3.5
        case .diamond: return 4
        case .emerald: return 4.5
        }
    }

    var usesEmeraldAura: Bool { self == .emerald }
    var usesDiamondEffects: Bool { self == .diamond }
    var usesPlatinumEffects: Bool { self == .platinum }
}
