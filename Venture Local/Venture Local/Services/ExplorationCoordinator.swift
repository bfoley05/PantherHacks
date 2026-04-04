//
//  ExplorationCoordinator.swift
//  Venture Local
//
//  Ties together location, Overpass sync, road XP; POI visits are claimed from the Journal within ~20m.
//

import CoreLocation
import Foundation
import MapKit
import Observation
import SwiftData

@Observable @MainActor
final class ExplorationCoordinator: NSObject {
    /// Journal “claim” and partner stamp checks use this horizontal distance (meters).
    static let poiProximityRadiusMeters: Double = 20
    /// When a partner’s `osmId` is synthetic, treat a cached map POI within this distance of `partners.json` coords as the same venue (matches Journal/map pin vs geocode).
    static let partnerVenueCoalesceRadiusMeters: Double = 60

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

    private var roadSegments: [POISyncService.RoadSegmentSample] = []
    private var lastRoadFetchCenter: CLLocationCoordinate2D?
    private var lastPOIFetchCenter: CLLocationCoordinate2D?
    private var lastLocationSample: CLLocation?
    private var mapHintClearTask: Task<Void, Never>?

    let locationManager = CLLocationManager()

    var currentCityKey: String?
    var currentCityDisplayName: String?
    /// Short, non-blocking hint on the map (sync issues). Avoids modal alerts for transient failures.
    var mapHint: String?
    var isSyncingPOIs: Bool = false
    var isSyncingRoads: Bool = false
    var lastUserLocation: CLLocation?
    /// Undiscovered cached POIs within `poiProximityRadiusMeters` of the user (Journal claim banner).
    private(set) var nearbyClaimablePOIs: [CachedPOI] = []
    /// Supported partners from `partners.json` within range (Passport — tap to open QR scanner).
    private(set) var nearbyPartnerStampOffers: [NearbyPartnerStampOffer] = []

    /// Revealed road segments as coordinates for `MapPolyline` (persisted + session).
    var revealedSegmentCoordinates: [[CLLocationCoordinate2D]] = []

    // MARK: - Current city limit (Nominatim boundary)

