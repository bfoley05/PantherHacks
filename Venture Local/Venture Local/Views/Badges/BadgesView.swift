//
//  BadgesView.swift
//  Venture Local
//

import SwiftData
import SwiftUI

struct BadgesView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var theme: ThemeSettings
    @Bindable var exploration: ExplorationCoordinator

    @Query private var profiles: [ExplorerProfile]
    @Query(sort: \BadgeUnlock.unlockedAt, order: .reverse) private var unlocked: [BadgeUnlock]
    @Query private var discoveries: [DiscoveredPlace]
    @Query private var pois: [CachedPOI]
    @Query private var stamps: [StampRecord]
    @Query(sort: \ExplorerEvent.occurredAt, order: .reverse) private var explorerEvents: [ExplorerEvent]
    @Query private var savedPlaces: [SavedPlace]
    @Query private var favorites: [FavoritePlace]
    @Query private var photoCheckIns: [PlacePhotoCheckIn]

    /// `nil` shows every tier; a value shows only that tier’s badges.
    @State private var selectedListTier: BadgeTier?

    private var profile: ExplorerProfile? { profiles.first }
    private var unlockedCodes: Set<String> { Set(unlocked.map(\.code)) }

    private var badgeDataRevision: Int {
        [discoveries.count, stamps.count, explorerEvents.count, savedPlaces.count, favorites.count, photoCheckIns.count, pois.count]
            .reduce(0) { $0 &* 31 &+ $1 }
    }

    private var gridColumns: [GridItem] {
        [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
    }

    var body: some View {
        let _ = theme.useDarkVintagePalette
        return badgeScroll
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                if let p = profiles.first {
                    p.badgesScreenVisitCount = (p.badgesScreenVisitCount ?? 0) + 1
                    try? modelContext.save()
                }
                evaluateBadges()
            }
            .onChange(of: badgeDataRevision) { _, _ in evaluateBadges() }
    }

    private var badgeScroll: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                LazyVStack(spacing: 14, pinnedViews: [.sectionHeaders]) {
                    Section {
                        header
                    }
                    Section {
                        ForEach(visibleTiers) { tier in
                            tierSection(tier)
                        }
                    } header: {
                        tierFilterBar
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(VLColor.paperSurface)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                // Lazy stacks can reuse cells; force refresh when palette flips so fills/labels stay in sync.
                .id(theme.useDarkVintagePalette)
            }
            .scrollContentBackground(.hidden)
        }
    }

    private func tierSection(_ tier: BadgeTier) -> some View {
        let badges = BadgeCatalog.badges(for: tier)
        let done = badges.filter { unlockedCodes.contains($0.code) }.count
        let accent = BadgeTierVisual.accent(for: tier)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(tier.title) Badges")
                    .font(.vlTitle(20))
                    .foregroundStyle(accent)
                Spacer(minLength: 8)
                Text("\(done) / \(badges.count) unlocked")
                    .font(.vlCaption(12))
                    .foregroundStyle(VLColor.dustyBlue)
            }

            if BadgeTierVisual.usesCompactGrid(tier) {
                LazyVGrid(columns: gridColumns, spacing: 8) {
                    ForEach(badges) { badge in
                        let u = unlockedCodes.contains(badge.code)
                        BadgeGridCellView(
                            badge: badge,
                            tier: tier,
                            isUnlocked: u,
                            footnote: footnoteIfNeeded(badge: badge, unlocked: u),
                            requirementLine: requirementDisplay(badge: badge, unlocked: u)
                        )
                    }
                }
            } else {
                VStack(spacing: 10) {
                    ForEach(badges) { badge in
                        let u = unlockedCodes.contains(badge.code)
                        BadgeFullCellView(
                            badge: badge,
                            tier: tier,
                            isUnlocked: u,
                            footnote: footnoteIfNeeded(badge: badge, unlocked: u),
                            requirementLine: requirementDisplay(badge: badge, unlocked: u)
                        )
                    }
                }
            }
        }
        .padding(12)
        .background(VLColor.paperSurface.opacity(0.92))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(accent.opacity(0.38), lineWidth: 1.5))
        .cornerRadius(12)
    }

    private func requirementDisplay(badge: BadgeDefinition, unlocked: Bool) -> String {
        if !unlocked && badge.obscuresRequirementWhenLocked { return "???" }
        return badge.requirement
    }

    private func footnoteIfNeeded(badge: BadgeDefinition, unlocked: Bool) -> String? {
        guard !unlocked, !badge.isTrackableNow else { return nil }
        return trackabilityFootnote(for: badge)
    }

    private var visibleTiers: [BadgeTier] {
        if let t = selectedListTier { return [t] }
        return Array(BadgeTier.allCases)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Badge Journal")
                .font(.vlTitle(24))
                .foregroundStyle(VLColor.burgundy)
            Text("Badges grant XP when unlocked. Use the tier bar to focus one set. Copper–Gold use two columns; Platinum and Special are full width.")
                .font(.vlBody(14))
                .foregroundStyle(VLColor.dustyBlue)
            let total = BadgeCatalog.all.count
            let done = unlocked.count
            Text("\(done) / \(total) unlocked")
                .font(.vlCaption())
                .foregroundStyle(VLColor.darkTeal)
        }
    }

    private var tierFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                tierFilterChip(title: "All", tier: nil)
                ForEach(BadgeTier.allCases) { tier in
                    tierFilterChip(title: tier.title, tier: tier)
                }
            }
            .padding(.vertical, 2)
        }
    }

    /// Tier accents for silver/platinum are light metals; label must stay dark for contrast in any app palette.
    private static let lightMetalChipLabel = Color(red: 0.16, green: 0.14, blue: 0.13)

    private func selectedTierChipLabelColor(tier: BadgeTier?) -> Color {
        guard let tier else { return VLColor.cream }
        switch tier {
        case .silver, .platinum: return Self.lightMetalChipLabel
        default: return VLColor.cream
        }
    }

    private func tierFilterChip(title: String, tier: BadgeTier?) -> some View {
        let selected = tier == nil ? selectedListTier == nil : selectedListTier == tier
        let accent: Color = {
            if let t = tier { return BadgeTierVisual.accent(for: t) }
            return VLColor.burgundy
        }()
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedListTier = tier
            }
        } label: {
            Text(title)
                .font(.vlCaption(12))
                .foregroundStyle(selected ? selectedTierChipLabelColor(tier: tier) : VLColor.darkTeal)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(selected ? accent : VLColor.mapChipIdleFill)
                )
                .overlay(
                    Capsule()
                        .stroke(selected ? accent.opacity(0.95) : VLColor.burgundy.opacity(0.22), lineWidth: selected ? 1.5 : 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func trackabilityFootnote(for badge: BadgeDefinition) -> String {
        switch badge.title {
        case "Rain or Shine":
            return "Needs weather on visit (coming soon)"
        default:
            return "Tracked in a future update"
        }
    }

    private func evaluateBadges() {
        exploration.evaluateBadgesAndLedgerNotifications()
    }
}

// MARK: - Grid cell (Copper / Silver / Gold)

private enum BadgeGridCellLayout {
    /// Fixed content height so every compact badge tile matches in a row (includes 4× `rowSpacing` between 5 blocks).
    static let contentHeight: CGFloat = 132
    static let rowSpacing: CGFloat = 3
    static let headerHeight: CGFloat = 26
    static let titleBlockHeight: CGFloat = 34
    static let requirementBlockHeight: CGFloat = 32
    static let footerBlockHeight: CGFloat = 20
    static let xpRowHeight: CGFloat = 8
    static let cornerRadius: CGFloat = 9
    static let cellPadding: CGFloat = 6
}

private struct BadgeGridCellView: View {
    @EnvironmentObject private var theme: ThemeSettings

    let badge: BadgeDefinition
    let tier: BadgeTier
    let isUnlocked: Bool
    let footnote: String?
    let requirementLine: String

    private var tierColor: Color { BadgeTierVisual.accent(for: tier) }
    private var dark: Bool { theme.useDarkVintagePalette }

    var body: some View {
        VStack(spacing: BadgeGridCellLayout.rowSpacing) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    BadgeTierLaurels(tier: tier, compact: true)
                    Image(systemName: badge.symbol)
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(BadgeTierVisual.badgeTierHighlight(tier: tier, useDarkVintage: dark, isUnlocked: isUnlocked))
                }
                if !isUnlocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(BadgeTierVisual.badgeLockGlyph(useDarkVintage: dark))
                        .padding(3)
                        .background(Circle().fill(BadgeTierVisual.badgeLockGlyphBackdrop(useDarkVintage: dark)))
                }
            }
            .frame(height: BadgeGridCellLayout.headerHeight)

            Text(badge.title)
                .font(.vlCaption(10))
                .foregroundStyle(BadgeTierVisual.badgePrimaryLabel(useDarkVintage: dark, isUnlocked: isUnlocked))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
                .frame(height: BadgeGridCellLayout.titleBlockHeight, alignment: .top)

            Text("+\(badge.xpAward) XP")
                .font(.vlCaption(8))
                .foregroundStyle(BadgeTierVisual.badgeTierHighlight(tier: tier, useDarkVintage: dark, isUnlocked: isUnlocked))
                .frame(height: BadgeGridCellLayout.xpRowHeight)

            Text(requirementLine)
                .font(.vlCaption(7))
                .foregroundStyle(BadgeTierVisual.badgeSecondaryLabel(useDarkVintage: dark, isUnlocked: isUnlocked))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .frame(height: BadgeGridCellLayout.requirementBlockHeight, alignment: .top)

            Group {
                if isUnlocked {
                    Text("Unlocked")
                        .font(.vlCaption(7).weight(.semibold))
                        .foregroundStyle(BadgeTierVisual.badgeStatusPillForeground(useDarkVintage: dark))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(BadgeTierVisual.badgeStatusPillBackground(tier: tier, useDarkVintage: dark)))
                } else if let footnote {
                    Text(footnote)
                        .font(.vlCaption(7))
                        .foregroundStyle(BadgeTierVisual.badgeFootnoteLabel(useDarkVintage: dark))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.68)
                } else {
                    Text("Locked")
                        .font(.vlCaption(7).weight(.medium))
                        .foregroundStyle(BadgeTierVisual.badgeTertiaryLabel(useDarkVintage: dark, isUnlocked: false))
                }
            }
            .frame(height: BadgeGridCellLayout.footerBlockHeight, alignment: .center)
        }
        .frame(maxWidth: .infinity, minHeight: BadgeGridCellLayout.contentHeight, maxHeight: BadgeGridCellLayout.contentHeight, alignment: .top)
        .padding(BadgeGridCellLayout.cellPadding)
        .opacity(isUnlocked ? 1 : 0.9)
        .background(
            RoundedRectangle(cornerRadius: BadgeGridCellLayout.cornerRadius, style: .continuous)
                .fill(BadgeTierVisual.compactGridCardFill(for: tier, isUnlocked: isUnlocked, useDarkVintage: dark))
        )
        .overlay(
            RoundedRectangle(cornerRadius: BadgeGridCellLayout.cornerRadius, style: .continuous)
                .stroke(
                    tierColor.opacity(isUnlocked ? (dark ? 0.62 : 0.50) : (dark ? 0.35 : 0.22)),
                    style: StrokeStyle(lineWidth: isUnlocked ? 1.5 : 1.15, dash: isUnlocked ? [] : [5, 3])
                )
        )
        .accessibilityLabel("\(badge.title), \(tier.title) tier, \(isUnlocked ? "unlocked" : "locked")")
    }
}

