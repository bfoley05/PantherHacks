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
        HStack(spacing: compact ? 2 : 6) {
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
                .font(compact ? .caption2 : .caption)
                .foregroundStyle(accent.opacity(0.85))
                .rotationEffect(.degrees(-28))
        case .silver:
            HStack(spacing: 0) {
                Image(systemName: "laurel.leading")
                    .font(compact ? .caption2 : .callout)
                    .foregroundStyle(accent)
            }
        case .gold:
            HStack(spacing: 2) {
                Image(systemName: "laurel.leading")
                    .font(compact ? .caption2 : .callout)
                    .foregroundStyle(accent)
                Image(systemName: "star.fill")
                    .font(.system(size: compact ? 7 : 9))
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
                .font(compact ? .caption2 : .caption)
                .foregroundStyle(accent.opacity(0.85))
                .rotationEffect(.degrees(28))
                .scaleEffect(x: -1, y: 1)
        case .silver:
            Image(systemName: "laurel.trailing")
                .font(compact ? .caption2 : .callout)
                .foregroundStyle(accent)
        case .gold:
            HStack(spacing: 2) {
                Image(systemName: "star.fill")
                    .font(.system(size: compact ? 7 : 9))
                    .foregroundStyle(accent.opacity(0.95))
                Image(systemName: "laurel.trailing")
                    .font(compact ? .caption2 : .callout)
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
