//
//  FavoritesListView.swift
//  Venture Local
//

import SwiftData
import SwiftUI

struct FavoritesListView: View {
    @EnvironmentObject private var theme: ThemeSettings
    @EnvironmentObject private var tabRouter: MainShellTabRouter
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FavoritePlace.favoritedAt, order: .reverse) private var favorites: [FavoritePlace]
    @Query private var pois: [CachedPOI]

    private var poiById: [String: CachedPOI] {
        Dictionary(uniqueKeysWithValues: pois.map { ($0.osmId, $0) })
    }

    private func category(for favorite: FavoritePlace) -> DiscoveryCategory? {
        guard let raw = poiById[favorite.osmId]?.categoryRaw else { return nil }
        return DiscoveryCategory(rawValue: raw)
    }

    private var sections: [(title: String, items: [FavoritePlace])] {
        var buckets: [DiscoveryCategory: [FavoritePlace]] = [:]
        var other: [FavoritePlace] = []
        for f in favorites {
            if let c = category(for: f) {
                buckets[c, default: []].append(f)
            } else {
                other.append(f)
            }
        }
        var rows: [(String, [FavoritePlace])] = []
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
                if favorites.isEmpty {
                    ContentUnavailableView(
                        "No favorites yet",
                        systemImage: "heart",
                        description: Text("Tap the heart on a place’s detail screen to save it here.")
                    )
                    .foregroundStyle(VLColor.ink)
                } else {
                    List {
                        ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                            Section {
                                ForEach(section.items, id: \.osmId) { fav in
                                    favoriteRowButton(fav)
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
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .vintageNavigationChrome()
    }

    private func resolvedPOI(for fav: FavoritePlace) -> CachedPOI? {
        if let p = poiById[fav.osmId] { return p }
        let osm = fav.osmId
        let fd = FetchDescriptor<CachedPOI>(predicate: #Predicate { $0.osmId == osm })
        return try? modelContext.fetch(fd).first
    }

    private func favoriteRowButton(_ fav: FavoritePlace) -> some View {
        let poi = resolvedPOI(for: fav)
        let canOpen = poi != nil
        return Button {
            guard let p = poi else { return }
            tabRouter.focusPlaceOnMap(
                MainShellTabRouter.PendingMapPlace(
                    osmId: p.osmId,
                    cityKey: p.cityKey,
                    name: p.name,
                    latitude: p.latitude,
                    longitude: p.longitude
                )
            )
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "heart.fill")
                    .font(.body)
                    .foregroundStyle(VLColor.burgundy)
                    .frame(width: 28, alignment: .center)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(poi?.name ?? "Unknown place")
                        .font(.vlBody(16))
                        .foregroundStyle(VLColor.ink)
                        .multilineTextAlignment(.leading)
                    if let a = poi?.addressSummary, !a.isEmpty {
                        Text(a)
                            .font(.vlCaption(12))
                            .foregroundStyle(VLColor.subtleInk)
                    }
                    Text("Saved \(fav.favoritedAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.vlCaption(11))
                        .foregroundStyle(VLColor.dustyBlue)
                    if canOpen {
                        Text("Open on map")
                            .font(.vlCaption(11).weight(.medium))
                            .foregroundStyle(VLColor.mutedGold)
                    } else {
                        Text("Place isn’t cached — open the map in that city to reload, then try again.")
                            .font(.vlCaption(11))
                            .foregroundStyle(VLColor.dustyBlue)
                    }
                }
                Spacer(minLength: 0)
                if canOpen {
                    Image(systemName: "map")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(VLColor.darkTeal.opacity(0.9))
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canOpen)
        .opacity(canOpen ? 1 : 0.55)
        .listRowBackground(VLColor.paperSurface.opacity(0.92))
        .accessibilityLabel("\(poi?.name ?? "Unknown place"), favorite")
        .accessibilityHint(canOpen ? "Switches to the map tab and opens this place." : "Place details are not available offline.")
    }
}
