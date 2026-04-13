//
//  ExplorationCoordinator.swift
//  Venture Local
//
//  Ties together location and Overpass sync for map context; POI visits are claimed from the Journal within ~0.02 mi; partner QR scans allow ~0.05 mi.
//

import CoreLocation
import Foundation
import MapKit
import Observation
import SwiftData
import UIKit

@Observable @MainActor
final class ExplorationCoordinator: NSObject {
    /// Journal visit claim, partner proximity banner, and manual stamp collection use **0.02 miles** (exposed in meters for `GeoMath`).
    nonisolated static let poiProximityRadiusMiles: Double = 0.02
    nonisolated static var poiProximityRadiusMeters: Double { poiProximityRadiusMiles * 1609.344 }
    nonisolated static let poiProximityRadiusCopy: String = "0.02 miles"

    /// Partner QR scan validation uses a wider radius than Journal claims.
    nonisolated static let partnerQRProximityRadiusMiles: Double = 0.05
    nonisolated static var partnerQRProximityRadiusMeters: Double { partnerQRProximityRadiusMiles * 1609.344 }
    nonisolated static let partnerQRProximityRadiusCopy: String = "0.05 miles"
    /// When a partner’s `osmId` is synthetic, treat a cached map POI within this distance of `partners.json` coords as the same venue (matches Journal/map pin vs geocode).
    nonisolated static let partnerVenueCoalesceRadiusMeters: Double = 60

    private let modelContext: ModelContext
    private let chainDetector = ChainDetector()
    private let partners = PartnerCatalog.load(from: .main)
    private let overpass = OverpassClient()
    private let nominatim = NominatimClient()

    private let geocoder = CLGeocoder()
    private var lastGeocodeTime: Date = .distantPast
    private var lastGeocodedCityKey: String?
    private var lastBoundaryFetchAt: Date = .distantPast
    private var boundaryFetchCityKey: String?
    /// Built from Apple `CLGeocoder` — used for Nominatim city search when reverse returns a micro-polygon.
    private var appleGeocodedPlaceQuery: String?

    private var lastPOIFetchCenter: CLLocationCoordinate2D?
    private var lastLocationSample: CLLocation?
    private var mapHintClearTask: Task<Void, Never>?
    private var didPurgeStalePOIsThisSession = false

    private var lastNearbyRecomputeAt: Date = .distantPast
    private let nearbyRecomputeMinInterval: TimeInterval = 3.0
    private let nearbyRecomputeMinIntervalAfterMove: TimeInterval = 0.45
    private let backgroundNearbyRecomputeMinInterval: TimeInterval = 22.0

    let locationManager = CLLocationManager()

    var currentCityKey: String?
    var currentCityDisplayName: String?
    /// Short, non-blocking hint on the map (sync issues). Avoids modal alerts for transient failures.
    var mapHint: String?
    var isSyncingPOIs: Bool = false
    var lastUserLocation: CLLocation?
    /// Undiscovered cached POIs within `poiProximityRadiusMeters` of the user (Journal claim banner).
    private(set) var nearbyClaimablePOIs: [CachedPOI] = []
    /// Supported partners from `partners.json` within range (Passport — tap to open QR scanner).
    private(set) var nearbyPartnerStampOffers: [NearbyPartnerStampOffer] = []

    // MARK: - Current city limit (Nominatim boundary)

