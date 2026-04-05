//
//  BadgeTierVisual.swift
//  Venture Local
//

import SwiftUI

enum BadgeTierVisual {
    /// Tier metal / gem accent (same in light and dark vintage).
    static func accent(for tier: BadgeTier) -> Color {
        switch tier {
        case .copper:
            Color(red: 0.72, green: 0.42, blue: 0.22)
        case .silver:
            Color(red: 0.72, green: 0.74, blue: 0.78)
        case .gold:
            Color(red: 0.91, green: 0.72, blue: 0.18)
        case .platinum:
            Color(red: 0.72, green: 0.88, blue: 0.95)
        case .special:
            Color(red: 0.62, green: 0.48, blue: 0.88)
        }
    }

    static func mutedAccent(for tier: BadgeTier) -> Color {
        accent(for: tier).opacity(0.55)
    }

    // MARK: - Theme-aware badge surfaces & type

    private static let darkCardBase = Color(red: 0.078, green: 0.10, blue: 0.082)
    private static let lightCardBase = Color(red: 0.97, green: 0.94, blue: 0.89)

    /// Copper unlocked: metal / peach wash; locked matches silver–gold (panel shows section background through base).
    static func compactGridCardFill(for tier: BadgeTier, isUnlocked: Bool, useDarkVintage: Bool) -> Color {
        switch tier {
        case .copper:
            if isUnlocked {
                if useDarkVintage {
                    return Color(red: 0.50, green: 0.31, blue: 0.195)
                }
                return Color(red: 0.94, green: 0.87, blue: 0.78)
            }
            return useDarkVintage ? darkCardBase.opacity(0.96) : lightCardBase.opacity(0.98)
        case .silver:
            if isUnlocked {
                return Color(red: 0.72, green: 0.74, blue: 0.78).opacity(useDarkVintage ? 0.20 : 0.22)
            }
            return useDarkVintage ? darkCardBase.opacity(0.96) : lightCardBase.opacity(0.98)
        case .gold:
            if isUnlocked {
                return Color(red: 0.91, green: 0.72, blue: 0.18).opacity(useDarkVintage ? 0.16 : 0.14)
            }
            return useDarkVintage ? darkCardBase.opacity(0.96) : lightCardBase.opacity(0.98)
        case .platinum, .special:
            return useDarkVintage ? darkCardBase.opacity(0.96) : lightCardBase.opacity(0.98)
        }
    }

    static func fullWidthBadgeCardFill(for tier: BadgeTier, isUnlocked: Bool, useDarkVintage: Bool) -> Color {
        switch tier {
        case .platinum, .special:
            if isUnlocked {
                return accent(for: tier).opacity(useDarkVintage ? 0.14 : 0.11)
            }
            return useDarkVintage ? darkCardBase.opacity(0.96) : lightCardBase.opacity(0.98)
        default:
            return compactGridCardFill(for: tier, isUnlocked: isUnlocked, useDarkVintage: useDarkVintage)
        }
    }

    /// Primary copy on badge cards: light in dark vintage, dark in light vintage; locked is lower opacity.
    static func badgePrimaryLabel(useDarkVintage: Bool, isUnlocked: Bool) -> Color {
        let full = useDarkVintage
            ? Color(red: 0.93, green: 0.96, blue: 0.91)
            : Color(red: 0.11, green: 0.10, blue: 0.09)
        return full.opacity(isUnlocked ? 1 : 0.66)
    }

    static func badgeSecondaryLabel(useDarkVintage: Bool, isUnlocked: Bool) -> Color {
        let full = useDarkVintage
            ? Color(red: 0.74, green: 0.82, blue: 0.72)
            : Color(red: 0.32, green: 0.30, blue: 0.27)
        return full.opacity(isUnlocked ? 1 : 0.70)
    }

    static func badgeTertiaryLabel(useDarkVintage: Bool, isUnlocked: Bool) -> Color {
        let full = useDarkVintage
            ? Color(red: 0.62, green: 0.72, blue: 0.60)
            : Color(red: 0.44, green: 0.42, blue: 0.39)
        return full.opacity(isUnlocked ? 1 : 0.72)
    }

    /// XP row and tier-colored highlights (same unlocked/locked contrast pattern).
    static func badgeTierHighlight(tier: BadgeTier, useDarkVintage: Bool, isUnlocked: Bool) -> Color {
        let base = accent(for: tier)
        let hi = useDarkVintage ? (isUnlocked ? 0.92 : 0.52) : (isUnlocked ? 0.88 : 0.46)
        return base.opacity(hi)
    }

    static func badgeFootnoteLabel(useDarkVintage: Bool) -> Color {
        useDarkVintage
            ? Color(red: 0.68, green: 0.80, blue: 0.70)
            : Color(red: 0.36, green: 0.44, blue: 0.50)
    }

    static func badgeLockGlyph(useDarkVintage: Bool) -> Color {
        useDarkVintage
            ? Color(red: 0.78, green: 0.88, blue: 0.72)
            : Color(red: 0.38, green: 0.46, blue: 0.54)
    }

    static func badgeLockGlyphBackdrop(useDarkVintage: Bool) -> Color {
        useDarkVintage ? Color.black.opacity(0.28) : Color.white.opacity(0.55)
    }

    static func badgeStatusPillForeground(useDarkVintage: Bool) -> Color {
        useDarkVintage
            ? Color(red: 0.94, green: 0.97, blue: 0.92)
            : Color(red: 0.12, green: 0.11, blue: 0.10)
    }

    static func badgeStatusPillBackground(tier: BadgeTier, useDarkVintage: Bool) -> Color {
        if useDarkVintage {
            return Color.black.opacity(0.32)
        }
        return accent(for: tier).opacity(0.20)
    }

