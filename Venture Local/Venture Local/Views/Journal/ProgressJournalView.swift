//
//  ProgressJournalView.swift
//  Venture Local
//

import Combine
import SwiftData
import SwiftUI
import UIKit

struct ProgressJournalView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var theme: ThemeSettings
    @EnvironmentObject private var auth: AuthSessionController
    @EnvironmentObject private var tabRouter: MainShellTabRouter
    @Bindable var exploration: ExplorationCoordinator

    /// Switches main tab to Badges (from notification inbox).
    var onSelectBadgesTab: () -> Void
    /// Switches main tab to Journal (level-up notifications).
    var onSelectJournalTab: () -> Void

    @Query private var profiles: [ExplorerProfile]
    @Query(sort: \DiscoveredPlace.discoveredAt, order: .reverse) private var recent: [DiscoveredPlace]
    @Query(filter: #Predicate<LedgerNotification> { $0.isRead == false }) private var unreadLedgerNotifications: [LedgerNotification]

    @State private var snapshot: ProgressStats.CitySnapshot?
    @State private var showProfileEditor = false
    @State private var claimError: String?

    init(
        exploration: ExplorationCoordinator,
        onSelectBadgesTab: @escaping () -> Void,
        onSelectJournalTab: @escaping () -> Void
    ) {
        _exploration = Bindable(exploration)
        self.onSelectBadgesTab = onSelectBadgesTab
        self.onSelectJournalTab = onSelectJournalTab
    }

    private var profile: ExplorerProfile? { profiles.first }
    private var cityKey: String? {
        profile?.effectiveProgressCityKey(liveCityKey: exploration.currentCityKey)
    }

    private var journalCityTitle: String {
        if let pin = profile?.pinnedExplorationCityKey, !pin.isEmpty {
            return CityKey.displayLabel(for: pin)
        }
        if let d = exploration.currentCityDisplayName, !d.isEmpty { return d }
        // Avoid flashing stale profile home/selected until GPS geocode fills `currentCityKey`.
        if exploration.lastUserLocation != nil, exploration.currentCityKey == nil {
            return "Locating your city…"
        }
        if let k = cityKey { return CityKey.displayLabel(for: k) }
        return "Unknown city"
    }

    var body: some View {
        let _ = theme.useDarkVintagePalette
        return ZStack {
            PaperBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .center) {
                        Text("Explorer’s Ledger")
                            .font(.vlTitle(24))
                            .foregroundStyle(VLColor.burgundy)
                        Spacer(minLength: 8)
                        HStack(spacing: 26) {
                            NavigationLink {
                                JournalNotificationsInboxView(
                                    onOpenBadgesTab: onSelectBadgesTab,
                                    onOpenJournalTab: onSelectJournalTab
                                )
                                .environmentObject(theme)
                                .environmentObject(auth)
                            } label: {
                                ZStack(alignment: .topTrailing) {
                                    Image(systemName: "bell.fill")
                                        .font(.system(size: 28, weight: .semibold))
                                        .foregroundStyle(VLColor.burgundy)
                                        .frame(minWidth: 44, minHeight: 44)
                                        .contentShape(Rectangle())
                                        .accessibilityLabel("Notifications")
                                    let n = unreadLedgerNotifications.count
                                    if n > 0 {
                                        Text(n > 99 ? "99+" : "\(n)")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(theme.useDarkVintagePalette ? Color.black : Color.white)
                                            .padding(.horizontal, n > 9 ? 4 : 5)
                                            .padding(.vertical, 2)
                                            .background(theme.useDarkVintagePalette ? VLColor.mutedGold : VLColor.darkTeal)
                                            .clipShape(Capsule())
                                            .offset(x: 12, y: -10)
                                            .accessibilityLabel("\(n) unread notifications")
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            Button {
                                showProfileEditor = true
                            } label: {
                                Image(systemName: "person.crop.circle")
                                    .font(.system(size: 28, weight: .semibold))
                                    .foregroundStyle(VLColor.burgundy)
                                    .frame(minWidth: 44, minHeight: 44)
                                    .contentShape(Rectangle())
                                    .accessibilityLabel("Profile")
                            }
                        }
                    }
                    .padding(.horizontal)

                    if let name = profile?.displayName {
                        Text(name)
                            .font(.vlCaption())
                            .foregroundStyle(VLColor.dustyBlue)
                            .padding(.horizontal)
                    }

                    if exploration.shouldSuggestAlwaysLocationUpgrade {
                        alwaysLocationUpgradeCallout
                    }

                    claimNearbyBanner

                    globalXPBlock

                    cityBlock

                    categorySection

                    recentSection
                }
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
            .scrollContentBackground(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        .containerBackground(theme.paperBackdropColor, for: .navigation)
        .onAppear {
            exploration.refreshNearbyClaimablePOIs()
            exploration.evaluateBadgesAndLedgerNotifications()
            refresh()
        }
        .onChange(of: cityKey ?? "") { _, _ in
            exploration.refreshNearbyClaimablePOIs()
            refresh()
        }
        .onChange(of: profile?.pinnedExplorationCityKey ?? "") { _, _ in
            refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .ventureLocalCityBaselineUpdated)) { _ in
            refresh()
        }
        .alert("Couldn’t claim", isPresented: Binding(get: { claimError != nil }, set: { if !$0 { claimError = nil } })) {
            Button("OK", role: .cancel) { claimError = nil }
        } message: {
            Text(claimError ?? "")
        }
        .fullScreenCover(isPresented: $showProfileEditor) {
            if let p = profiles.first {
                ProfileEditorView(profile: p)
                    .environmentObject(theme)
                    .environmentObject(auth)
                    .environmentObject(tabRouter)
                    .environment(\.explorationCoordinator, exploration)
            }
        }
    }

    private var alwaysLocationUpgradeCallout: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Background exploration")
                .font(.vlCaption())
                .foregroundStyle(VLColor.dustyBlue)
            Text("Location is set to “While Using the App.” Choose Always in Settings so Venture Local can keep surfacing nearby places and city context when the app isn’t open.")
                .font(.vlBody(13))
                .foregroundStyle(VLColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Open Settings")
                    .font(.vlCaption(12).weight(.semibold))
                    .foregroundStyle(VLColor.burgundy)
            }
            .accessibilityHint("Opens the Settings app for Venture Local")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VLColor.cardBackground)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(VLColor.burgundy.opacity(0.28), lineWidth: 1))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    @ViewBuilder
    private var claimNearbyBanner: some View {
        if !exploration.nearbyClaimablePOIs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("You’re near a place")
                    .font(.vlCaption())
                    .foregroundStyle(VLColor.dustyBlue)
                ForEach(exploration.nearbyClaimablePOIs, id: \.osmId) { poi in
                    HStack(alignment: .center, spacing: 12) {
                        let category = DiscoveryCategory(rawValue: poi.categoryRaw)
                        Image(systemName: category?.symbol ?? "mappin.circle.fill")
                            .font(.title2)
                            .foregroundStyle(VLColor.mutedGold)
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(VLColor.cream.opacity(0.14))
                            )
                            .overlay(Circle().stroke(VLColor.mutedGold.opacity(0.35), lineWidth: 1))
                            .accessibilityLabel(category?.displayName ?? "Place")

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Nearby place")
                                .font(.vlCaption(11))
                                .foregroundStyle(VLColor.mutedGold)
                            Text(poi.name)
                                .font(.vlBody(16))
                                .foregroundStyle(VLColor.cream)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Button {
                            do {
                                try exploration.claimPOI(osmId: poi.osmId)
                                refresh()
                            } catch {
                                claimError = error.localizedDescription
                            }
                        } label: {
                            Text("Claim")
                                .font(.vlCaption(12).weight(.semibold))
                                .foregroundStyle(VLColor.burgundy)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(VLColor.cream)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Claim visit at \(poi.name)")
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(VLColor.burgundy)
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(VLColor.mutedGold.opacity(0.5), lineWidth: 2))
                }
            }
            .padding(.horizontal)
        }
    }

    private var globalXPBlock: some View {
        let xp = profile?.totalXP ?? 0
        let level = LevelFormula.level(for: xp)
        let span = LevelFormula.xpIntoCurrentLevel(totalXP: xp)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Global explorer rank")
                .font(.vlCaption())
                .foregroundStyle(VLColor.dustyBlue)
            HStack {
                Text("Level \(level)")
                    .font(.vlTitle(20))
                    .foregroundStyle(VLColor.mutedGold)
                Spacer()
                Text("\(xp) XP")
                    .font(.vlCaption())
                    .foregroundStyle(VLColor.dustyBlue)
            }
            ProgressView(value: Double(span.into), total: Double(max(span.needed, 1)))
                .tint(VLColor.burgundy)
        }
        .padding()
        .background(VLColor.cardBackground)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(VLColor.burgundy.opacity(0.35), lineWidth: 2))
        .cornerRadius(14)
        .padding(.horizontal)
    }

    /// Ring size: smaller than full-width hero, still prominent in the card.
    private var cityCompletionRingDiameter: CGFloat {
        let w = (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.screen.bounds.width) ?? 390
        return max(200, min(w - 72, w * 0.62))
    }

    private var cityBlock: some View {
        VStack(alignment: .center, spacing: 16) {
            Text("City completion (locals)")
                .font(.vlCaption())
                .foregroundStyle(VLColor.dustyBlue)
                .frame(maxWidth: .infinity)

            if let snap = snapshot {
                Text(journalCityTitle)
                    .font(.vlTitle(20))
                    .foregroundStyle(VLColor.darkTeal)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)

                Text("\(snap.localsDiscovered) / \(snap.localsTotal) locals discovered")
                    .font(.vlCaption(13))
                    .foregroundStyle(VLColor.burgundy)

                cityCompletionRing(progress: snap.completion01, diameter: cityCompletionRingDiameter)
                    .frame(maxWidth: .infinity)
            } else {
                Text("Pan the map or enable location to resolve a city and sync places.")
                    .font(.vlBody(14))
                    .foregroundStyle(VLColor.dustyBlue)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .background(VLColor.cardBackground)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(VLColor.dustyBlue.opacity(0.35), lineWidth: 2))
        .cornerRadius(14)
        .padding(.horizontal)
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Categories")
                .font(.vlCaption())
                .foregroundStyle(VLColor.dustyBlue)
                .padding(.horizontal)
            if let snap = snapshot {
                ForEach(DiscoveryCategory.allCases) { cat in
                    let slice = snap.perCategory[cat] ?? .init(discovered: 0, total: 0)
                    HStack {
                        Label(cat.displayName, systemImage: cat.symbol)
                            .font(.vlBody(15))
                            .foregroundStyle(VLColor.burgundy)
                        Spacer()
                        Text("\(slice.discovered)/\(slice.total)")
                            .font(.vlCaption())
                            .foregroundStyle(VLColor.darkTeal)
                    }
                    ProgressView(value: slice.percent01)
                        .tint(VLColor.dustyBlue)
                    Divider().opacity(0.25)
                }
                .padding()
                .background(VLColor.cardBackground)
                .cornerRadius(12)
                .padding(.horizontal)
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent discoveries")
                .font(.vlCaption())
                .foregroundStyle(VLColor.dustyBlue)
                .padding(.horizontal)
            let rows = Array(recent.prefix(10))
            if rows.isEmpty {
                Text("Nothing yet — when you’re within \(ExplorationCoordinator.poiProximityRadiusCopy) of a place, use Claim visit above to log it.")
                    .font(.vlBody(14))
                    .foregroundStyle(VLColor.dustyBlue)
                    .padding(.horizontal)
            } else {
                ForEach(rows, id: \.osmId) { d in
                    HStack {
                        let cat = DiscoveryCategory(rawValue: categoryRaw(for: d.osmId) ?? "")
                        Image(systemName: cat?.symbol ?? "mappin.circle.fill")
                            .font(.body)
                            .foregroundStyle(VLColor.mutedGold)
                            .frame(width: 28, alignment: .center)
                            .accessibilityLabel(cat?.displayName ?? "Place")
                        VStack(alignment: .leading) {
                            Text(title(for: d.osmId))
                                .font(.vlBody(15))
                                .foregroundStyle(VLColor.burgundy)
                            Text(d.discoveredAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.vlCaption(11))
                                .foregroundStyle(VLColor.dustyBlue)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    Divider().opacity(0.2)
                }
                .padding()
                .background(VLColor.cardBackground)
                .cornerRadius(12)
                .padding(.horizontal)
            }
        }
    }

    private func cityCompletionRing(progress: Double, diameter: CGFloat) -> some View {
        let clamped = min(max(progress, 0), 1)
        let pctValue = clamped * 100
        let pctLabel = String(format: "%.2f%%", pctValue)
        let lineWidth = max(12, diameter * 0.055)
        let pctFont = max(22, diameter * 0.14)
        return ZStack {
            Circle()
                .stroke(VLColor.dustyBlue.opacity(0.22), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(VLColor.darkTeal, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(pctLabel)
                .font(.system(size: pctFont, weight: .semibold, design: .serif))
                .foregroundStyle(VLColor.burgundy)
                .minimumScaleFactor(0.65)
                .lineLimit(1)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("City completion \(String(format: "%.2f", pctValue)) percent")
    }

    private func title(for osmId: String) -> String {
        let fd = FetchDescriptor<CachedPOI>(predicate: #Predicate { $0.osmId == osmId })
        return (try? modelContext.fetch(fd).first?.name) ?? osmId
    }

    private func categoryRaw(for osmId: String) -> String? {
        let fd = FetchDescriptor<CachedPOI>(predicate: #Predicate { $0.osmId == osmId })
        return try? modelContext.fetch(fd).first?.categoryRaw
    }

    private func refresh() {
        guard let cityKey else {
            snapshot = nil
            return
        }
        snapshot = try? ProgressStats.citySnapshot(modelContext: modelContext, cityKey: cityKey)
    }
}
