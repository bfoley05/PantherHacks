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

    private var cityKey: String? {
        exploration.currentCityKey
    }

    private var visiblePOIs: [CachedPOI] {
        guard let cityKey else { return [] }
        return cachedPOIs.filter { $0.cityKey == cityKey }
    }

    private var discoveredIDs: Set<String> {
        Set(discoveries.map(\.osmId))
    }

    var body: some View {
        ZStack {
            Map(position: $position) {
                UserAnnotation()
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
            .mapStyle(.standard(elevation: .flat, emphasis: .muted))
            .onMapCameraChange(frequency: .onEnd) { ctx in
                Task {
                    await exploration.syncRegion(ctx.region)
                }
            }

            Rectangle()
                .fill(VLColor.parchmentFog)
                .allowsHitTesting(false)

            VStack {
                HStack {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        if exploration.isSyncingPOIs || exploration.isSyncingRoads {
                            ProgressView()
                                .tint(VLColor.mutedGold)
                                .padding(8)
                                .background(VLColor.cream.opacity(0.85))
                                .clipShape(Circle())
                        }
                    }
                    .padding()
                }
                Spacer()
                HStack(spacing: 12) {
                    ornateButton(symbol: "location.north.circle") {
                        recenter()
                    }
                }
                .padding(.bottom, 28)
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
        .alert("Explorer note", isPresented: Binding(get: { exploration.lastErrorMessage != nil }, set: { if !$0 { exploration.lastErrorMessage = nil } })) {
            Button("OK", role: .cancel) { exploration.lastErrorMessage = nil }
        } message: {
            Text(exploration.lastErrorMessage ?? "")
        }
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
