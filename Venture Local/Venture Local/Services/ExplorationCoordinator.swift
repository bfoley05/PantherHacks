//
//  ExplorationCoordinator.swift
//  Venture Local
//
//  Ties together location, Overpass sync, road XP, and POI discovery within 10m.
//

import CoreLocation
import Foundation
import MapKit
import Observation
import SwiftData

@Observable @MainActor
final class ExplorationCoordinator: NSObject {
    private let modelContext: ModelContext
    private let chainDetector = ChainDetector()
    private let partners = PartnerCatalog.load(from: .main)
    private let overpass = OverpassClient()

    private let geocoder = CLGeocoder()
    private var lastGeocodeTime: Date = .distantPast

    private var roadSegments: [POISyncService.RoadSegmentSample] = []
    private var lastRoadFetchCenter: CLLocationCoordinate2D?
    private var lastPOIFetchCenter: CLLocationCoordinate2D?
    private var lastLocationSample: CLLocation?

    let locationManager = CLLocationManager()

    var currentCityKey: String?
    var currentCityDisplayName: String?
    var lastErrorMessage: String?
    var isSyncingPOIs: Bool = false
    var isSyncingRoads: Bool = false
    var lastUserLocation: CLLocation?

    /// Revealed road segments as coordinates for `MapPolyline` (persisted + session).
    var revealedSegmentCoordinates: [[CLLocationCoordinate2D]] = []

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 12
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

    /// Call when the map camera settles; fetches POIs + roads for the visible region.
    func syncRegion(_ region: MKCoordinateRegion) async {
        let center = region.center
        let latDelta = max(region.span.latitudeDelta, 0.01)
        let lonDelta = max(region.span.longitudeDelta, 0.01)
        let south = center.latitude - latDelta / 2
        let north = center.latitude + latDelta / 2
        let west = center.longitude - lonDelta / 2
        let east = center.longitude + lonDelta / 2

        await refreshCityKeyIfNeeded(for: center)

        guard let cityKey = currentCityKey ?? lastKnownProfile()?.selectedCityKey else {
            lastErrorMessage = "City not resolved yet — pan the map or enable location."
            return
        }

        if shouldFetchPOIs(center: center) {
            isSyncingPOIs = true
            defer { isSyncingPOIs = false }
            do {
                try POISyncService.purgeStalePOIs(olderThan: 7, in: modelContext)
                let ql = OverpassClient.poiQuery(south: south, west: west, north: north, east: east)
                let data = try await overpass.runQuery(ql)
                _ = try POISyncService.mergePOIs(from: data, cityKey: cityKey, chainDetector: chainDetector, partners: partners, into: modelContext)
                try modelContext.save()
                lastPOIFetchCenter = center
            } catch {
                lastErrorMessage = "POI sync failed: \(error.localizedDescription)"
            }
        }

        if shouldFetchRoads(center: center) {
            isSyncingRoads = true
            defer { isSyncingRoads = false }
            do {
                let ql = OverpassClient.roadQuery(south: south, west: west, north: north, east: east)
                let data = try await overpass.runQuery(ql)
                roadSegments = try POISyncService.decodeRoadSegments(from: data)
                lastRoadFetchCenter = center
            } catch {
                lastErrorMessage = "Road sync failed: \(error.localizedDescription)"
            }
        }
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
        guard now.timeIntervalSince(lastGeocodeTime) > 25 else { return }
        lastGeocodeTime = now
        let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        do {
            let marks = try await geocoder.reverseGeocodeLocation(loc)
            guard let m = marks.first else { return }
            let key = CityKey.make(locality: m.locality, administrativeArea: m.administrativeArea, country: m.isoCountryCode)
            let display = [m.locality, m.administrativeArea].compactMap { $0 }.joined(separator: ", ")
            currentCityKey = key
            currentCityDisplayName = display.isEmpty ? key : display
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

    private func lastKnownProfile() -> ExplorerProfile? {
        try? modelContext.fetch(FetchDescriptor<ExplorerProfile>()).first
    }

    fileprivate func handleLocation(_ location: CLLocation) {
        if let prev = lastLocationSample, location.timestamp.timeIntervalSince(prev.timestamp) < 2, location.distance(from: prev) < 5 {
            return
        }
        lastLocationSample = location
        lastUserLocation = location
        let coord = location.coordinate
        Task { await refreshCityKeyIfNeeded(for: coord) }
        Task { await visitNearestRoadSegment(user: coord) }
        try? discoverNearbyPOIs(user: location)
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

    /// No bulk radius discovery: only POIs whose coordinate is within 10m of the user.
    private func discoverNearbyPOIs(user: CLLocation) throws {
        let city = currentCityKey ?? lastKnownProfile()?.selectedCityKey
        guard let cityKey = city else { return }
        let fd = FetchDescriptor<CachedPOI>(predicate: #Predicate { $0.cityKey == cityKey })
        let all = try modelContext.fetch(fd)
        let here = user.coordinate
        for poi in all {
            let there = CLLocationCoordinate2D(latitude: poi.latitude, longitude: poi.longitude)
            let meters = GeoMath.distanceMeters(here, there)
            guard meters <= 10 else { continue }

            let discId = poi.osmId
            let fd = FetchDescriptor<DiscoveredPlace>(predicate: #Predicate { $0.osmId == discId })
            if (try modelContext.fetch(fd).first) != nil {
                continue
            }

            modelContext.insert(DiscoveredPlace(osmId: poi.osmId, cityKey: cityKey))

            if poi.isPartner {
                let stamp = StampRecord(osmId: poi.osmId, cityKey: cityKey)
                modelContext.insert(stamp)
            }
        }
        try modelContext.save()
    }

    func collectStamp(for poi: CachedPOI, user: CLLocation) throws -> Bool {
        guard poi.isPartner else { return false }
        let here = user.coordinate
        let there = CLLocationCoordinate2D(latitude: poi.latitude, longitude: poi.longitude)
        guard GeoMath.distanceMeters(here, there) <= 10 else { return false }
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
            self.lastErrorMessage = error.localizedDescription
        }
    }
}
