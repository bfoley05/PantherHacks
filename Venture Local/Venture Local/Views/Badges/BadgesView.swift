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
        [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
    }

    var body: some View {
        let _ = theme.useDarkVintagePalette
        return badgeScroll
            .navigationTitle("Badges")
            .vintageNavigationChrome()
            .onAppear { evaluateBadges() }
            .onChange(of: badgeDataRevision) { _, _ in evaluateBadges() }
    }

    private var badgeScroll: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                LazyVStack(spacing: 18, pinnedViews: [.sectionHeaders]) {
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
                            .background(VLColor.paperBackground)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .scrollContentBackground(.hidden)
        }
    }

    private func tierSection(_ tier: BadgeTier) -> some View {
        let badges = BadgeCatalog.badges(for: tier)
        let done = badges.filter { unlockedCodes.contains($0.code) }.count
        let accent = BadgeTierVisual.accent(for: tier)
        return VStack(alignment: .leading, spacing: 10) {
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
                LazyVGrid(columns: gridColumns, spacing: 10) {
                    ForEach(badges) { badge in
                        let u = unlockedCodes.contains(badge.code)
                        BadgeGridCellView(
                            badge: badge,
                            tier: tier,
                            isUnlocked: u,
                            footnote: footnoteIfNeeded(badge: badge, unlocked: u)
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
                            footnote: footnoteIfNeeded(badge: badge, unlocked: u)
                        )
                    }
                }
            }
        }
        .padding(14)
        .background(VLColor.paperSurface.opacity(0.92))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(accent.opacity(0.38), lineWidth: 1.5))
        .cornerRadius(14)
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
        case "Friend Recommendation", "Bring a Friend", "Community Leader":
            return "Needs social / online (Phase C)"
        case "Local Legend":
            return "Needs social, completion, and badges endgame (Phase C)"
        case "Hidden Door":
            return "Needs popularity signal (deferred)"
        case "Trail Creator":
            return "Needs shared custom trails (Phase C)"
        case "Local Circle", "Local Supporter":
            return "Needs more partner-location visits"
        case "Community Champion", "Quest Master":
            return "Needs events / quests backend (Phase C)"
        case "City Ambassador":
            return "Needs submissions pipeline (Phase C)"
        case "Business Bestie":
            return "Needs monthly visit history (Phase C)"
        case "Master Explorer":
            return "Needs 100% city completion + challenges (Phase C)"
        default:
            return "Tracked in a future update"
        }
    }

    private func evaluateBadges() {
        exploration.evaluateBadgesAndLedgerNotifications()
    }
}

// MARK: - Grid cell (Copper / Silver / Gold)

private struct BadgeGridCellView: View {
    let badge: BadgeDefinition
    let tier: BadgeTier
    let isUnlocked: Bool
    let footnote: String?

    var body: some View {
        let tierColor = BadgeTierVisual.accent(for: tier)
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    BadgeTierLaurels(tier: tier, compact: true)
                    Image(systemName: badge.symbol)
                        .font(.title2)
                        .foregroundStyle(isUnlocked ? tierColor : tierColor.opacity(0.35))
                }
                if !isUnlocked {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(VLColor.subtleInk)
                        .padding(4)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
            .frame(height: 38)

            Text(badge.title)
                .font(.vlCaption(12))
                .foregroundStyle(isUnlocked ? VLColor.ink : VLColor.subtleInk.opacity(0.92))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.82)

            Text("+\(badge.xpAward) XP")
                .font(.vlCaption(9))
                .foregroundStyle(isUnlocked ? tierColor.opacity(0.95) : tierColor.opacity(0.45))

            Text(badge.requirement)
                .font(.vlCaption(9))
                .foregroundStyle(isUnlocked ? VLColor.subtleInk : VLColor.subtleInk.opacity(0.75))
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .minimumScaleFactor(0.78)

            if isUnlocked {
                Text("Unlocked")
                    .font(.vlCaption(9).weight(.semibold))
                    .foregroundStyle(tierColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(tierColor.opacity(0.2)))
            } else if let footnote {
                Text(footnote)
                    .font(.vlCaption(8))
                    .foregroundStyle(VLColor.dustyBlue)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.72)
            } else {
                Text("Locked")
                    .font(.vlCaption(9).weight(.medium))
                    .foregroundStyle(VLColor.subtleInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(10)
        .opacity(isUnlocked ? 1 : 0.88)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isUnlocked ? tierColor.opacity(0.14) : VLColor.paperBackground.opacity(0.42))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    tierColor.opacity(isUnlocked ? 0.55 : 0.2),
                    style: StrokeStyle(lineWidth: isUnlocked ? 1.5 : 1.15, dash: isUnlocked ? [] : [5, 3])
                )
        )
        .accessibilityLabel("\(badge.title), \(tier.title) tier, \(isUnlocked ? "unlocked" : "locked")")
    }
}

// MARK: - Full-width cell (Platinum / Special)

private struct BadgeFullCellView: View {
    let badge: BadgeDefinition
    let tier: BadgeTier
    let isUnlocked: Bool
    let footnote: String?

    var body: some View {
        let tierColor = BadgeTierVisual.accent(for: tier)
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                BadgeEliteCrownRow(tier: tier)
                    .frame(maxWidth: .infinity)
                    .opacity(isUnlocked ? 1 : 0.5)
                if !isUnlocked {
                    Label("Locked", systemImage: "lock.fill")
                        .font(.vlCaption(10))
                        .foregroundStyle(VLColor.subtleInk)
                }
            }

            BadgeTierLaurels(tier: tier, compact: false)
                .padding(.horizontal, 4)
                .opacity(isUnlocked ? 1 : 0.55)

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: badge.symbol)
                    .font(.title2)
                    .foregroundStyle(isUnlocked ? tierColor : tierColor.opacity(0.36))
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(badge.title)
                            .font(.vlBody(16))
                            .foregroundStyle(isUnlocked ? VLColor.ink : VLColor.subtleInk.opacity(0.92))
                        Spacer(minLength: 8)
                        Text("+\(badge.xpAward) XP")
                            .font(.vlCaption(11))
                            .foregroundStyle(isUnlocked ? tierColor : tierColor.opacity(0.45))
                    }

                    Text(badge.requirement)
                        .font(.vlCaption(12))
                        .foregroundStyle(isUnlocked ? VLColor.subtleInk : VLColor.subtleInk.opacity(0.78))

                    if isUnlocked {
                        Text("Unlocked")
                            .font(.vlCaption(11).weight(.semibold))
                            .foregroundStyle(tierColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(tierColor.opacity(0.22)))
                    } else if let footnote {
                        Text(footnote)
                            .font(.vlCaption(11))
                            .foregroundStyle(VLColor.dustyBlue)
                    }
                }
            }
        }
        .padding(14)
        .opacity(isUnlocked ? 1 : 0.9)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isUnlocked ? tierColor.opacity(0.12) : VLColor.paperBackground.opacity(0.48))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    isUnlocked
                        ? AnyShapeStyle(
                            LinearGradient(
                                colors: [tierColor.opacity(0.8), tierColor.opacity(0.38)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        : AnyShapeStyle(tierColor.opacity(0.22)),
                    style: StrokeStyle(lineWidth: isUnlocked ? 1.85 : 1.15, dash: isUnlocked ? [] : [6, 4])
                )
        )
        .accessibilityLabel("\(badge.title), \(tier.title) tier, \(isUnlocked ? "unlocked" : "locked")")
    }
}
