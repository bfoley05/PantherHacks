//
//  ProgressJournalView.swift
//  Venture Local
//

import SwiftData
import SwiftUI
import UIKit

struct ProgressJournalView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var exploration: ExplorationCoordinator

    @Query private var profiles: [ExplorerProfile]
    @Query(sort: \DiscoveredPlace.discoveredAt, order: .reverse) private var recent: [DiscoveredPlace]

    @State private var snapshot: ProgressStats.CitySnapshot?
    @State private var segmentCount: Int = 0
    @State private var showProfileEditor = false
    @State private var claimError: String?

    private var profile: ExplorerProfile? { profiles.first }
    private var cityKey: String? { exploration.currentCityKey ?? profile?.selectedCityKey }

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .center) {
                        Text("Explorer’s Ledger")
                            .font(.vlTitle(24))
                            .foregroundStyle(VLColor.burgundy)
                        Spacer(minLength: 8)
                        Button {
                            showProfileEditor = true
                        } label: {
                            Image(systemName: "person.crop.circle")
                                .font(.title2)
                                .foregroundStyle(VLColor.burgundy)
                                .accessibilityLabel("Profile")
                        }
                    }
                    .padding(.horizontal)

                    if let name = profile?.displayName {
                        Text(name)
                            .font(.vlCaption())
                            .foregroundStyle(VLColor.dustyBlue)
                            .padding(.horizontal)
                    }

                    claimNearbyBanner

                    globalXPBlock

                    cityBlock

                    categorySection

                    recentSection
                }
                .padding(.vertical, 20)
            }
        }
        .onAppear {
            exploration.refreshNearbyClaimablePOIs()
            refresh()
        }
        .onChange(of: cityKey ?? "") { _, _ in
            exploration.refreshNearbyClaimablePOIs()
            refresh()
        }
        .alert("Couldn’t claim", isPresented: Binding(get: { claimError != nil }, set: { if !$0 { claimError = nil } })) {
            Button("OK", role: .cancel) { claimError = nil }
        } message: {
            Text(claimError ?? "")
        }
        .sheet(isPresented: $showProfileEditor) {
            if let p = profiles.first {
                ProfileEditorView(profile: p)
                    .presentationDetents([.medium])
            }
        }
    }

    @ViewBuilder
    private var claimNearbyBanner: some View {
        if !exploration.nearbyClaimablePOIs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("You’re near a place")
                    .font(.vlCaption())
                    .foregroundStyle(VLColor.dustyBlue)
                ForEach(exploration.nearbyClaimablePOIs, id: \.osmId) { poi in
                    Button {
                        do {
                            try exploration.claimPOI(osmId: poi.osmId)
                            refresh()
                        } catch {
                            claimError = error.localizedDescription
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Claim visit")
                                    .font(.vlCaption(11))
                                    .foregroundStyle(VLColor.mutedGold)
                                Text(poi.name)
                                    .font(.vlBody(16))
                                    .foregroundStyle(VLColor.cream)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "mappin.and.ellipse")
                                .font(.title2)
                                .foregroundStyle(VLColor.mutedGold)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(VLColor.burgundy)
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(VLColor.mutedGold.opacity(0.5), lineWidth: 2))
                    }
                    .buttonStyle(.plain)
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
            Text("Unique road segments traveled: \(segmentCount)")
                .font(.vlCaption(12))
                .foregroundStyle(VLColor.darkTeal)
        }
        .padding()
        .background(VLColor.cream)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(VLColor.burgundy.opacity(0.35), lineWidth: 2))
        .cornerRadius(14)
        .padding(.horizontal)
    }

    /// Ring size: smaller than full-width hero, still prominent in the card.
    private var cityCompletionRingDiameter: CGFloat {
        let w = UIScreen.main.bounds.width
        return max(200, min(w - 72, w * 0.62))
    }

    private var cityBlock: some View {
        VStack(alignment: .center, spacing: 16) {
            Text("City completion (local businesses)")
                .font(.vlCaption())
                .foregroundStyle(VLColor.dustyBlue)
                .frame(maxWidth: .infinity)

            if let snap = snapshot {
                Text(exploration.currentCityDisplayName ?? cityKey ?? "Unknown city")
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
        .background(VLColor.cream)
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
                .background(VLColor.cream)
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
                Text("Nothing yet — when you’re within \(Int(ExplorationCoordinator.poiProximityRadiusMeters))m of a place, use Claim visit above to log it.")
                    .font(.vlBody(14))
                    .foregroundStyle(VLColor.dustyBlue)
                    .padding(.horizontal)
            } else {
                ForEach(rows, id: \.osmId) { d in
                    HStack {
                        Image(systemName: "sparkle")
                            .foregroundStyle(VLColor.mutedGold)
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
                .background(VLColor.cream)
                .cornerRadius(12)
                .padding(.horizontal)
            }
        }
    }

    private func cityCompletionRing(progress: Double, diameter: CGFloat) -> some View {
        let clamped = min(max(progress, 0), 1)
        let pct = Int((clamped * 100).rounded())
        let lineWidth = max(12, diameter * 0.055)
        let pctFont = max(28, diameter * 0.19)
        return ZStack {
            Circle()
                .stroke(VLColor.dustyBlue.opacity(0.22), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(VLColor.darkTeal, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(pct)%")
                .font(.system(size: pctFont, weight: .semibold, design: .serif))
                .foregroundStyle(VLColor.burgundy)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("City completion \(pct) percent")
    }

    private func title(for osmId: String) -> String {
        let fd = FetchDescriptor<CachedPOI>(predicate: #Predicate { $0.osmId == osmId })
        return (try? modelContext.fetch(fd).first?.name) ?? osmId
    }

    private func refresh() {
        segmentCount = (try? modelContext.fetch(FetchDescriptor<VisitedRoadSegment>()))?.count ?? 0
        guard let cityKey else {
            snapshot = nil
            return
        }
        snapshot = try? ProgressStats.citySnapshot(modelContext: modelContext, cityKey: cityKey)
    }
}
