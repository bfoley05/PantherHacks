//
//  ExplorationMapView.swift
//  Venture Local
//
//  Place pins use circle + symbol glyphs (road polylines disabled for performance).
//  City limit: `MapPolygon` from `MKPolygon` (with holes) — light fill + outline.
//

import CoreLocation
import MapKit
import SwiftData
import SwiftUI

/// Wraps a `CachedPOI` for `sheet(item:)` so the sheet body always receives that POI (avoids blank sheets when `isPresented` races optional state).
private struct MapPresentedPlace: Identifiable {
    var id: String { poi.osmId }
    let poi: CachedPOI
}

struct ExplorationMapView: View {
    @EnvironmentObject private var theme: ThemeSettings
    @EnvironmentObject private var tabRouter: MainShellTabRouter
    @Environment(\.modelContext) private var modelContext
    @Bindable var exploration: ExplorationCoordinator

    @Query(sort: \CachedPOI.name) private var cachedPOIs: [CachedPOI]
    @Query private var discoveries: [DiscoveredPlace]

    @State private var position: MapCameraPosition = .automatic
    @State private var presentedPlace: MapPresentedPlace?
    /// Only one category is shown at a time (reduces map lag).
    @State private var mapCategoryFilter: DiscoveryCategory = .food
    /// Region when the camera last settled — POIs update from this only so panning matches native MapKit smoothness.
    @State private var overlayAnchorRegion: MKCoordinateRegion?
    /// Latest visible region (updated continuously) so city-boundary stroke can taper when zoomed out.
    @State private var mapRegionForBoundaryStroke: MKCoordinateRegion?
    @State private var renderedPOIs: [CachedPOI] = []
    /// When on, map pins exclude places you’ve already discovered.
    @State private var exploreOnlyUnvisitedPlaces = false
    @AppStorage("mapDistanceUsesMiles") private var mapDistanceUsesMiles = Locale.current.measurementSystem == .us
    /// Only road segments you’ve revealed (no POIs, city outline, or Apple POI clutter).
    @State private var pathTrailsOnlyMode = false
    @State private var mapFogOpacity: Double = 0
    @State private var mapModeTransitionInProgress = false
    @State private var debouncedSyncTask: Task<Void, Never>?
    @StateObject private var mapVoiceTranscriber = MapSpeechTranscriptionController()
    @State private var showMapVoiceAssistant = false
    @State private var voiceSheetPickedPOI: CachedPOI?

    private var cityKey: String? {
        exploration.currentCityKey
    }

    /// Hard cap on map pins for smooth panning/rendering.
    private let maxVisiblePOIAnnotations = 35

    private static let cityBoundaryStrokeMaxPt: CGFloat = 2.5
    private static let cityBoundaryStrokeMinPt: CGFloat = 0.85
    /// Thinner stroke when zoomed out (large span); never above ``cityBoundaryStrokeMaxPt``.
    private static func cityBoundaryStrokeWidth(for region: MKCoordinateRegion?) -> CGFloat {
        guard let r = region else { return cityBoundaryStrokeMaxPt }
        let span = max(max(r.span.latitudeDelta, r.span.longitudeDelta), 0.006)
        let referenceSpan: CGFloat = 0.038
        let w = cityBoundaryStrokeMaxPt * referenceSpan / CGFloat(span)
        return min(cityBoundaryStrokeMaxPt, max(cityBoundaryStrokeMinPt, w))
    }

    /// `MKPolygon` with holes so fill matches OSM (e.g. Villa Park cut out of Orange).
    private static func cityBoundaryMKPolygon(outer: [CLLocationCoordinate2D], holes: [[CLLocationCoordinate2D]]) -> MKPolygon? {
        guard outer.count >= 3 else { return nil }
        let interior = holes.compactMap { hole -> MKPolygon? in
            guard hole.count >= 3 else { return nil }
            return MKPolygon(coordinates: hole, count: hole.count)
        }
        return MKPolygon(coordinates: outer, count: outer.count, interiorPolygons: interior)
    }

    private var discoveredIDs: Set<String> {
        Set(discoveries.map(\.osmId))
    }