    /// Outer rings (closed) for map outline (`MapPolyline`).
    var cityBoundaryMapRings: [[CLLocationCoordinate2D]] = []
    /// Draw the outline only when this matches ``currentCityKey`` so a stale polygon never labels the wrong city.
    var cityBoundaryRingsCityKey: String? { boundaryFetchCityKey }
    /// Full polygons with holes for point-in-polygon tests.
    private(set) var cityBoundaryPolygons: [(outer: [CLLocationCoordinate2D], holes: [[CLLocationCoordinate2D]])] = []
    private(set) var cityLimitBoundingBox: (south: Double, north: Double, west: Double, east: Double)?
    var isLoadingCityBoundary: Bool = false

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        super.init()
        locationManager.delegate = self
        // Nearest-ten + modest distance filter: enough for road “ink” without chasing perfect GPS.
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        locationManager.distanceFilter = 22
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.activityType = .fitness
        locationManager.allowsBackgroundLocationUpdates = false
    }

    /// `UIBackgroundModes` must include `location` or Core Location throws when enabling background updates.
    private static func appBundleIncludesLocationBackgroundMode() -> Bool {
        guard let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] else { return false }
        return modes.contains("location")
    }

    /// Whether we may set `allowsBackgroundLocationUpdates` without tripping `CLClientIsBackgroundable` assertions.
    private var canEnableBackgroundLocationUpdates: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return locationManager.authorizationStatus == .authorizedAlways
            && Self.appBundleIncludesLocationBackgroundMode()
        #endif
    }

    /// Stops updates before toggling `allowsBackgroundLocationUpdates` (required on device), then resumes if authorized.
    func configureBackgroundIfAuthorized() {
        reconcileLocationTrackingForCurrentAuthorization()
    }

    private func reconcileLocationTrackingForCurrentAuthorization() {
        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            applyBackgroundLocationCapabilityThenResumeUpdates()
        default:
            locationManager.stopUpdatingLocation()
            locationManager.allowsBackgroundLocationUpdates = false
            locationManager.showsBackgroundLocationIndicator = false
        }
    }

    private func applyBackgroundLocationCapabilityThenResumeUpdates() {
        let enableBackground = canEnableBackgroundLocationUpdates
        if locationManager.allowsBackgroundLocationUpdates != enableBackground {
            locationManager.stopUpdatingLocation()
            locationManager.allowsBackgroundLocationUpdates = enableBackground
        }
        locationManager.showsBackgroundLocationIndicator = enableBackground
        locationManager.startUpdatingLocation()
    }

    /// Current Core Location authorization (for UI hints).
    var locationAuthorizationStatus: CLAuthorizationStatus {
        locationManager.authorizationStatus
    }

    /// `true` when we only have When-In-Use — user can upgrade to Always in Settings for background exploration.
    var shouldSuggestAlwaysLocationUpgrade: Bool {
        locationManager.authorizationStatus == .authorizedWhenInUse
    }

    /// `true` when background updates are allowed (Always + configured).
    var isBackgroundLocationEnabled: Bool {
        locationManager.authorizationStatus == .authorizedAlways && locationManager.allowsBackgroundLocationUpdates
    }

    /// Requests **Always** authorization (includes while-using). Needed to log roads, nearby places, and journal context when the app isn’t open.
    func requestExplorationLocationAccess() {
        locationManager.requestAlwaysAuthorization()
    }

    /// Legacy entry point — prefer `requestExplorationLocationAccess()`.
    func requestWhenInUse() {
        requestExplorationLocationAccess()
    }

    func requestAlwaysIfNeeded() {
        locationManager.requestAlwaysAuthorization()
    }

    func startTracking() {
        reconcileLocationTrackingForCurrentAuthorization()
    }

    func stopTracking() {
        locationManager.stopUpdatingLocation()
        locationManager.allowsBackgroundLocationUpdates = false
        locationManager.showsBackgroundLocationIndicator = false
    }

    func fetchOrCreateProfile() throws -> ExplorerProfile {
        let d = FetchDescriptor<ExplorerProfile>()
        if let p = try modelContext.fetch(d).first { return p }
        let p = ExplorerProfile()
        modelContext.insert(p)
        try modelContext.save()
        return p
    }

    /// Prefer a recent GPS fix over the map center so city / boundaries match where you actually are (not the simulator default or a panned map).
    func anchorForLocationServices(mapCenter: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        if let loc = lastUserLocation,
           loc.horizontalAccuracy > 0,
           loc.horizontalAccuracy <= 2_500,
           abs(loc.timestamp.timeIntervalSinceNow) < 240 {
            return loc.coordinate
        }
        return mapCenter
    }

    /// Call when the map camera settles; fetches POIs + roads for the visible region.
    func syncRegion(_ region: MKCoordinateRegion) async {
        let mapCenter = region.center
        let anchor = anchorForLocationServices(mapCenter: mapCenter)
        let zoomSpan = max(region.span.latitudeDelta, region.span.longitudeDelta)
        // Zoomed-out map: use a smaller query box + fewer persisted POIs so decode/merge/SwiftData stay responsive.
        let maxQueryDelta: Double = {
            if zoomSpan > 0.14 { return 0.028 }
            if zoomSpan > 0.10 { return 0.034 }
            if zoomSpan > 0.06 { return 0.044 }
            return 0.056
        }()
        let latDelta = min(max(region.span.latitudeDelta, 0.012), maxQueryDelta)
        let lonDelta = min(max(region.span.longitudeDelta, 0.012), maxQueryDelta)
        let south = mapCenter.latitude - latDelta / 2
        let north = mapCenter.latitude + latDelta / 2
        let west = mapCenter.longitude - lonDelta / 2
        let east = mapCenter.longitude + lonDelta / 2

        await refreshCityKeyIfNeeded(for: anchor)

        let profileKey = lastKnownProfile()?.selectedCityKey
        let fallback = CityKey.mapRegionFallback(center: anchor)
        let cityKey = currentCityKey ?? profileKey ?? fallback
        if currentCityKey == nil {
            currentCityKey = cityKey
        }
        if cityKey.hasPrefix("map__"), currentCityDisplayName == nil {
            currentCityDisplayName = String(format: "Near %.2f°, %.2f°", anchor.latitude, anchor.longitude)
        }

        await refreshCityBoundaryIfNeeded(center: anchor, cityKey: cityKey)

        let maxOverpassPlaces: Int = {
            if zoomSpan > 0.14 { return 120 }
            if zoomSpan > 0.10 { return 160 }
            if zoomSpan > 0.07 { return 220 }
            if zoomSpan > 0.045 { return 280 }
            return 340
        }()
        let maxApplePlaces: Int = {
            if zoomSpan > 0.12 { return 65 }
            if zoomSpan > 0.08 { return 85 }
            return 105
        }()
        if shouldFetchPOIs(center: mapCenter, zoomLatitudeSpan: zoomSpan) {
            isSyncingPOIs = true
            defer { isSyncingPOIs = false }
            do {
                if !didPurgeStalePOIsThisSession {
                    try POISyncService.purgeStalePOIs(olderThan: 7, in: modelContext)
                    didPurgeStalePOIsThisSession = true
                }
                let ql = OverpassClient.poiQuery(south: south, west: west, north: north, east: east)
                let data = try await overpass.runQuery(ql)
                let maxResponseBytes = 14 * 1024 * 1024
                let mergedPOIs: Bool
                if data.count > maxResponseBytes {
                    showMapHint("Places data: Area returned too much data. Zoom in closer and try again.")
                    mergedPOIs = false
                } else {
                    let payload = try OverpassMergePayloadFactory.buildOverpassMergePayload(
                        from: data,
                        chainDetector: chainDetector,
                        partners: partners,
                        priorityCenter: anchor,
                        maxPlacesToPersist: maxOverpassPlaces
                    )
                    _ = try POISyncService.applyOverpassMergePayload(payload, cityKey: cityKey, into: modelContext)
                    mergedPOIs = true
                }
                try modelContext.save()
                recomputeNearbyClaimablePOIs()
                if mergedPOIs {
                    lastPOIFetchCenter = mapCenter
                    clearMapHint()
                    let mkRegion = MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: (south + north) / 2, longitude: (west + east) / 2),
                        span: MKCoordinateSpan(latitudeDelta: max(north - south, 0.015), longitudeDelta: max(east - west, 0.015))
                    )
                    Task { await self.refreshApplePOIs(region: mkRegion, cityKey: cityKey, priorityCenter: anchor, maxItems: maxApplePlaces) }
                }
            } catch {
                guard shouldSurfaceFetchError(error) else { return }
                showMapHint("Places data: \(error.localizedDescription)")
            }
        }

    }

    private func refreshApplePOIs(region: MKCoordinateRegion, cityKey: String, priorityCenter: CLLocationCoordinate2D, maxItems: Int) async {
        guard currentCityKey == cityKey else { return }
        do {
            _ = try await ApplePOISearchService.mergePointsOfInterest(
                region: region,
                cityKey: cityKey,
                chainDetector: chainDetector,
                partners: partners,
                context: modelContext,
                priorityCenter: priorityCenter,
                maxItemsToMerge: maxItems
            )
            try modelContext.save()
            recomputeNearbyClaimablePOIs()
        } catch {
            guard shouldSurfaceFetchError(error) else { return }
            showMapHint("Places data: \(error.localizedDescription)")
        }
    }


    private func showMapHint(_ text: String) {
        mapHint = text
        mapHintClearTask?.cancel()
        mapHintClearTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled else { return }
            if mapHint == text { mapHint = nil }
        }
    }

    private func clearMapHint() {
        mapHint = nil
        mapHintClearTask?.cancel()
        mapHintClearTask = nil
    }

    /// Pan/zoom cancels debounced `syncRegion` / child tasks — don’t flash “cancelled” to the user.
    private func shouldSurfaceFetchError(_ error: Error) -> Bool {
        if error is CancellationError { return false }
        if let url = error as? URLError, url.code == .cancelled { return false }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain, ns.code == NSURLErrorCancelled { return false }
        return true
    }

    /// Wider zoom ⇒ larger pan (meters) before refetching, so zoomed-out browsing doesn’t spam Overpass.
    private func shouldFetchPOIs(center: CLLocationCoordinate2D, zoomLatitudeSpan: Double) -> Bool {
        guard let prev = lastPOIFetchCenter else { return true }
        let spanBoost = max(1.0, zoomLatitudeSpan / 0.04)
        let threshold = min(4_500, 1_200 * spanBoost)
        return GeoMath.distanceMeters(prev, center) > threshold
    }

    private func refreshCityKeyIfNeeded(for coord: CLLocationCoordinate2D) async {
        let now = Date()
        guard now.timeIntervalSince(lastGeocodeTime) > 18 else { return }
        lastGeocodeTime = now
        let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        do {
            let marks = try await geocoder.reverseGeocodeLocation(loc)
            guard !marks.isEmpty else { return }
            let m = PlacemarkPicker.best(for: loc, marks: marks)
            let key = CityKey.make(
                locality: m.locality,
                administrativeArea: m.administrativeArea,
                country: m.isoCountryCode,
                subAdministrativeArea: m.subAdministrativeArea
            )
            let display = [m.locality ?? m.subAdministrativeArea, m.administrativeArea]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
            var qParts: [String] = []
            if let l = m.locality, !l.isEmpty { qParts.append(l) }
            else if let sub = m.subAdministrativeArea, !sub.isEmpty { qParts.append(sub) }
            if let a = m.administrativeArea { qParts.append(a) }
            if let c = m.country, !c.isEmpty { qParts.append(c) } else if let code = m.isoCountryCode { qParts.append(code) }
            appleGeocodedPlaceQuery = qParts.isEmpty ? nil : qParts.joined(separator: ", ")

            let prior = lastGeocodedCityKey
            lastGeocodedCityKey = key
            currentCityKey = key
            currentCityDisplayName = display.isEmpty ? key : display
            recomputeNearbyClaimablePOIs()
            recomputeNearbyPartnersForPassport()
            if prior != key {
                lastPOIFetchCenter = nil
                clearCityBoundaryData()
                boundaryFetchCityKey = nil
                Task { await refreshCityBoundary(center: coord, cityKey: key) }
            }
            if let p = try? fetchOrCreateProfile() {
                let pin = p.pinnedExplorationCityKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let isPinned = !pin.isEmpty
                if isPinned {
                    if p.selectedCityKey == nil { p.selectedCityKey = key }
                    if p.homeCityKey == nil { p.homeCityKey = key }
                    if p.homeCityDisplayName == nil { p.homeCityDisplayName = display }
                } else {
                    // “Follow my location”: keep profile keys in sync with GPS so stale keys (e.g. old simulator geocode) don’t stick.
                    p.selectedCityKey = key
                    p.homeCityKey = key
                    p.homeCityDisplayName = display.isEmpty ? key : display
                }
                try? modelContext.save()
            }
        } catch {
            // Geocoder failures are common under throttling; ignore silently.
        }
    }

    private func refreshCityBoundaryIfNeeded(center: CLLocationCoordinate2D, cityKey: String) async {
        if boundaryFetchCityKey == cityKey, !cityBoundaryPolygons.isEmpty { return }
        if boundaryFetchCityKey == cityKey, cityBoundaryPolygons.isEmpty, Date().timeIntervalSince(lastBoundaryFetchAt) < 120 {
            return
        }
        await refreshCityBoundary(center: center, cityKey: cityKey)
    }

    private func refreshCityBoundary(center: CLLocationCoordinate2D, cityKey: String) async {
        isLoadingCityBoundary = true
        defer { isLoadingCityBoundary = false }
        do {
            let json = try await nominatim.reverse(latitude: center.latitude, longitude: center.longitude, zoom: 11)
            var candidates: [ParsedCityBoundary] = []
            if let p = CityBoundaryParser.parse(nominatimJSON: json) {
                candidates.append(p)
            }

            let needsSearch = CityBoundaryResolver.reverseLooksLikeMicroPlace(json)
                || candidates.first.map { CityBoundaryResolver.isTooSmallForCity($0) } != false
                || candidates.isEmpty

            if needsSearch {
                let q = CityBoundaryResolver.buildSearchQuery(fromReverseJSON: json, fallbackCityKey: cityKey)
                    ?? appleGeocodedPlaceQuery
                if let q, !q.isEmpty {
                    var hits = try await nominatim.search(query: q, featuretype: "city")
                    if hits.isEmpty { hits = try await nominatim.search(query: q, featuretype: "town") }
                    if hits.isEmpty { hits = try await nominatim.search(query: q, featuretype: nil) }
                    if let best = CityBoundaryResolver.pickBestSearchResult(hits, near: center),
                       let p2 = CityBoundaryParser.parse(nominatimJSON: best) {
                        candidates.append(p2)
                    }
                }
            }

            let chosen = CityBoundaryResolver.pickParsedBoundary(candidates: candidates, center: center)

            guard let parsed = chosen else {
                clearCityBoundaryData()
                boundaryFetchCityKey = cityKey
                lastBoundaryFetchAt = Date()
                return
            }

            cityBoundaryPolygons = parsed.polygons
            cityBoundaryMapRings = parsed.mapOutlineRings
            let s = parsed.south, n = parsed.north, w = parsed.west, e = parsed.east
            cityLimitBoundingBox = (s, n, w, e)
            boundaryFetchCityKey = cityKey
            lastBoundaryFetchAt = Date()
            Task { await self.scheduleCityLocalsBaselineRefresh(cityKey: cityKey, south: s, north: n, west: w, east: e) }
        } catch {
            guard shouldSurfaceFetchError(error) else { return }
            showMapHint("City outline: \(error.localizedDescription)")
        }
    }

    /// One full Overpass pass over the Nominatim city bbox (throttled) so journal “X / Y locals” doesn’t track map tile cache size.
    private func scheduleCityLocalsBaselineRefresh(cityKey: String, south: Double, north: Double, west: Double, east: Double) async {
        guard south < north, west < east else { return }
        let latSpan = north - south
        let lonSpan = east - west
        guard latSpan <= 0.52, lonSpan <= 0.62, latSpan * lonSpan <= 0.28 else { return }

        let ck = cityKey
        let fd = FetchDescriptor<CityLocalsBaseline>(predicate: #Predicate<CityLocalsBaseline> { $0.cityKey == ck })
        if let existing = try? modelContext.fetch(fd).first,
           Date().timeIntervalSince(existing.updatedAt) < 86400 * 5 {
            return
        }

        let ql = OverpassClient.poiQuery(south: south, west: west, north: north, east: east, timeoutSeconds: 90)
        let data: Data
        do {
            data = try await overpass.runQuery(ql)
        } catch {
            return
        }

        let scan: (total: Int, perCategory: [String: Int])
        do {
            scan = try OverpassMergePayloadFactory.countNonChainLocalsFromOverpassData(
                data,
                chainDetector: chainDetector,
                partners: partners
            )
        } catch {
            return
        }

        guard scan.total > 0 else { return }

        let json = try? JSONEncoder().encode(scan.perCategory)
        let row: CityLocalsBaseline
        if let e = try? modelContext.fetch(fd).first {
            row = e
        } else {
            row = CityLocalsBaseline(cityKey: cityKey)
            modelContext.insert(row)
        }
        row.nonChainLocalTotal = scan.total
        row.categoryTotalsJSON = json
        row.updatedAt = .now
        try? modelContext.save()
        NotificationCenter.default.post(name: .ventureLocalCityBaselineUpdated, object: nil)
    }

    private func clearCityBoundaryData() {
        cityBoundaryPolygons = []
        cityBoundaryMapRings = []
        cityLimitBoundingBox = nil
        boundaryFetchCityKey = nil
    }

    private func lastKnownProfile() -> ExplorerProfile? {
        try? modelContext.fetch(FetchDescriptor<ExplorerProfile>()).first
    }

    /// City for journal completion / stats (respects profile pin).
    var progressCityKeyForUI: String? {
        lastKnownProfile()?.effectiveProgressCityKey(liveCityKey: currentCityKey)
    }

    var progressCityDisplayName: String {
        if let pin = lastKnownProfile()?.pinnedExplorationCityKey, !pin.isEmpty {
            return CityKey.displayLabel(for: pin)
        }
        if let d = currentCityDisplayName, !d.isEmpty { return d }
        if let k = progressCityKeyForUI { return CityKey.displayLabel(for: k) }
        return "Unknown city"
    }

    /// Live anchor for “near you” lists (ignores pin so banners match where you actually are).
    private func nearbyAnchorCityKey() -> String? {
        currentCityKey ?? lastKnownProfile()?.selectedCityKey
    }

    fileprivate func handleLocation(_ location: CLLocation) {
        lastUserLocation = location

        let inBackground = UIApplication.shared.applicationState != .active
        if inBackground {
            scheduleThrottledNearbyRecompute(background: true)
            return
        }

        let skipHeavyWork: Bool = {
            guard let prev = lastLocationSample else { return false }
            return location.timestamp.timeIntervalSince(prev.timestamp) < 2 && location.distance(from: prev) < 5
        }()

        if skipHeavyWork {
            scheduleThrottledNearbyRecompute(background: false)
            return
        }

        lastLocationSample = location
        let coord = location.coordinate
        Task {
            await refreshCityKeyIfNeeded(for: coord)
            scheduleThrottledNearbyRecompute(background: false, allowSoon: true)
        }
    }

    private func scheduleThrottledNearbyRecompute(background: Bool, allowSoon: Bool = false) {
        let now = Date()
        let minDt: TimeInterval = {
            if background { return backgroundNearbyRecomputeMinInterval }
            if allowSoon { return nearbyRecomputeMinIntervalAfterMove }
            return nearbyRecomputeMinInterval
        }()
        guard now.timeIntervalSince(lastNearbyRecomputeAt) >= minDt else { return }
        lastNearbyRecomputeAt = now
        recomputeNearbyClaimablePOIs()
        recomputeNearbyPartnersForPassport()
    }

    /// Call when opening the Journal so the claim banner matches the latest cache without waiting for GPS.
    func refreshNearbyClaimablePOIs() {
        recomputeNearbyClaimablePOIs()
    }

    /// Recomputes badge rules after visits/stamps/XP and records inbox + passive local notifications for new badges or level-ups.
    func evaluateBadgesAndLedgerNotifications() {
        guard let profile = try? fetchOrCreateProfile() else { return }
        let xpBefore = profile.totalXP
        do {
            let discoveries = try modelContext.fetch(FetchDescriptor<DiscoveredPlace>())
            let pois = try modelContext.fetch(FetchDescriptor<CachedPOI>())
            let stamps = try modelContext.fetch(FetchDescriptor<StampRecord>())
            let result = try BadgeCatalog.evaluateAndAward(
                context: modelContext,
                profile: profile,
                liveCityKey: currentCityKey,
                discoveries: discoveries,
                pois: pois,
                stamps: stamps
            )
            try JournalLedgerNotificationService.recordAfterBadgeEvaluation(
                context: modelContext,
                newUnlocks: result.newUnlocks,
                xpBefore: xpBefore,
                xpAfter: profile.totalXP
            )
        } catch {}
    }

    /// Call when opening Passport (or after a stamp) so the in-range partner banner stays current.
    func refreshNearbyPartnersForPassport() {
        recomputeNearbyPartnersForPassport()
    }

    /// National chains are excluded from the discovery map even when `CachedPOI.isChain` is stale (before the next sync).
    func shouldHideChainFromDiscoveryMap(_ poi: CachedPOI) -> Bool {
        if poi.isChain { return true }
        let tags = POIExtendedMetadataCodec.decode(poi.extendedMetadataJSON)?.osmTags ?? [:]
        if PlaceExclusion.shouldExcludeOSMTags(tags) { return true }
        return chainDetector.evaluate(name: poi.name, tags: tags).0
    }

    /// Mark a visit for one POI when you are within `poiProximityRadiusMeters` (partner stamps auto-add if not already stamped).
    func claimPOI(osmId: String) throws {
        guard let loc = lastUserLocation else {
            struct E: LocalizedError { var errorDescription: String? { "Location is unavailable — enable location services to claim." } }
            throw E()
        }
        let id = osmId
        let poiFetch = FetchDescriptor<CachedPOI>(predicate: #Predicate { $0.osmId == id })
        guard let poi = try modelContext.fetch(poiFetch).first else { return }
        let cityKey = poi.cityKey
        let tags = POIExtendedMetadataCodec.decode(poi.extendedMetadataJSON)?.osmTags ?? [:]
        if POISyncService.isUnwantedPOIName(poi.name) || poi.isChain || PlaceExclusion.shouldExcludeOSMTags(tags) { return }
        let there = CLLocationCoordinate2D(latitude: poi.latitude, longitude: poi.longitude)
        guard GeoMath.distanceMeters(loc.coordinate, there) <= Self.poiProximityRadiusMeters else {
            struct E: LocalizedError { var errorDescription: String? { "Move closer to this place to claim it." } }
            throw E()
        }
        let discFetch = FetchDescriptor<DiscoveredPlace>(predicate: #Predicate { $0.osmId == id })
        if try modelContext.fetch(discFetch).first != nil {
            if try ExplorerEventLog.shouldRecordRevisit(context: modelContext, osmId: id, on: Date()) {
                ExplorerEventLog.recordRevisit(context: modelContext, poi: poi, cityKey: cityKey)
                try modelContext.save()
            }
            evaluateBadgesAndLedgerNotifications()
            recomputeNearbyClaimablePOIs()
            return
        }
        let claimedAt = Date()
        modelContext.insert(DiscoveredPlace(osmId: poi.osmId, discoveredAt: claimedAt, cityKey: cityKey))
        ExplorerEventLog.recordVisit(context: modelContext, poi: poi, cityKey: cityKey)
        if poi.isPartner {
            let stampFetch = FetchDescriptor<StampRecord>(predicate: #Predicate { $0.osmId == id })
            if try modelContext.fetch(stampFetch).first == nil {
                modelContext.insert(StampRecord(osmId: poi.osmId, cityKey: cityKey))
                ExplorerEventLog.recordStamp(context: modelContext, poi: poi, cityKey: cityKey)
            }
        }
        var xpBefore = 0
        var xpAfter = 0
        if let profile = try? fetchOrCreateProfile() {
            xpBefore = profile.totalXP
            profile.totalXP += 1
            xpAfter = profile.totalXP
        }
        try modelContext.save()
        if xpAfter > xpBefore {
            try? JournalLedgerNotificationService.recordLevelUpFromXPChange(
                context: modelContext,
                xpBefore: xpBefore,
                xpAfter: xpAfter
            )
        }
        evaluateBadgesAndLedgerNotifications()
        recomputeNearbyClaimablePOIs()
        Task {
            await CloudSyncService.shared.pushVisitIfPossible(
                osmId: poi.osmId,
                cityKey: cityKey,
                discoveredAt: claimedAt,
                explorerNote: nil
            )
        }
    }

    /// Cached POIs in a loose lat/lon window around the user (avoids `cityKey` mismatches between `map__…` merges and later geocode keys).
    private func cachedPOIsNearUser(coordinate: CLLocationCoordinate2D, marginDegrees: Double = 0.0045) throws -> [CachedPOI] {
        let la = coordinate.latitude
        let lo = coordinate.longitude
        let south = la - marginDegrees
        let north = la + marginDegrees
        let west = lo - marginDegrees
        let east = lo + marginDegrees
        return try modelContext.fetch(
            FetchDescriptor<CachedPOI>(predicate: #Predicate<CachedPOI> { p in
                p.latitude >= south && p.latitude <= north && p.longitude >= west && p.longitude <= east
            })
        )
    }

    private func recomputeNearbyClaimablePOIs() {
        guard let loc = lastUserLocation else {
            nearbyClaimablePOIs = []
            return
        }
        let here = loc.coordinate
        do {
            let all = try cachedPOIsNearUser(coordinate: here)
            let discovered = try Set(modelContext.fetch(FetchDescriptor<DiscoveredPlace>()).map(\.osmId))
            nearbyClaimablePOIs = Array(
                all
                    .filter { poi in
                        let tags = POIExtendedMetadataCodec.decode(poi.extendedMetadataJSON)?.osmTags ?? [:]
                        return !POISyncService.isUnwantedPOIName(poi.name)
                            && poi.isChain == false
                            && !PlaceExclusion.shouldExcludeOSMTags(tags)
                            && !discovered.contains(poi.osmId)
                            && GeoMath.distanceMeters(here, CLLocationCoordinate2D(latitude: poi.latitude, longitude: poi.longitude)) <= Self.poiProximityRadiusMeters
                    }
                    .sorted { a, b in
                        let da = GeoMath.distanceMeters(here, CLLocationCoordinate2D(latitude: a.latitude, longitude: a.longitude))
                        let db = GeoMath.distanceMeters(here, CLLocationCoordinate2D(latitude: b.latitude, longitude: b.longitude))
                        return da < db
                    }
                    .prefix(30)
            )
        } catch {
            nearbyClaimablePOIs = []
        }
    }

    private func recomputeNearbyPartnersForPassport() {
        guard let loc = lastUserLocation else {
            nearbyPartnerStampOffers = []
            return
        }
        let here = loc.coordinate
        do {
            let inCity = try cachedPOIsNearUser(coordinate: here)
            var rows: [(offer: NearbyPartnerStampOffer, distance: Double)] = []
            for poi in inCity {
                guard let entry = partners.matchPartnerPOI(name: poi.name, osmId: poi.osmId) else { continue }
                let pCoord = CLLocationCoordinate2D(latitude: poi.latitude, longitude: poi.longitude)
                let d = GeoMath.distanceMeters(here, pCoord)
                guard d <= Self.poiProximityRadiusMeters else { continue }
                let scansToday = (try? partnerQRScanCountSameCalendarDay(osmId: poi.osmId, referenceDate: .now)) ?? 0
                let canScan = scansToday == 0
                let asset = entry.stampImageName
                rows.append((
                    NearbyPartnerStampOffer(
                        osmId: poi.osmId,
                        displayName: poi.name,
                        stampImageName: asset.isEmpty ? nil : asset,
                        partnerImageURL: entry.imageURLString,
                        canScanPartnerQRToday: canScan,
                        distanceMeters: d
                    ),
                    d
                ))
            }
            rows.sort { $0.distance < $1.distance }
            nearbyPartnerStampOffers = rows.map(\.offer)
        } catch {
            nearbyPartnerStampOffers = []
        }
    }

    /// Same anchor as QR proximity: exact `CachedPOI` by `osmId`, else the in-city map pin nearest you among POIs within `partnerVenueCoalesceRadiusMeters` of catalog coords, else JSON coords.
    private func resolvedPartnerProximity(for partner: PartnerCatalog.Entry, userHere: CLLocationCoordinate2D) -> (anchor: CLLocationCoordinate2D, venuePOI: CachedPOI?)? {
        let pid = partner.osmId
        let exactFetch = FetchDescriptor<CachedPOI>(predicate: #Predicate { $0.osmId == pid })
        if let poi = try? modelContext.fetch(exactFetch).first {
            let c = CLLocationCoordinate2D(latitude: poi.latitude, longitude: poi.longitude)
            return (c, poi)
        }
        guard let la = partner.latitude, let lo = partner.longitude else { return nil }
        let catalogCoord = CLLocationCoordinate2D(latitude: la, longitude: lo)
        guard let cityKey = nearbyAnchorCityKey() else {
            return (catalogCoord, nil)
        }
        let inCityFetch = FetchDescriptor<CachedPOI>(predicate: #Predicate { $0.cityKey == cityKey })
        guard let inCity = try? modelContext.fetch(inCityFetch) else {
            return (catalogCoord, nil)
        }
        var bestPOI: CachedPOI?
        var bestDUser = Double.greatestFiniteMagnitude
        for poi in inCity {
            let pCoord = CLLocationCoordinate2D(latitude: poi.latitude, longitude: poi.longitude)
            guard GeoMath.distanceMeters(pCoord, catalogCoord) <= Self.partnerVenueCoalesceRadiusMeters else { continue }
            let dUser = GeoMath.distanceMeters(userHere, pCoord)
            if dUser < bestDUser {
                bestDUser = dUser
                bestPOI = poi
            }
        }
        if let p = bestPOI {
            return (CLLocationCoordinate2D(latitude: p.latitude, longitude: p.longitude), p)
        }
        return (catalogCoord, nil)
    }

    private func passportPartnerTitle(entry: PartnerCatalog.Entry, venuePOI: CachedPOI?) -> String {
        if let n = venuePOI?.name.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty { return n }
        return displayNameForPassportPartner(entry: entry)
    }

    private func displayNameForPassportPartner(entry: PartnerCatalog.Entry) -> String {
        if let n = entry.listingName, !n.isEmpty { return n }
        let id = entry.osmId
        let fd = FetchDescriptor<CachedPOI>(predicate: #Predicate { $0.osmId == id })
        if let n = try? modelContext.fetch(fd).first?.name, !n.isEmpty { return n }
        let offer = entry.offer.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = offer.range(of: " — ") { return String(offer[..<r.lowerBound]) }
        if let r = offer.range(of: " - ") { return String(offer[..<r.lowerBound]) }
        if !offer.isEmpty { return offer }
        let img = entry.stampImageName
        return img.isEmpty ? id : img
    }

    /// Validates QR payload (must match partner **image URL** or legacy stamp token), proximity (`partnerQRProximityRadiusMeters`), and one QR stamp per place per day.
    func recordPartnerQRScan(rawPayload: String) throws {
        guard let code = StampQRParser.extractStampCode(from: rawPayload) else {
            throw StampQRScanError.invalidQR
        }
        guard let partner = partners.match(qrToken: code) else {
            throw StampQRScanError.unknownPartner
        }
        guard let loc = lastUserLocation else {
            throw StampQRScanError.locationUnavailable
        }

        let resolved = try resolvePartnerScanVenue(partner: partner, userHere: loc.coordinate)
        guard resolved.distanceToUser <= Self.partnerQRProximityRadiusMeters else {
            throw StampQRScanError.tooFar
        }

        let pid = resolved.stampOsmId
        if try partnerQRScanCountSameCalendarDay(osmId: pid, referenceDate: .now) > 0 {
            throw StampQRScanError.alreadyScannedToday
        }

        let cityKey = currentCityKey ?? resolved.venuePOI?.cityKey ?? lastKnownProfile()?.selectedCityKey ?? "map__passport"
        modelContext.insert(StampRecord(osmId: pid, cityKey: cityKey, viaPartnerQR: true))
        if let venue = resolved.venuePOI {
            ExplorerEventLog.recordStamp(context: modelContext, poi: venue, cityKey: cityKey)
        } else if let stub = try? modelContext.fetch(FetchDescriptor<CachedPOI>(predicate: #Predicate { $0.osmId == pid })).first {
            ExplorerEventLog.recordStamp(context: modelContext, poi: stub, cityKey: cityKey)
        } else {
            modelContext.insert(ExplorerEvent(
                kind: .stamp,
                osmId: pid,
                cityKey: cityKey,
                categoryRaw: "",
                isChain: false,
                occurredAt: .now
            ))
        }
        try modelContext.save()
        evaluateBadgesAndLedgerNotifications()
        recomputeNearbyPartnersForPassport()
    }

    private struct PartnerScanResolution {
        var stampOsmId: String
        var venuePOI: CachedPOI?
        var distanceToUser: Double
    }

    /// Prefer a map POI whose **name** matches the partner listing and is within `partnerQRProximityRadiusMeters`; else catalog id / coordinates.
    private func resolvePartnerScanVenue(partner: PartnerCatalog.Entry, userHere: CLLocationCoordinate2D) throws -> PartnerScanResolution {
        guard let cityKey = currentCityKey ?? lastKnownProfile()?.selectedCityKey else {
            throw StampQRScanError.noAnchorCoordinate
        }
        let inCity = try modelContext.fetch(FetchDescriptor<CachedPOI>(predicate: #Predicate { $0.cityKey == cityKey }))

        var best: (poi: CachedPOI, d: Double)?
        for poi in inCity {
            guard partner.matchesListing(name: poi.name) else { continue }
            let c = CLLocationCoordinate2D(latitude: poi.latitude, longitude: poi.longitude)
            let d = GeoMath.distanceMeters(userHere, c)
            if d <= Self.partnerQRProximityRadiusMeters {
                if best == nil || d < best!.d { best = (poi, d) }
            }
        }
        if let b = best {
            return PartnerScanResolution(stampOsmId: b.poi.osmId, venuePOI: b.poi, distanceToUser: b.d)
        }

        let exactFetch = FetchDescriptor<CachedPOI>(predicate: #Predicate { $0.osmId == partner.osmId && $0.cityKey == cityKey })
        if let poi = try? modelContext.fetch(exactFetch).first {
            let c = CLLocationCoordinate2D(latitude: poi.latitude, longitude: poi.longitude)
            let d = GeoMath.distanceMeters(userHere, c)
            return PartnerScanResolution(stampOsmId: poi.osmId, venuePOI: poi, distanceToUser: d)
        }

        if let la = partner.latitude, let lo = partner.longitude {
            let catalogCoord = CLLocationCoordinate2D(latitude: la, longitude: lo)
            let d = GeoMath.distanceMeters(userHere, catalogCoord)
            return PartnerScanResolution(stampOsmId: partner.osmId, venuePOI: nil, distanceToUser: d)
        }

        if let prox = resolvedPartnerProximity(for: partner, userHere: userHere) {
            let d = GeoMath.distanceMeters(userHere, prox.anchor)
            let oid = prox.venuePOI?.osmId ?? partner.osmId
            return PartnerScanResolution(stampOsmId: oid, venuePOI: prox.venuePOI, distanceToUser: d)
        }
        throw StampQRScanError.noAnchorCoordinate
    }

    /// QR scans only: one partner QR stamp per place per calendar day.
    private func partnerQRScanCountSameCalendarDay(osmId: String, referenceDate: Date) throws -> Int {
        let cal = Calendar.current
        let rows = try modelContext.fetch(FetchDescriptor<StampRecord>(predicate: #Predicate { $0.osmId == osmId }))
        return rows.filter { $0.viaPartnerQR && cal.isDate($0.stampedAt, inSameDayAs: referenceDate) }.count
    }

    func collectStamp(for poi: CachedPOI, user: CLLocation) throws -> Bool {
        guard poi.isPartner else { return false }
        let here = user.coordinate
        let there = CLLocationCoordinate2D(latitude: poi.latitude, longitude: poi.longitude)
        guard GeoMath.distanceMeters(here, there) <= Self.poiProximityRadiusMeters else { return false }
        let id = poi.osmId
        let stampFetch = FetchDescriptor<StampRecord>(predicate: #Predicate { $0.osmId == id })
        if try modelContext.fetch(stampFetch).first != nil { return true }
        let city = currentCityKey ?? poi.cityKey
        modelContext.insert(StampRecord(osmId: poi.osmId, cityKey: city))
        ExplorerEventLog.recordStamp(context: modelContext, poi: poi, cityKey: city)
        try modelContext.save()
        evaluateBadgesAndLedgerNotifications()
        return true
    }

    /// Call after `ExplorationProgressReset.clearAllVisitAndExplorationData` so the map and nearby banners match storage.
    func reloadSessionStateAfterDataReset() {
        refreshNearbyClaimablePOIs()
        refreshNearbyPartnersForPassport()
    }
}

extension ExplorationCoordinator {
    /// In-range partner POI (name in `partners.json`) within `poiProximityRadiusMeters` — same idea as Journal claim banner.
    struct NearbyPartnerStampOffer: Identifiable, Hashable {
        var id: String { osmId }
        var osmId: String
        var displayName: String
        var stampImageName: String?
        /// Remote logo URL from JSON; QR should encode this same URL.
        var partnerImageURL: String?
        /// `true` when no partner-QR stamp exists yet for this place today (calendar day).
        var canScanPartnerQRToday: Bool
        var distanceMeters: Double
    }
}

extension ExplorationCoordinator: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.reconcileLocationTrackingForCurrentAuthorization()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            self.handleLocation(loc)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            // kCLErrorDenied (1) and locationUnknown (0) are routine (simulator, permissions, brief GPS loss).
            if let cl = error as? CLError {
                switch cl.code {
                case .locationUnknown, .denied, .network, .headingFailure:
                    return
                default:
                    break
                }
            }
            self.showMapHint("Location: \(error.localizedDescription)")
        }
    }
}
