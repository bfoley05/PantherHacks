//
//  JournalCityViews.swift
//  Venture Local
//

import SwiftData
import SwiftUI

/// Choose which city the journal completion ring follows, and drill into visits per city.
struct JournalCityHubView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var theme: ThemeSettings
    @Bindable var profile: ExplorerProfile
    @Query private var discoveries: [DiscoveredPlace]

    private var discoveredCityKeys: [String] {
        Array(Set(discoveries.map(\.cityKey))).sorted()
    }

    private var followingGPS: Bool {
        profile.pinnedExplorationCityKey == nil || profile.pinnedExplorationCityKey?.isEmpty == true
    }

    var body: some View {
        let _ = theme.useDarkVintagePalette
        ZStack {
            PaperBackground()
            List {
                Section {
                    Button {
                        profile.pinnedExplorationCityKey = nil
                        try? modelContext.save()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Follow my location")
                                    .font(.vlBody(16))
                                    .foregroundStyle(VLColor.ink)
                                Text("Journal stats match where you are now")
                                    .font(.vlCaption(12))
                                    .foregroundStyle(VLColor.dustyBlue)
                            }
                            Spacer()
                            if followingGPS {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(VLColor.darkTeal)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(VLColor.paperSurface.opacity(0.92))
                } header: {
                    Text("Journal city")
                        .font(.vlCaption())
                        .foregroundStyle(VLColor.dustyBlue)
                } footer: {
                    Text("Pick a city below to see every place you’ve visited there, or set it as the journal focus.")
                        .font(.vlCaption(11))
                        .foregroundStyle(VLColor.subtleInk)
                }

                Section {
                    if discoveredCityKeys.isEmpty {
                        Text("Discover places on the map to see cities here.")
                            .font(.vlBody(14))
                            .foregroundStyle(VLColor.dustyBlue)
                            .listRowBackground(VLColor.paperSurface.opacity(0.92))
                    } else {
                        ForEach(discoveredCityKeys, id: \.self) { key in
                            NavigationLink {
                                DiscoveredPlacesInCityView(cityKey: key, profile: profile)
                                    .environmentObject(theme)
                            } label: {
                                HStack {
                                    Text(CityKey.displayLabel(for: key))
                                        .font(.vlBody(16))
                                        .foregroundStyle(VLColor.ink)
                                    Spacer()
                                    if profile.pinnedExplorationCityKey == key {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(VLColor.burgundy)
                                    }
                                }
                            }
                            .contextMenu {
                                Button("Use for journal") {
                                    profile.pinnedExplorationCityKey = key
                                    try? modelContext.save()
                                }
                            }
                            .listRowBackground(VLColor.paperSurface.opacity(0.92))
                        }
                    }
                } header: {
                    Text("Cities you’ve explored")
                        .font(.vlCaption())
                        .foregroundStyle(VLColor.dustyBlue)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Journal & cities")
        .navigationBarTitleDisplayMode(.inline)
        .vintageNavigationChrome()
    }
}

struct DiscoveredPlacesInCityView: View {
    let cityKey: String
    @Bindable var profile: ExplorerProfile
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var theme: ThemeSettings
    @Query(sort: \DiscoveredPlace.discoveredAt, order: .reverse) private var allDiscoveries: [DiscoveredPlace]
    @Query private var pois: [CachedPOI]

    private var poiById: [String: CachedPOI] {
        Dictionary(uniqueKeysWithValues: pois.map { ($0.osmId, $0) })
    }

    private var cityDiscoveries: [DiscoveredPlace] {
        allDiscoveries.filter { $0.cityKey == cityKey }
    }

    private var isJournalCity: Bool {
        profile.pinnedExplorationCityKey == cityKey
    }

    private var sections: [(title: String, items: [DiscoveredPlace])] {
        var buckets: [DiscoveryCategory: [DiscoveredPlace]] = [:]
        var other: [DiscoveredPlace] = []
        for d in cityDiscoveries {
            guard let poi = poiById[d.osmId] else {
                other.append(d)
                continue
            }
            if let cat = DiscoveryCategory(rawValue: poi.categoryRaw) {
                buckets[cat, default: []].append(d)
            } else {
                other.append(d)
            }
        }
        var rows: [(String, [DiscoveredPlace])] = []
        for cat in DiscoveryCategory.allCases {
            if let items = buckets[cat], !items.isEmpty {
                rows.append((cat.displayName, items))
            }
        }
        if !other.isEmpty {
            rows.append(("Other", other))
        }
        return rows
    }

    var body: some View {
        let _ = theme.useDarkVintagePalette
        ZStack {
            PaperBackground()
            Group {
                if cityDiscoveries.isEmpty {
                    ContentUnavailableView(
                        "No visits in this city",
                        systemImage: "map",
                        description: Text("Discoveries for this city will appear here.")
                    )
                    .foregroundStyle(VLColor.ink)
                } else {
                    List {
                        Section {
                            if isJournalCity {
                                Label("Journal is set to this city", systemImage: "checkmark.circle.fill")
                                    .font(.vlBody(15))
                                    .foregroundStyle(VLColor.darkTeal)
                            } else {
                                Button {
                                    profile.pinnedExplorationCityKey = cityKey
                                    try? modelContext.save()
                                } label: {
                                    Text("Use this city for journal")
                                        .font(.vlBody(16).weight(.semibold))
                                        .foregroundStyle(VLColor.cream)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(VLColor.burgundy)
                                        .cornerRadius(10)
                                }
                                .buttonStyle(.plain)
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            }
                        }
                        .listRowBackground(Color.clear)

                        ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                            Section {
                                ForEach(section.items, id: \.osmId) { visit in
                                    discoveryRow(visit)
                                }
                            } header: {
                                Text(section.title)
                                    .font(.vlCaption())
                                    .foregroundStyle(VLColor.dustyBlue)
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .navigationTitle(CityKey.displayLabel(for: cityKey))
        .navigationBarTitleDisplayMode(.inline)
        .vintageNavigationChrome()
    }

    private func discoveryRow(_ visit: DiscoveredPlace) -> some View {
        let poi = poiById[visit.osmId]
        let cat = DiscoveryCategory(rawValue: poi?.categoryRaw ?? "")
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: cat?.symbol ?? "mappin.circle.fill")
                .font(.body)
                .foregroundStyle(VLColor.mutedGold)
                .frame(width: 28, alignment: .center)
                .padding(.top, 2)
                .accessibilityLabel(cat?.displayName ?? "Place")
            VStack(alignment: .leading, spacing: 4) {
                Text(poi?.name ?? visit.osmId)
                    .font(.vlBody(16))
                    .foregroundStyle(VLColor.ink)
                if let a = poi?.addressSummary, !a.isEmpty {
                    Text(a)
                        .font(.vlCaption(12))
                        .foregroundStyle(VLColor.subtleInk)
                }
                Text("Visited \(visit.discoveredAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.vlCaption(11))
                    .foregroundStyle(VLColor.dustyBlue)
            }
            Spacer(minLength: 0)
        }
        .listRowBackground(VLColor.paperSurface.opacity(0.92))
    }
}