    var body: some View {
        let _ = theme.useDarkVintagePalette
        let boundaryOutlineColor = theme.useDarkVintagePalette ? VLColor.mutedGold : VLColor.burgundy
        let boundaryFillColor = boundaryOutlineColor.opacity(0.1)
        let boundaryStrokeWidth = Self.cityBoundaryStrokeWidth(for: mapRegionForBoundaryStroke ?? overlayAnchorRegion)
        let cityBoundaryPolygonsToDraw: [(outer: [CLLocationCoordinate2D], holes: [[CLLocationCoordinate2D]])] = {
            guard !pathTrailsOnlyMode,
                  let ck = exploration.currentCityKey,
                  let bk = exploration.cityBoundaryRingsCityKey,
                  ck == bk,
                  !exploration.cityBoundaryPolygons.isEmpty else { return [] }
            return exploration.cityBoundaryPolygons
        }()
        let pathTrailStroke = theme.useDarkVintagePalette ? VLColor.mutedGold : VLColor.burgundy
        return ZStack {
            // Match other tabs: same paper / geometric backdrop in letterbox areas.
            PaperBackground()

            ZStack {
                Map(position: $position) {
                    UserAnnotation()
                    if pathTrailsOnlyMode {
                        let segments = exploration.revealedSegmentCoordinates
                        ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                            if segment.count >= 2 {
                                MapPolyline(coordinates: segment)
                                    .stroke(pathTrailStroke, lineWidth: 5)
                            }
                        }
                    } else {
                        ForEach(Array(cityBoundaryPolygonsToDraw.enumerated()), id: \.offset) { _, part in
                            if let poly = Self.cityBoundaryMKPolygon(outer: part.outer, holes: part.holes) {
                                MapPolygon(poly)
                                    .foregroundStyle(boundaryFillColor)
                                    .stroke(boundaryOutlineColor, lineWidth: boundaryStrokeWidth)
                            }
                        }
                        ForEach(renderedPOIs, id: \.osmId) { poi in
                            let coord = CLLocationCoordinate2D(latitude: poi.latitude, longitude: poi.longitude)
                            Annotation(poi.name, coordinate: coord) {
                                Button {
                                    presentedPlace = MapPresentedPlace(poi: poi)
                                } label: {
                                    let vis = discoveredIDs.contains(poi.osmId)
                                    POIMapGlyph(poi: poi, discovered: vis)
                                        .id("\(poi.osmId)-discovered:\(vis)")
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Self.placePinAccessibilityLabel(poi))
                                .accessibilityAddTraits(.isButton)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .mapStyle(
                    pathTrailsOnlyMode
                        ? .standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll)
                        : .standard(elevation: .flat, emphasis: .automatic, pointsOfInterest: .excludingAll)
                )

                if mapFogOpacity > 0.02 {
                    MapFogTransitionOverlay(opacity: mapFogOpacity, useDarkVintage: theme.useDarkVintagePalette)
                        .allowsHitTesting(mapFogOpacity > 0.85)
                }
            }
            .onMapCameraChange(frequency: .continuous) { ctx in
                mapRegionForBoundaryStroke = ctx.region
            }
            .onMapCameraChange(frequency: .onEnd) { ctx in
                let region = ctx.region
                overlayAnchorRegion = region
                mapRegionForBoundaryStroke = region
                rebuildMapOverlayCaches()
                debouncedSyncTask?.cancel()
                debouncedSyncTask = Task {
                    do {
                        try await Task.sleep(for: .seconds(1))
                    } catch {
                        return
                    }
                    guard !pathTrailsOnlyMode else { return }
                    await exploration.syncRegion(region)
                }
            }

            VStack(spacing: 0) {
                if let hint = exploration.mapHint {
                    Text(hint)
                        .font(.vlCaption(12))
                        .foregroundStyle(VLColor.burgundy)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(VLColor.mapOverlayBar)
                } else if exploration.isSyncingPOIs || exploration.isSyncingRoads {
                    Text("Updating map data…")
                        .font(.vlCaption(11))
                        .foregroundStyle(VLColor.darkTeal)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(VLColor.mapOverlayBar)
                }
                if let name = exploration.currentCityDisplayName, !pathTrailsOnlyMode {
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
                    .background(VLColor.mapOverlayBar)
                }
                if pathTrailsOnlyMode {
                    Text("Your path")
                        .font(.vlCaption(12).weight(.semibold))
                        .foregroundStyle(VLColor.darkTeal)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(VLColor.mapOverlayBar)
                }
                if !pathTrailsOnlyMode {
                    mapCategoryFilterBar
                    exploreModeToggleBar
                }
                HStack {
                    Spacer()
                    if exploration.isSyncingPOIs || exploration.isSyncingRoads {
                        ProgressView()
                            .tint(VLColor.mutedGold)
                            .padding(8)
                            .background(VLColor.mapOverlayBar)
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal)
                .padding(.top, exploration.mapHint == nil ? 8 : 4)
                Spacer()
                HStack(alignment: .bottom, spacing: 12) {
                    pathTrailsMapToggleButton
                    Spacer()
                    mapVoiceAssistantButton
                    Spacer()
                    ornateButton(symbol: "location.north.circle") {
                        recenter()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .sheet(item: $presentedPlace) { item in
            POIDetailView(poi: item.poi, exploration: exploration)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showMapVoiceAssistant, onDismiss: {
            mapVoiceTranscriber.stopListening()
            if let poi = voiceSheetPickedPOI {
                voiceSheetPickedPOI = nil
                focusMapOn(poi: poi)
                presentedPlace = MapPresentedPlace(poi: poi)
            }
        }) {
            if let ck = cityKey {
                MapVoiceAssistantSheet(
                    transcriber: mapVoiceTranscriber,
                    cityKey: ck,
                    exploration: exploration,
                    cachedPOIs: cachedPOIs,
                    referenceLocation: mapVoiceReferenceLocation,
                    distanceUsesMiles: mapDistanceUsesMiles,
                    exploreOnlyUnvisited: exploreOnlyUnvisitedPlaces,
                    discoveredOsmIds: discoveredIDs,
                    onSelectPlace: { voiceSheetPickedPOI = $0 }
                )
                .presentationDetents([.medium, .large])
            }
        }
        .onAppear {
            if exploration.locationAuthorizationStatus == .notDetermined {
                exploration.requestExplorationLocationAccess()
            }
            exploration.startTracking()
            try? exploration.loadPersistedPolylinesIntoMap()
            if let loc = exploration.locationManager.location {
                let span = MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
                let reg = MKCoordinateRegion(center: loc.coordinate, span: span)
                position = .region(reg)
                overlayAnchorRegion = reg
            }
            rebuildMapOverlayCaches()
        }
        .onChange(of: mapCategoryFilter) { _, _ in rebuildMapOverlayCaches() }
        .onChange(of: exploreOnlyUnvisitedPlaces) { _, _ in rebuildMapOverlayCaches() }
        .onChange(of: exploration.currentCityKey ?? "") { _, _ in rebuildMapOverlayCaches() }
        .onChange(of: discoveries.count) { _, _ in rebuildMapOverlayCaches() }
        .onChange(of: cachedPOIs.count) { _, _ in rebuildMapOverlayCaches() }
        .onChange(of: exploration.isSyncingPOIs) { _, syncing in
            if !syncing { rebuildMapOverlayCaches() }
        }
        .onChange(of: tabRouter.mapFocusGeneration) { _, _ in
            guard let place = tabRouter.pendingMapPlace else { return }
            openPlaceFromSocialDeepLink(place)
        }
        .onDisappear {
            debouncedSyncTask?.cancel()
            debouncedSyncTask = nil
        }
    }

    private var mapVoiceReferenceLocation: CLLocation? {
        if let u = exploration.lastUserLocation { return u }
        if let l = exploration.locationManager.location { return l }
        if let c = overlayAnchorRegion?.center {
            return CLLocation(latitude: c.latitude, longitude: c.longitude)
        }
        return nil
    }

    private var mapVoiceAssistantButton: some View {
        Button {
            mapVoiceTranscriber.resetTranscript()
            showMapVoiceAssistant = true
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.title3.weight(.semibold))
                .foregroundStyle(VLColor.cream)
                .padding(12)
                .background(VLColor.burgundy)
                .clipShape(Circle())
                .overlay(Circle().stroke(VLColor.mutedGold, lineWidth: 2))
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search places")
        .disabled(pathTrailsOnlyMode || cityKey == nil)
        .opacity((pathTrailsOnlyMode || cityKey == nil) ? 0.45 : 1)
    }

    private var pathTrailsMapToggleButton: some View {
        Button {
            runPathExploreModeTransition(toPathTrailsOnly: !pathTrailsOnlyMode)
        } label: {
            Image(systemName: pathTrailsOnlyMode ? "map.fill" : "point.topleft.down.curvedto.point.bottomright.up.fill")
                .font(.title3)
                .foregroundStyle(VLColor.cream)
                .padding(12)
                .background(VLColor.burgundy)
                .clipShape(Circle())
                .overlay(Circle().stroke(VLColor.mutedGold, lineWidth: 2))
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(mapModeTransitionInProgress)
        .opacity(mapModeTransitionInProgress ? 0.55 : 1)
        .accessibilityLabel(pathTrailsOnlyMode ? "Show explore map with places" : "Show only roads you’ve traveled")
    }

    private func runPathExploreModeTransition(toPathTrailsOnly: Bool) {
        guard !mapModeTransitionInProgress else { return }
        mapModeTransitionInProgress = true
        withAnimation(.easeIn(duration: 0.32)) {
            mapFogOpacity = 1
        }
        Task { @MainActor in
            let t0 = Date()
            if toPathTrailsOnly {
                try? exploration.loadPersistedPolylinesIntoMap()
            }
            let elapsed = Date().timeIntervalSince(t0)
            if elapsed < 1 {
                try? await Task.sleep(nanoseconds: UInt64((1 - elapsed) * 1_000_000_000))
            }
            pathTrailsOnlyMode = toPathTrailsOnly
            withAnimation(.easeOut(duration: 0.55)) {
                mapFogOpacity = 0
            }
            try? await Task.sleep(nanoseconds: 600_000_000)
            mapModeTransitionInProgress = false
        }
    }

    private static func placePinAccessibilityLabel(_ poi: CachedPOI) -> String {
        let chips = PlaceExploreFlavorTags.displayChips(for: poi)
        if chips.isEmpty { return poi.name }
        return "\(poi.name). Badge hints: \(chips.joined(separator: ", "))"
    }

    /// Rebuilds the POI annotation list — call when camera settles or data/filters change, not every frame while panning.
    private func rebuildMapOverlayCaches() {
        guard let cityKey else {
            renderedPOIs = []
            return
        }
        let region = overlayAnchorRegion
        let categoryMatches = cachedPOIs.filter {
            $0.cityKey == cityKey
                && DiscoveryCategory(rawValue: $0.categoryRaw) == mapCategoryFilter
                && !POISyncService.isUnwantedPOIName($0.name)
                && !exploration.shouldHideChainFromDiscoveryMap($0)
        }
        let base = exploreOnlyUnvisitedPlaces
            ? categoryMatches.filter { !discoveredIDs.contains($0.osmId) }
            : categoryMatches
        let inView: [CachedPOI] = {
            guard let region else { return base }
            return base.filter { MapViewportFilter.poi($0, isInside: region) }
        }()
        let fallbackCenter = exploration.lastUserLocation?.coordinate
            ?? exploration.locationManager.location?.coordinate
            ?? region?.center
            ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let dedupedInView = POISyncService.dedupeCachedPOIsForMapDisplay(inView)
        renderedPOIs = MapAnnotationCap.cappedPOIs(
            dedupedInView,
            maxCount: maxVisiblePOIAnnotations,
            region: region,
            fallbackCenter: fallbackCenter
        )
    }

    private var exploreModeToggleBar: some View {
        HStack(alignment: .center) {
            Toggle(isOn: $exploreOnlyUnvisitedPlaces) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Explore mode")
                        .font(.vlCaption(12))
                        .foregroundStyle(VLColor.darkTeal)
                    Text("Only unvisited places")
                        .font(.vlCaption(10))
                        .foregroundStyle(VLColor.subtleInk)
                }
            }
            .tint(VLColor.burgundy)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(VLColor.mapOverlayBar)
    }

    private var mapCategoryFilterBar: some View {
        HStack(spacing: 6) {
            ForEach(DiscoveryCategory.allCases) { cat in
                mapCategoryChip(
                    title: cat.mapChipLabel,
                    accessibilityTitle: cat.displayName,
                    symbol: cat.symbol,
                    selected: mapCategoryFilter == cat
                ) {
                    mapCategoryFilter = cat
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(VLColor.mapOverlayBar)
    }

    private func mapCategoryChip(
        title: String,
        accessibilityTitle: String,
        symbol: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.caption2)
                Text(title)
                    .font(.vlCaption(10))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(selected ? VLColor.cream : VLColor.darkTeal)
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(selected ? VLColor.burgundy : VLColor.mapChipIdleFill)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(selected ? VLColor.mutedGold.opacity(0.6) : VLColor.burgundy.opacity(0.25), lineWidth: selected ? 2 : 1)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(accessibilityTitle) places")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
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

    private func focusMapOn(poi: CachedPOI) {
        let c = CLLocationCoordinate2D(latitude: poi.latitude, longitude: poi.longitude)
        withAnimation {
            position = .region(MKCoordinateRegion(center: c, span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)))
        }
    }

    private func openPlaceFromSocialDeepLink(_ place: MainShellTabRouter.PendingMapPlace) {
        let id = place.osmId
        if let existing = cachedPOIs.first(where: { $0.osmId == id }) {
            focusMapOn(poi: existing)
            presentedPlace = MapPresentedPlace(poi: existing)
            tabRouter.pendingMapPlace = nil
            return
        }
        let fd = FetchDescriptor<CachedPOI>(predicate: #Predicate { $0.osmId == id })
        if let existing = try? modelContext.fetch(fd).first {
            focusMapOn(poi: existing)
            presentedPlace = MapPresentedPlace(poi: existing)
            tabRouter.pendingMapPlace = nil
            return
        }
        let stub = CachedPOI(
            osmId: place.osmId,
            name: place.name,
            latitude: place.latitude,
            longitude: place.longitude,
            categoryRaw: DiscoveryCategory.food.rawValue,
            isChain: false,
            chainLabel: nil,
            isPartner: false,
            partnerOffer: nil,
            stampCode: nil,
            addressSummary: nil,
            cityKey: place.cityKey
        )
        modelContext.insert(stub)
        try? modelContext.save()
        focusMapOn(poi: stub)
        presentedPlace = MapPresentedPlace(poi: stub)
        tabRouter.pendingMapPlace = nil
    }
}

/// Soft “fog of war” veil while swapping map display modes.
private struct MapFogTransitionOverlay: View {
    var opacity: Double
    var useDarkVintage: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.06, paused: opacity < 0.08)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let center = UnitPoint(
                x: 0.5 + 0.1 * sin(t * 0.65),
                y: 0.48 + 0.08 * cos(t * 0.48)
            )
            ZStack {
                RadialGradient(
                    colors: [
                        (useDarkVintage ? Color(red: 0.14, green: 0.2, blue: 0.16) : Color(red: 0.94, green: 0.9, blue: 0.86))
                            .opacity(0.88 * opacity),
                        Color.black.opacity(useDarkVintage ? 0.72 : 0.5).opacity(opacity)
                    ],
                    center: center,
                    startRadius: 24,
                    endRadius: 560
                )
                Color.white.opacity(useDarkVintage ? 0 : 0.1 * opacity)
                    .blendMode(.overlay)
            }
            .ignoresSafeArea()
        }
    }
}

/// Picks which POIs to draw when over the pin cap: zoomed in ⇒ near map center; zoomed out ⇒ grid across the viewport.
private enum MapAnnotationCap {
    /// Above this span (degrees), spread pins across the visible rect instead of clustering on the center.
    private static let zoomSpreadThresholdSpan = 0.048

    static func cappedPOIs(
        _ pois: [CachedPOI],
        maxCount: Int,
        region: MKCoordinateRegion?,
        fallbackCenter: CLLocationCoordinate2D
    ) -> [CachedPOI] {
        guard maxCount > 0 else { return [] }
        guard pois.count > maxCount else { return pois }
        guard let region else {
            return nearestTo(pois, center: fallbackCenter, maxCount: maxCount)
        }
        let span = max(region.span.latitudeDelta, region.span.longitudeDelta)
        if span < zoomSpreadThresholdSpan {
            return nearestTo(pois, center: region.center, maxCount: maxCount)
        }
        return spreadAcrossViewport(pois, region: region, maxCount: maxCount, fillRemainderAround: fallbackCenter)
    }

    private static func coord(_ p: CachedPOI) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: p.latitude, longitude: p.longitude)
    }

    private static func nearestTo(_ pois: [CachedPOI], center: CLLocationCoordinate2D, maxCount: Int) -> [CachedPOI] {
        pois
            .sorted { GeoMath.distanceSquaredComparable(center, coord($0)) < GeoMath.distanceSquaredComparable(center, coord($1)) }
            .prefix(maxCount)
            .map { $0 }
    }

    private static func spreadAcrossViewport(
        _ pois: [CachedPOI],
        region: MKCoordinateRegion,
        maxCount: Int,
        fillRemainderAround: CLLocationCoordinate2D
    ) -> [CachedPOI] {
        let gridCols = max(2, Int(ceil(sqrt(Double(maxCount)))))
        let gridRows = max(2, Int(ceil(Double(maxCount) / Double(gridCols))))

        let lat0 = region.center.latitude - region.span.latitudeDelta / 2
        let lon0 = region.center.longitude - region.span.longitudeDelta / 2
        let latS = max(region.span.latitudeDelta, 1e-12)
        let lonS = max(region.span.longitudeDelta, 1e-12)

        var buckets: [Int: [CachedPOI]] = [:]
        for p in pois {
            let col = min(gridCols - 1, max(0, Int((p.longitude - lon0) / lonS * Double(gridCols))))
            let row = min(gridRows - 1, max(0, Int((p.latitude - lat0) / latS * Double(gridRows))))
            let key = row * gridCols + col
            buckets[key, default: []].append(p)
        }

        func cellCenter(row: Int, col: Int) -> CLLocationCoordinate2D {
            let lat = lat0 + (Double(row) + 0.5) / Double(gridRows) * latS
            let lon = lon0 + (Double(col) + 0.5) / Double(gridCols) * lonS
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }

        var out: [CachedPOI] = []
        for row in 0 ..< gridRows {
            for col in 0 ..< gridCols {
                guard out.count < maxCount else { break }
                let key = row * gridCols + col
                guard let list = buckets[key], !list.isEmpty else { continue }
                let c = cellCenter(row: row, col: col)
                if let best = list.min(by: { GeoMath.distanceSquaredComparable(c, coord($0)) < GeoMath.distanceSquaredComparable(c, coord($1)) }) {
                    out.append(best)
                }
            }
        }

        if out.count < maxCount {
            var seen = Set(out.map(\.osmId))
            for row in 0 ..< gridRows {
                for col in 0 ..< gridCols {
                    guard out.count < maxCount else { break }
                    let key = row * gridCols + col
                    guard let list = buckets[key] else { continue }
                    let c = cellCenter(row: row, col: col)
                    let extras = list.filter { !seen.contains($0.osmId) }
                    guard let next = extras.min(by: { GeoMath.distanceSquaredComparable(c, coord($0)) < GeoMath.distanceSquaredComparable(c, coord($1)) }) else { continue }
                    out.append(next)
                    seen.insert(next.osmId)
                }
            }
        }

        if out.count < maxCount {
            let seen = Set(out.map(\.osmId))
            let rest = pois.filter { !seen.contains($0.osmId) }
            out.append(contentsOf: nearestTo(rest, center: fillRemainderAround, maxCount: maxCount - out.count))
        }

        return Array(out.prefix(maxCount))
    }
}

/// Keeps annotations inside (or slightly past) the visible map rect so we don’t render the whole city at once.
private enum MapViewportFilter {
    static func poi(_ poi: CachedPOI, isInside region: MKCoordinateRegion, marginFraction: Double = 0.12) -> Bool {
        coordinate(latitude: poi.latitude, longitude: poi.longitude, isInside: region, marginFraction: marginFraction)
    }

    private static func coordinate(latitude: Double, longitude: Double, isInside region: MKCoordinateRegion, marginFraction: Double) -> Bool {
        let latPad = region.span.latitudeDelta * marginFraction
        let lonPad = region.span.longitudeDelta * marginFraction
        let minLat = region.center.latitude - region.span.latitudeDelta / 2 - latPad
        let maxLat = region.center.latitude + region.span.latitudeDelta / 2 + latPad
        let minLon = region.center.longitude - region.span.longitudeDelta / 2 - lonPad
        let maxLon = region.center.longitude + region.span.longitudeDelta / 2 + lonPad
        return latitude >= minLat && latitude <= maxLat && longitude >= minLon && longitude <= maxLon
    }
}

/// Shared chrome for map pins (category fill is per ``DiscoveryCategory/mapPinMutedFill``).
private enum MapPlaceGlyphPalette {
    static let ringStroke = Color(red: 0x7B / 255, green: 0x2D / 255, blue: 0x26 / 255)
    static let symbolOnPin = Color(red: 0xF5 / 255, green: 0xE9 / 255, blue: 0xD3 / 255)
    static let partnerSeal = Color(red: 0xC8 / 255, green: 0x9B / 255, blue: 0x3C / 255)
    static let unknownCategoryFill = Color(red: 0.52, green: 0.48, blue: 0.46)
}

private extension DiscoveryCategory {
    /// Muted fills: Shop blue, Fun red, Parks green, Food orange, Gems purple (vintage-friendly).
    var mapPinMutedFill: Color {
        switch self {
        case .shopping:
            Color(red: 0.44, green: 0.56, blue: 0.72)
        case .entertainment:
            Color(red: 0.71, green: 0.40, blue: 0.42)
        case .outdoor:
            Color(red: 0.46, green: 0.62, blue: 0.50)
        case .food:
            Color(red: 0.76, green: 0.54, blue: 0.38)
        case .hiddenGems:
            Color(red: 0.58, green: 0.48, blue: 0.70)
        }
    }
}

/// Four-point compass star (cardinal points, diagonal indents).
private struct FourPointedStar: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let outer = Double(min(rect.width, rect.height) / 2)
        let inner = outer * 0.42
        var path = Path()
        for i in 0 ..< 8 {
            let angle = -Double.pi / 2 + Double(i) * Double.pi / 4
            let rad = i.isMultiple(of: 2) ? outer : inner
            let p = CGPoint(
                x: c.x + CGFloat(cos(angle) * rad),
                y: c.y + CGFloat(sin(angle) * rad)
            )
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }
}

private struct POIMapGlyph: View {
    let poi: CachedPOI
    var discovered: Bool

    private var pinFill: Color {
        let base = DiscoveryCategory(rawValue: poi.categoryRaw)?.mapPinMutedFill ?? MapPlaceGlyphPalette.unknownCategoryFill
        return discovered ? base.opacity(0.92) : base.opacity(0.62)
    }

    var body: some View {
        ZStack {
            if discovered {
                FourPointedStar()
                    .fill(pinFill)
                    .frame(width: 32, height: 32)
                    .overlay(
                        FourPointedStar()
                            .stroke(MapPlaceGlyphPalette.ringStroke, lineWidth: 2)
                    )
            } else {
                Circle()
                    .fill(pinFill)
                    .frame(width: 28, height: 28)
                    .overlay(Circle().stroke(MapPlaceGlyphPalette.ringStroke, lineWidth: 1.5))
            }
            categorySymbol
                .font(discovered ? .system(size: 11) : .caption)
                .foregroundStyle(MapPlaceGlyphPalette.symbolOnPin)
            if poi.isPartner {
                Image(systemName: "seal.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(MapPlaceGlyphPalette.partnerSeal)
                    .offset(x: discovered ? 14 : 12, y: discovered ? -14 : -12)
            }
        }
        .frame(width: 36, height: 36)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var categorySymbol: some View {
        if let cat = DiscoveryCategory(rawValue: poi.categoryRaw) {
            Image(systemName: cat.symbol)
        } else {
            Image(systemName: "mappin")
        }
    }
}