// MARK: - Full-width cell (Platinum / Special)

private enum BadgeFullCellLayout {
    /// One height for every platinum/special row so the list doesn’t stagger.
    static let contentHeight: CGFloat = 160
    static let crownHeight: CGFloat = 22
    static let laurelHeight: CGFloat = 18
    static let bodyRowHeight: CGFloat = 108
    static let cornerRadius: CGFloat = 12
    static let cellPadding: CGFloat = 10
}

private struct BadgeFullCellView: View {
    @EnvironmentObject private var theme: ThemeSettings

    let badge: BadgeDefinition
    let tier: BadgeTier
    let isUnlocked: Bool
    let footnote: String?
    let requirementLine: String

    private var tierColor: Color { BadgeTierVisual.accent(for: tier) }
    private var dark: Bool { theme.useDarkVintagePalette }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                BadgeEliteCrownRow(tier: tier)
                    .frame(maxWidth: .infinity)
                    .opacity(isUnlocked ? 1 : 0.5)
                if !isUnlocked {
                    Label("Locked", systemImage: "lock.fill")
                        .font(.vlCaption(10))
                        .foregroundStyle(BadgeTierVisual.badgeTertiaryLabel(useDarkVintage: dark, isUnlocked: false))
                }
            }
            .frame(height: BadgeFullCellLayout.crownHeight)

            BadgeTierLaurels(tier: tier, compact: false)
                .padding(.horizontal, 4)
                .opacity(isUnlocked ? 1 : 0.55)
                .frame(height: BadgeFullCellLayout.laurelHeight)

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: badge.symbol)
                    .font(.title3)
                    .foregroundStyle(BadgeTierVisual.badgeTierHighlight(tier: tier, useDarkVintage: dark, isUnlocked: isUnlocked))
                    .frame(width: 30, alignment: .top)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(badge.title)
                            .font(.vlBody(15))
                            .foregroundStyle(BadgeTierVisual.badgePrimaryLabel(useDarkVintage: dark, isUnlocked: isUnlocked))
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                        Spacer(minLength: 6)
                        Text("+\(badge.xpAward) XP")
                            .font(.vlCaption(10))
                            .foregroundStyle(BadgeTierVisual.badgeTierHighlight(tier: tier, useDarkVintage: dark, isUnlocked: isUnlocked))
                    }
                    .frame(height: 36, alignment: .top)

                    Text(requirementLine)
                        .font(.vlCaption(11))
                        .foregroundStyle(BadgeTierVisual.badgeSecondaryLabel(useDarkVintage: dark, isUnlocked: isUnlocked))
                        .lineLimit(3)
                        .minimumScaleFactor(0.82)
                        .frame(height: 42, alignment: .top)

                    Spacer(minLength: 0)

                    if isUnlocked {
                        Text("Unlocked")
                            .font(.vlCaption(10).weight(.semibold))
                            .foregroundStyle(BadgeTierVisual.badgeStatusPillForeground(useDarkVintage: dark))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(BadgeTierVisual.badgeStatusPillBackground(tier: tier, useDarkVintage: dark)))
                    } else if let footnote {
                        Text(footnote)
                            .font(.vlCaption(10))
                            .foregroundStyle(BadgeTierVisual.badgeFootnoteLabel(useDarkVintage: dark))
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, minHeight: BadgeFullCellLayout.bodyRowHeight, maxHeight: BadgeFullCellLayout.bodyRowHeight, alignment: .top)
        }
        .frame(maxWidth: .infinity, minHeight: BadgeFullCellLayout.contentHeight, maxHeight: BadgeFullCellLayout.contentHeight, alignment: .top)
        .padding(BadgeFullCellLayout.cellPadding)
        .opacity(isUnlocked ? 1 : 0.92)
        .background(
            RoundedRectangle(cornerRadius: BadgeFullCellLayout.cornerRadius, style: .continuous)
                .fill(BadgeTierVisual.fullWidthBadgeCardFill(for: tier, isUnlocked: isUnlocked, useDarkVintage: dark))
        )
        .overlay(
            RoundedRectangle(cornerRadius: BadgeFullCellLayout.cornerRadius, style: .continuous)
                .stroke(
                    isUnlocked
                        ? AnyShapeStyle(
                            LinearGradient(
                                colors: [
                                    tierColor.opacity(dark ? 0.82 : 0.72),
                                    tierColor.opacity(dark ? 0.40 : 0.32),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        : AnyShapeStyle(tierColor.opacity(dark ? 0.30 : 0.24)),
                    style: StrokeStyle(lineWidth: isUnlocked ? 1.85 : 1.15, dash: isUnlocked ? [] : [6, 4])
                )
        )
        .accessibilityLabel("\(badge.title), \(tier.title) tier, \(isUnlocked ? "unlocked" : "locked")")
    }
}