    /// Outer rings (closed) for `MapPolygon` stroke/fill.
    var cityBoundaryMapRings: [[CLLocationCoordinate2D]] = []
    /// Full polygons with holes for point-in-polygon tests.
    private(set) var cityBoundaryPolygons: [(outer: [CLLocationCoordinate2D], holes: [[CLLocationCoordinate2D]])] = []
    private(set) var cityLimitBoundingBox: (south: Double, north: Double, west: Double, east: Double)?
    var isLoadingCityBoundary: Bool = false

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 8
        locationManager.pausesLocationUpdatesAutomatically = true
        locationManager.activityType = .fitness
        locationManager.allowsBackgroundLocationUpdates = false
    }

    func configureBackgroundIfAuthorized() {
        guard locationManager.authorizationStatus == .authorizedAlways else { return }
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.showsBackgroundLocationIndicator = true
    }

    func requestWhenInUse() {
        locationManager.requestWhenInUseAuthorization()
    }

    func requestAlwaysIfNeeded() {
        locationManager.requestAlwaysAuthorization()
    }

    func startTracking() {
        locationManager.startUpdatingLocation()
    }

    func stopTracking() {
        locationManager.stopUpdatingLocation()
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
        // Huge viewports overload public Overpass instances; cap the bbox (~≤8km per axis in mid-latitudes).
        let latDelta = min(max(region.span.latitudeDelta, 0.012), 0.072)
        let lonDelta = min(max(region.span.longitudeDelta, 0.012), 0.072)
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

        if shouldFetchPOIs(center: mapCenter) {
            isSyncingPOIs = true
            defer { isSyncingPOIs = false }
            do {
                try POISyncService.purgeStalePOIs(olderThan: 7, in: modelContext)
                let ql = OverpassClient.poiQuery(south: south, west: west, north: north, east: east)
                let data = try await overpass.runQuery(ql)
                _ = try POISyncService.mergePOIs(from: data, cityKey: cityKey, chainDetector: chainDetector, partners: partners, into: modelContext)
                let mkRegion = MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: (south + north) / 2, longitude: (west + east) / 2),
                    span: MKCoordinateSpan(latitudeDelta: max(north - south, 0.015), longitudeDelta: max(east - west, 0.015))
                )
                _ = try await ApplePOISearchService.mergePointsOfInterest(
                    region: mkRegion,
                    cityKey: cityKey,
                    chainDetector: chainDetector,
                    partners: partners,
                    context: modelContext
                )
                try modelContext.save()
                lastPOIFetchCenter = mapCenter
                recomputeNearbyClaimablePOIs()
                clearMapHint()
            } catch {
                showMapHint("Places data: \(error.localizedDescription)")
            }
        }

        if shouldFetchRoads(center: mapCenter) {
            isSyncingRoads = true
            defer { isSyncingRoads = false }
            do {
                let ql = OverpassClient.roadQuery(south: south, west: west, north: north, east: east)
                let data = try await overpass.runQuery(ql)
                roadSegments = try POISyncService.decodeRoadSegments(from: data)
                lastRoadFetchCenter = mapCenter
                clearMapHint()
            } catch {
                showMapHint("Roads data: \(error.localizedDescription)")
            }
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

    private func shouldFetchPOIs(center: CLLocationCoordinate2D) -> Bool {
        guard let prev = lastPOIFetchCenter else { return true }
        return GeoMath.distanceMeters(prev, center) > 800
    }

    private func shouldFetchRoads(center: CLLocationCoordinate2D) -> Bool {
        guard let prev = lastRoadFetchCenter else { return true }
        return GeoMath.distanceMeters(prev, center) > 500
    }

    private func refreshCityKeyIfNeeded(for coord: CLLocationCoordinate2D) async {
        let now = Date()
        guard now.timeIntervalSince(lastGeocodeTime) > 18 else { return }
        lastGeocodeTime = now
        let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        do {
            let marks = try await geocoder.reverseGeocodeLocation(loc)
            guard let m = marks.first else { return }
            let key = CityKey.make(locality: m.locality, administrativeArea: m.administrativeArea, country: m.isoCountryCode)
            let display = [m.locality, m.administrativeArea].compactMap { $0 }.joined(separator: ", ")
            var qParts: [String] = []
            if let l = m.locality { qParts.append(l) }
            if let a = m.administrativeArea { qParts.append(a) }
            if let c = m.country, !c.isEmpty { qParts.append(c) } else if let code = m.isoCountryCode { qParts.append(code) }
            appleGeocodedPlaceQuery = qParts.isEmpty ? nil : qParts.joined(separator: ", ")

            let prior = lastGeocodedCityKey
            lastGeocodedCityKey = key
            currentCityKey = key
            currentCityDisplayName = display.isEmpty ? key : display
            if prior != key {
                roadSegments = []
                lastRoadFetchCenter = nil
                lastPOIFetchCenter = nil
                clearCityBoundaryData()
                boundaryFetchCityKey = nil
                Task { await refreshCityBoundary(center: coord, cityKey: key) }
            }
            if let p = try? fetchOrCreateProfile() {
                if p.selectedCityKey == nil { p.selectedCityKey = key }
                if p.homeCityKey == nil { p.homeCityKey = key }
                if p.homeCityDisplayName == nil { p.homeCityDisplayName = display }
                try? modelContext.save()
            }
        } catch {
            // Geocoder failures are common under throttling; ignore silently.
        }
    }

    private func refreshCityBoundaryIfNeeded(center: CLLocationCoordinate2D, cityKey: String) async {
        if boundaryFetchCityKey == cityKey, !cityBoundaryMapRings.isEmpty { return }
        if boundaryFetchCityKey == cityKey, cityBoundaryMapRings.isEmpty, Date().timeIntervalSince(lastBoundaryFetchAt) < 120 {
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
                    if let best = CityBoundaryResolver.pickBestSearchResult(hits),
                       let p2 = CityBoundaryParser.parse(nominatimJSON: best) {
                        candidates.append(p2)
                    }
                }
            }

            let viable = candidates.filter { !CityBoundaryResolver.isTooSmallForCity($0) }
            let chosen = viable.max(by: { CityBoundaryResolver.diagonalMeters(of: $0) < CityBoundaryResolver.diagonalMeters(of: $1) })
                ?? candidates.max(by: { CityBoundaryResolver.diagonalMeters(of: $0) < CityBoundaryResolver.diagonalMeters(of: $1) })

            guard let parsed = chosen else {
                clearCityBoundaryData()
                boundaryFetchCityKey = cityKey
                lastBoundaryFetchAt = Date()
                return
            }

            cityBoundaryPolygons = parsed.polygons
            cityBoundaryMapRings = parsed.mapPolygonOuters
            cityLimitBoundingBox = (parsed.south, parsed.north, parsed.west, parsed.east)
            boundaryFetchCityKey = cityKey
            lastBoundaryFetchAt = Date()
        } catch {
            showMapHint("City outline: \(error.localizedDescription)")
        }
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

    fileprivate func handleLocation(_ location: CLLocation) {
        lastUserLocation = location

        let skipHeavyWork: Bool = {
            guard let prev = lastLocationSample else { return false }
            return location.timestamp.timeIntervalSince(prev.timestamp) < 2 && location.distance(from: prev) < 5
        }()

        if skipHeavyWork {
            recomputeNearbyClaimablePOIs()
            recomputeNearbyPartnersForPassport()
            return
        }

        lastLocationSample = location
        let coord = location.coordinate
        Task {
            await refreshCityKeyIfNeeded(for: coord)
            recomputeNearbyClaimablePOIs()
            recomputeNearbyPartnersForPassport()
        }
        Task { await visitNearestRoadSegment(user: coord) }
    }

    /// Call when opening the Journal so the claim banner matches the latest cache without waiting for GPS.
    func refreshNearbyClaimablePOIs() {
        recomputeNearbyClaimablePOIs()
    }

    /// Call when opening Passport (or after a stamp) so the in-range partner banner stays current.
    func refreshNearbyPartnersForPassport() {
        recomputeNearbyPartnersForPassport()
    }

    /// Mark a visit for one POI when you are within `poiProximityRadiusMeters` (partner stamps auto-add if not already stamped).
    func claimPOI(osmId: String) throws {
        guard let loc = lastUserLocation else {
            struct E: LocalizedError { var errorDescription: String? { "Location is unavailable — enable location services to claim." } }
            throw E()
        }
        guard let cityKey = currentCityKey ?? lastKnownProfile()?.selectedCityKey else {
            struct E: LocalizedError { var errorDescription: String? { "City not ready — open the map briefly so we know where you are." } }
            throw E()
        }
        let id = osmId
        let poiFetch = FetchDescriptor<CachedPOI>(predicate: #Predicate { $0.osmId == id })
        guard let poi = try modelContext.fetch(poiFetch).first else { return }
        if POISyncService.isUnwantedPOIName(poi.name) { return }
        let there = CLLocationCoordinate2D(latitude: poi.latitude, longitude: poi.longitude)
        guard GeoMath.distanceMeters(loc.coordinate, there) <= Self.poiProximityRadiusMeters else {
            struct E: LocalizedError { var errorDescription: String? { "Move closer to this place to claim it." } }
            throw E()
        }
        let discFetch = FetchDescriptor<DiscoveredPlace>(predicate: #Predicate { $0.osmId == id })
        if try modelContext.fetch(discFetch).first != nil {
            recomputeNearbyClaimablePOIs()
            return
        }
        modelContext.insert(DiscoveredPlace(osmId: poi.osmId, cityKey: cityKey))
        if poi.isPartner {
            let stampFetch = FetchDescriptor<StampRecord>(predicate: #Predicate { $0.osmId == id })
            if try modelContext.fetch(stampFetch).first == nil {
                modelContext.insert(StampRecord(osmId: poi.osmId, cityKey: cityKey))
            }
        }
        try modelContext.save()
        recomputeNearbyClaimablePOIs()
    }

    private func recomputeNearbyClaimablePOIs() {
        guard let loc = lastUserLocation else {
            nearbyClaimablePOIs = []
            return
        }
        guard let cityKey = currentCityKey ?? lastKnownProfile()?.selectedCityKey else {
            nearbyClaimablePOIs = []
            return
        }
        do {
            let poiFetch = FetchDescriptor<CachedPOI>(predicate: #Predicate { $0.cityKey == cityKey })
            let all = try modelContext.fetch(poiFetch)
            let discovered = try Set(modelContext.fetch(FetchDescriptor<DiscoveredPlace>()).map(\.osmId))
            let here = loc.coordinate
            nearbyClaimablePOIs = all
                .filter { poi in
                    !POISyncService.isUnwantedPOIName(poi.name)
                        && !discovered.contains(poi.osmId)
                        && GeoMath.distanceMeters(here, CLLocationCoordinate2D(latitude: poi.latitude, longitude: poi.longitude)) <= Self.poiProximityRadiusMeters
                }
                .sorted { a, b in
                    let da = GeoMath.distanceMeters(here, CLLocationCoordinate2D(latitude: a.latitude, longitude: a.longitude))
                    let db = GeoMath.distanceMeters(here, CLLocationCoordinate2D(latitude: b.latitude, longitude: b.longitude))
                    return da < db
                }
        } catch {
            nearbyClaimablePOIs = []
        }
    }

    private func recomputeNearbyPartnersForPassport() {
        guard let loc = lastUserLocation else {
            nearbyPartnerStampOffers = []
            return
        }
        guard currentCityKey != nil || lastKnownProfile()?.selectedCityKey != nil else {
            nearbyPartnerStampOffers = []
            return
        }
        let here = loc.coordinate
        var rows: [(offer: NearbyPartnerStampOffer, distance: Double)] = []
        rows.reserveCapacity(partners.partners.count)
        for entry in partners.partners {
            let token = entry.stampImageName
            guard !token.isEmpty else { continue }
            let pid = entry.osmId
            guard let prox = resolvedPartnerProximity(for: entry, userHere: here) else { continue }
            let d = GeoMath.distanceMeters(here, prox.anchor)
            guard d <= Self.poiProximityRadiusMeters else { continue }
            let name = passportPartnerTitle(entry: entry, venuePOI: prox.venuePOI)
            let scansToday = (try? partnerQRScanCountSameCalendarDay(osmId: pid, referenceDate: .now)) ?? 0
            let canScan = scansToday == 0
            rows.append((
                NearbyPartnerStampOffer(
                    osmId: pid,
                    displayName: name,
                    stampImageName: token,
                    canScanPartnerQRToday: canScan,
                    distanceMeters: d
                ),
                d
            ))
        }
        rows.sort { $0.distance < $1.distance }
        nearbyPartnerStampOffers = rows.map(\.offer)
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
        guard let cityKey = currentCityKey ?? lastKnownProfile()?.selectedCityKey else {
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

    /// Snaps the user to the nearest OSM road segment; awards 1 XP per new segment key.
    private func visitNearestRoadSegment(user: CLLocationCoordinate2D) async {
        guard !roadSegments.isEmpty else { return }
        var best: (POISyncService.RoadSegmentSample, Double)?
        for seg in roadSegments {
            let d = GeoMath.distancePointToSegmentMeters(p: user, a: seg.a, b: seg.b)
            if d < (best?.1 ?? .greatestFiniteMagnitude) {
                best = (seg, d)
            }
        }
        guard let candidate = best, candidate.1 <= 40 else { return }
        let key = "w:\(candidate.0.wayId):i:\(candidate.0.segmentIndex)"
        let fetch = FetchDescriptor<VisitedRoadSegment>(predicate: #Predicate { $0.segmentKey == key })
        if let _ = try? modelContext.fetch(fetch).first { return }

        let coords = [candidate.0.a, candidate.0.b]
        let arr: [[String: Double]] = coords.map { ["lat": $0.latitude, "lon": $0.longitude] }
        let data = (try? JSONSerialization.data(withJSONObject: arr)) ?? Data()
        let row = VisitedRoadSegment(segmentKey: key, wayId: candidate.0.wayId, polylineJSON: data, cityKey: currentCityKey)
        modelContext.insert(row)

        if let profile = try? fetchOrCreateProfile() {
            profile.totalXP += 1
        }

        revealedSegmentCoordinates.append(coords)

        try? modelContext.save()
    }

    /// Validates QR payload, proximity, and one scan per calendar day; appends a `StampRecord`.
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

        let pid = partner.osmId
        guard let prox = resolvedPartnerProximity(for: partner, userHere: loc.coordinate) else {
            throw StampQRScanError.noAnchorCoordinate
        }
        guard GeoMath.distanceMeters(loc.coordinate, prox.anchor) <= Self.poiProximityRadiusMeters else {
            throw StampQRScanError.tooFar
        }

        if try partnerQRScanCountSameCalendarDay(osmId: pid, referenceDate: .now) > 0 {
            throw StampQRScanError.alreadyScannedToday
        }

        let cityKey = currentCityKey ?? prox.venuePOI?.cityKey ?? lastKnownProfile()?.selectedCityKey ?? "map__passport"
        modelContext.insert(StampRecord(osmId: pid, cityKey: cityKey, viaPartnerQR: true))
        try modelContext.save()
        recomputeNearbyPartnersForPassport()
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
        try modelContext.save()
        return true
    }

    func loadPersistedPolylinesIntoMap() throws {
        let rows = try modelContext.fetch(FetchDescriptor<VisitedRoadSegment>())
        var lines: [[CLLocationCoordinate2D]] = []
        lines.reserveCapacity(rows.count)
        for row in rows {
            if let arr = try? JSONSerialization.jsonObject(with: row.polylineJSON) as? [[String: Double]] {
                var coords: [CLLocationCoordinate2D] = []
                for p in arr {
                    if let la = p["lat"], let lo = p["lon"] {
                        coords.append(CLLocationCoordinate2D(latitude: la, longitude: lo))
                    }
                }
                guard coords.count >= 2 else { continue }
                lines.append(coords)
            }
        }
        revealedSegmentCoordinates = lines
    }

    /// Call after `ExplorationProgressReset.clearAllVisitAndExplorationData` so the map and nearby banners match storage.
    func reloadSessionStateAfterDataReset() {
        revealedSegmentCoordinates = []
        try? loadPersistedPolylinesIntoMap()
        refreshNearbyClaimablePOIs()
        refreshNearbyPartnersForPassport()
    }
}

extension ExplorationCoordinator {
    /// In-range catalog partner shown on Passport (Journal-style banner).
    struct NearbyPartnerStampOffer: Identifiable, Hashable {
        var id: String { osmId }
        var osmId: String
        var displayName: String
        var stampImageName: String?
        /// `true` when no partner-QR stamp exists yet for this place today (calendar day).
        var canScanPartnerQRToday: Bool
        var distanceMeters: Double
    }
}

extension ExplorationCoordinator: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
                self.startTracking()
            }
            self.configureBackgroundIfAuthorized()
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