    /// Uses two columns for these tiers.
    static func usesCompactGrid(_ tier: BadgeTier) -> Bool {
        switch tier {
        case .copper, .silver, .gold: true
        case .platinum, .special: false
        }
    }
}

/// Side flourishes for a badge row; intricacy scales with tier.
struct BadgeTierLaurels: View {
    let tier: BadgeTier
    /// `true` = grid cell (copper–gold); `false` = full-width platinum/special.
    var compact: Bool

    var body: some View {
        let accent = BadgeTierVisual.accent(for: tier)
        HStack(spacing: compact ? 1 : 6) {
            leadingCluster(accent: accent)
            Spacer(minLength: 0)
            trailingCluster(accent: accent)
        }
    }

    @ViewBuilder
    private func leadingCluster(accent: Color) -> some View {
        switch tier {
        case .copper:
            Image(systemName: "leaf.fill")
                .font(compact ? .system(size: 9) : .caption)
                .foregroundStyle(accent.opacity(0.85))
                .rotationEffect(.degrees(-28))
        case .silver:
            HStack(spacing: 0) {
                Image(systemName: "laurel.leading")
                    .font(compact ? .system(size: 10, weight: .medium) : .callout)
                    .foregroundStyle(accent)
            }
        case .gold:
            HStack(spacing: compact ? 1 : 2) {
                Image(systemName: "laurel.leading")
                    .font(compact ? .system(size: 10, weight: .medium) : .callout)
                    .foregroundStyle(accent)
                Image(systemName: "star.fill")
                    .font(.system(size: compact ? 6 : 9))
                    .foregroundStyle(accent.opacity(0.95))
            }
        case .platinum:
            HStack(spacing: 3) {
                Image(systemName: "sparkle")
                    .font(compact ? .caption2 : .caption)
                    .foregroundStyle(accent)
                Image(systemName: "laurel.leading")
                    .font(compact ? .caption : .title3)
                    .foregroundStyle(accent)
                Image(systemName: "sparkle")
                    .font(.system(size: compact ? 8 : 11))
                    .foregroundStyle(accent.opacity(0.9))
            }
        case .special:
            HStack(spacing: 2) {
                Image(systemName: "sparkles")
                    .font(compact ? .caption2 : .caption)
                    .foregroundStyle(accent)
                Image(systemName: "laurel.leading")
                    .font(compact ? .caption : .title3)
                    .foregroundStyle(accent)
                Image(systemName: "star.circle.fill")
                    .font(compact ? .caption2 : .body)
                    .foregroundStyle(accent.opacity(0.95))
                Image(systemName: "laurel.trailing")
                    .font(compact ? .caption : .title3)
                    .foregroundStyle(accent)
                Image(systemName: "sparkles")
                    .font(compact ? .caption2 : .caption)
                    .foregroundStyle(accent)
            }
        }
    }

    @ViewBuilder
    private func trailingCluster(accent: Color) -> some View {
        switch tier {
        case .copper:
            Image(systemName: "leaf.fill")
                .font(compact ? .system(size: 9) : .caption)
                .foregroundStyle(accent.opacity(0.85))
                .rotationEffect(.degrees(28))
                .scaleEffect(x: -1, y: 1)
        case .silver:
            Image(systemName: "laurel.trailing")
                .font(compact ? .system(size: 10, weight: .medium) : .callout)
                .foregroundStyle(accent)
        case .gold:
            HStack(spacing: compact ? 1 : 2) {
                Image(systemName: "star.fill")
                    .font(.system(size: compact ? 6 : 9))
                    .foregroundStyle(accent.opacity(0.95))
                Image(systemName: "laurel.trailing")
                    .font(compact ? .system(size: 10, weight: .medium) : .callout)
                    .foregroundStyle(accent)
            }
        case .platinum:
            HStack(spacing: 3) {
                Image(systemName: "sparkle")
                    .font(.system(size: compact ? 8 : 11))
                    .foregroundStyle(accent.opacity(0.9))
                Image(systemName: "laurel.trailing")
                    .font(compact ? .caption : .title3)
                    .foregroundStyle(accent)
                Image(systemName: "crown.fill")
                    .font(compact ? .caption2 : .subheadline)
                    .foregroundStyle(accent.opacity(0.95))
            }
        case .special:
            HStack(spacing: 2) {
                Image(systemName: "star.circle.fill")
                    .font(compact ? .caption2 : .body)
                    .foregroundStyle(accent.opacity(0.95))
                Image(systemName: "laurel.trailing")
                    .font(compact ? .caption : .title3)
                    .foregroundStyle(accent)
                Image(systemName: "sun.max.fill")
                    .font(compact ? .caption2 : .callout)
                    .foregroundStyle(accent)
            }
        }
    }
}

/// Optional crown row above full-width elite badges.
struct BadgeEliteCrownRow: View {
    let tier: BadgeTier

    var body: some View {
        let accent = BadgeTierVisual.accent(for: tier)
        switch tier {
        case .platinum:
            HStack(spacing: 10) {
                Image(systemName: "sparkle")
                    .foregroundStyle(accent.opacity(0.85))
                Image(systemName: "crown.fill")
                    .font(.title3)
                    .foregroundStyle(accent)
                Image(systemName: "sparkle")
                    .foregroundStyle(accent.opacity(0.85))
            }
        case .special:
            HStack(spacing: 8) {
                Image(systemName: "sun.max.fill")
                    .foregroundStyle(accent.opacity(0.9))
                Image(systemName: "crown.fill")
                    .font(.title2)
                    .foregroundStyle(accent)
                Image(systemName: "sun.max.fill")
                    .foregroundStyle(accent.opacity(0.9))
            }
        default:
            EmptyView()
        }
    }
}
