//
//  ExplorationMapView.swift
//  Venture Local
//
//  Vintage “fog” is a parchment tint over the map; revealed road segments draw as gold ink trails.
//

import CoreLocation
import MapKit
import SwiftData
import SwiftUI

struct ExplorationMapView: View {
    @Bindable var exploration: ExplorationCoordinator

    @Query(sort: \CachedPOI.name) private var cachedPOIs: [CachedPOI]
    @Query private var discoveries: [DiscoveredPlace]

    @State private var position: MapCameraPosition = .automatic
    @State private var selectedPOI: CachedPOI?
    @State private var showPOISheet = false
    /// Only one category is shown at a time (reduces map lag).
    @State private var mapCategoryFilter: DiscoveryCategory = .food

    private var cityKey: String? {
        exploration.currentCityKey
    }

    private var visiblePOIs: [CachedPOI] {
        guard let cityKey else { return [] }
        return cachedPOIs.filter {
            $0.cityKey == cityKey
                && DiscoveryCategory(rawValue: $0.categoryRaw) == mapCategoryFilter
                && !POISyncService.isUnwantedPOIName($0.name)
        }
    }

    private var discoveredIDs: Set<String> {
        Set(discoveries.map(\.osmId))
    }

    var body: some View {
        ZStack {
            // Match tab/chrome so safe areas aren’t a different color than the map stack.
            VLColor.cream
                .ignoresSafeArea()

            Map(position: $position) {
                UserAnnotation()
                ForEach(Array(exploration.cityBoundaryMapRings.enumerated()), id: \.offset) { _, ring in
                    MapPolygon(coordinates: ring)
                        .foregroundStyle(VLColor.mutedGold.opacity(0.06))
                        .stroke(VLColor.burgundy, lineWidth: 2.5)
                }
                ForEach(Array(exploration.revealedSegmentCoordinates.enumerated()), id: \.offset) { _, seg in
                    MapPolyline(coordinates: seg)
                        .stroke(VLColor.mutedGold, lineWidth: 5)
                }
                ForEach(visiblePOIs, id: \.osmId) { poi in
                    let coord = CLLocationCoordinate2D(latitude: poi.latitude, longitude: poi.longitude)
                    Annotation(poi.name, coordinate: coord) {
                        Button {
                            selectedPOI = poi
                            showPOISheet = true
                        } label: {
                            POIMapGlyph(poi: poi, discovered: discoveredIDs.contains(poi.osmId))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
            .onMapCameraChange(frequency: .onEnd) { ctx in
                Task {
                    await exploration.syncRegion(ctx.region)
                }
            }

            Rectangle()
                .fill(VLColor.parchmentFog)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                if let hint = exploration.mapHint {
                    Text(hint)
                        .font(.vlCaption(12))
                        .foregroundStyle(VLColor.burgundy)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(VLColor.cream.opacity(0.92))
                }
                if let name = exploration.currentCityDisplayName {
                    HStack(spacing: 6) {
                        Image(systemName: "building.columns.fill")
                            .font(.caption)
                        Text(name)
                            .font(.vlCaption(12))
                        if exploration.isLoadingCityBoundary {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                    }
                    .foregroundStyle(VLColor.darkTeal)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(VLColor.cream.opacity(0.88))
                }
                mapCategoryFilterBar
                HStack {
                    Spacer()
                    if exploration.isSyncingPOIs || exploration.isSyncingRoads {
                        ProgressView()
                            .tint(VLColor.mutedGold)
                            .padding(8)
                            .background(VLColor.cream.opacity(0.85))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal)
                .padding(.top, exploration.mapHint == nil ? 8 : 4)
                Spacer()
                HStack(spacing: 12) {
                    ornateButton(symbol: "location.north.circle") {
                        recenter()
                    }
                }
                .padding(.bottom, 12)
            }
        }
        .sheet(isPresented: $showPOISheet, onDismiss: { selectedPOI = nil }) {
            if let poi = selectedPOI {
                POIDetailView(poi: poi, exploration: exploration)
                    .presentationDetents([.medium, .large])
            }
        }
        .onAppear {
            exploration.requestWhenInUse()
            exploration.startTracking()
            try? exploration.loadPersistedPolylinesIntoMap()
            if let loc = exploration.locationManager.location {
                position = .region(MKCoordinateRegion(center: loc.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)))
            }
        }
    }

    private var mapCategoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DiscoveryCategory.allCases) { cat in
                    mapCategoryChip(title: cat.displayName, symbol: cat.symbol, selected: mapCategoryFilter == cat) {
                        mapCategoryFilter = cat
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(VLColor.cream.opacity(0.92))
    }

    private func mapCategoryChip(title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.caption2)
                Text(title)
                    .font(.vlCaption(11))
            }
            .foregroundStyle(selected ? VLColor.cream : VLColor.darkTeal)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(selected ? VLColor.burgundy : VLColor.cream)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(selected ? VLColor.mutedGold.opacity(0.6) : VLColor.burgundy.opacity(0.25), lineWidth: selected ? 2 : 1)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func ornateButton(symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(VLColor.cream)
                .padding(12)
                .background(VLColor.burgundy)
                .clipShape(Circle())
                .overlay(Circle().stroke(VLColor.mutedGold, lineWidth: 2))
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        }
        .accessibilityLabel(Text(symbol))
    }

    private func recenter() {
        guard let c = exploration.lastUserLocation?.coordinate ?? exploration.locationManager.location?.coordinate else { return }
        withAnimation {
            position = .region(MKCoordinateRegion(center: c, span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)))
        }
    }
}

private struct POIMapGlyph: View {
    let poi: CachedPOI
    var discovered: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(discovered ? VLColor.darkTeal.opacity(0.9) : VLColor.mutedGold.opacity(0.55))
                .frame(width: 28, height: 28)
                .overlay(Circle().stroke(VLColor.burgundy, lineWidth: 1.5))
            if let cat = DiscoveryCategory(rawValue: poi.categoryRaw) {
                Image(systemName: cat.symbol)
                    .font(.caption)
                    .foregroundStyle(VLColor.cream)
            } else {
                Image(systemName: "mappin")
                    .font(.caption)
                    .foregroundStyle(VLColor.cream)
            }
            if poi.isPartner {
                Image(systemName: "seal.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(VLColor.mutedGold)
                    .offset(x: 12, y: -12)
            }
        }
    }
}
