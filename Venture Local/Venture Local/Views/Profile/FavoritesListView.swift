//
//  FavoritesListView.swift
//  Venture Local
//

import SwiftData
import SwiftUI

struct FavoritesListView: View {
    @EnvironmentObject private var theme: ThemeSettings
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
                                    favoriteRow(fav)
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

    private func favoriteRow(_ fav: FavoritePlace) -> some View {
        let poi = poiById[fav.osmId]
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: "heart.fill")
                .font(.body)
                .foregroundStyle(VLColor.burgundy)
                .frame(width: 28, alignment: .center)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(poi?.name ?? "Unknown place")
                    .font(.vlBody(16))
                    .foregroundStyle(VLColor.ink)
                if let a = poi?.addressSummary, !a.isEmpty {
                    Text(a)
                        .font(.vlCaption(12))
                        .foregroundStyle(VLColor.subtleInk)
                }
                Text("Saved \(fav.favoritedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.vlCaption(11))
                    .foregroundStyle(VLColor.dustyBlue)
            }
            Spacer(minLength: 0)
        }
        .listRowBackground(VLColor.paperSurface.opacity(0.92))
    }
}
