//
//  ProgressJournalView.swift
//  Venture Local
//

import SwiftData
import SwiftUI

struct ProgressJournalView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var exploration: ExplorationCoordinator

    @Query private var profiles: [ExplorerProfile]
    @Query(sort: \DiscoveredPlace.discoveredAt, order: .reverse) private var recent: [DiscoveredPlace]

    @State private var snapshot: ProgressStats.CitySnapshot?
    @State private var segmentCount: Int = 0

    private var profile: ExplorerProfile? { profiles.first }
    private var cityKey: String? { exploration.currentCityKey ?? profile?.selectedCityKey }

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Text("Explorer’s Ledger")
                            .font(.vlTitle(24))
                            .foregroundStyle(VLColor.burgundy)
                        Spacer()
                    }
                    .padding(.horizontal)

                    if let name = profile?.displayName {
                        Text(name)
                            .font(.vlCaption())
                            .foregroundStyle(VLColor.dustyBlue)
                            .padding(.horizontal)
                    }

                    globalXPBlock

                    cityBlock

                    categorySection

                    recentSection
                }
                .padding(.vertical, 20)
            }
        }
        .onAppear {
            refresh()
        }
        .onChange(of: cityKey ?? "") { _, _ in
            refresh()
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

    private var cityBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("City completion (local businesses)")
                .font(.vlCaption())
                .foregroundStyle(VLColor.dustyBlue)
            if let snap = snapshot {
                let pct = Int((snap.completion01 * 100).rounded())
                HStack {
                    Text(exploration.currentCityDisplayName ?? cityKey ?? "Unknown city")
                        .font(.vlTitle(18))
                        .foregroundStyle(VLColor.darkTeal)
                    Spacer()
                    Text("\(pct)%")
                        .font(.vlTitle(18))
                        .foregroundStyle(VLColor.mutedGold)
                }
                ProgressView(value: snap.completion01)
                    .tint(VLColor.darkTeal)
                Text("\(snap.localsDiscovered) / \(snap.localsTotal) locals discovered")
                    .font(.vlCaption(12))
                    .foregroundStyle(VLColor.dustyBlue)
            } else {
                Text("Pan the map or enable location to resolve a city and sync places.")
                    .font(.vlBody(14))
                    .foregroundStyle(VLColor.dustyBlue)
            }
        }
        .padding()
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
                Text("Nothing yet — walk within 10m of a place to discover it.")
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
