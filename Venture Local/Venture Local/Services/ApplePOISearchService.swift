//
//  ApplePOISearchService.swift
//  Venture Local
//
//  Supplements Overpass with MapKit local POIs (often better coverage for named businesses).
//

import CoreLocation
import Foundation
import MapKit
import SwiftData

enum ApplePOISearchService {
    /// Categories we care about for Venture Local discovery.
    private static let poiFilter = MKPointOfInterestFilter(including: [
        .restaurant, .cafe, .bakery, .brewery, .winery, .foodMarket,
        .museum, .nationalPark, .park, .beach, .theater, .movieTheater,
        .library, .store, .nightlife,
    ])

    static func mergePointsOfInterest(
        region: MKCoordinateRegion,
        cityKey: String,
        chainDetector: ChainDetector,
        partners: PartnerCatalog,
        context: ModelContext
    ) async throws -> Int {
        let request = MKLocalPointsOfInterestRequest(coordinateRegion: region)
        request.pointOfInterestFilter = poiFilter
        let search = MKLocalSearch(request: request)
        let response = try await search.start()
        let existing = try context.fetch(FetchDescriptor<CachedPOI>(predicate: #Predicate { $0.cityKey == cityKey }))
        var scratch: [(coord: CLLocationCoordinate2D, name: String)] = existing.map {
            (CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude), $0.name)
        }
        var inserted = 0

        for item in response.mapItems {
            guard let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { continue }
            if POISyncService.isUnwantedPOIName(name) { continue }
            if PlaceExclusion.shouldExcludeAppleMapItem(name: name, category: item.pointOfInterestCategory) {
                continue
            }
            let category = discoveryCategory(for: item.pointOfInterestCategory)
            let coord = item.placemark.coordinate
            guard CLLocationCoordinate2DIsValid(coord) else { continue }
            if nearDuplicate(coordinate: coord, name: name, in: scratch) { continue }

            let osmId = stableApplePOIId(name: name, coordinate: coord)
            let chain = chainDetector.evaluate(name: name, tags: [:])
            let partner = partners.match(osmId: osmId)
            let addr = [
                item.placemark.subThoroughfare,
                item.placemark.thoroughfare,
                item.placemark.locality,
            ].compactMap { $0 }.joined(separator: " ")

            let fetch = FetchDescriptor<CachedPOI>(predicate: #Predicate { $0.osmId == osmId })
            if let row = try context.fetch(fetch).first {
                row.name = name
                row.latitude = coord.latitude
                row.longitude = coord.longitude
                row.categoryRaw = category.rawValue
                row.isChain = chain.0
                row.chainLabel = chain.1
                row.isPartner = partner != nil
                row.partnerOffer = partner?.offer
                row.stampCode = partner.map(\.stampImageName).flatMap { $0.isEmpty ? nil : $0 }
                row.addressSummary = addr.isEmpty ? nil : addr
                row.cacheDate = .now
                row.cityKey = cityKey
            } else {
                context.insert(
                    CachedPOI(
                        osmId: osmId,
                        name: name,
                        latitude: coord.latitude,
                        longitude: coord.longitude,
                        categoryRaw: category.rawValue,
                        isChain: chain.0,
                        chainLabel: chain.1,
                        isPartner: partner != nil,
                        partnerOffer: partner?.offer,
                        stampCode: partner.map(\.stampImageName).flatMap { $0.isEmpty ? nil : $0 },
                        addressSummary: addr.isEmpty ? nil : addr,
                        cacheDate: .now,
                        cityKey: cityKey
                    )
                )
                inserted += 1
            }
            scratch.append((coord, name))
        }
        return inserted
    }

    private static func stableApplePOIId(name: String, coordinate: CLLocationCoordinate2D) -> String {
        let la = String(format: "%.5f", coordinate.latitude)
        let lo = String(format: "%.5f", coordinate.longitude)
        let slug = name.lowercased()
            .filter { $0.isLetter || $0.isNumber || $0 == " " }
            .prefix(40)
            .replacingOccurrences(of: " ", with: "_")
        return "apple:\(la):\(lo):\(slug)"
    }

    private static func nearDuplicate(coordinate: CLLocationCoordinate2D, name: String, in scratch: [(coord: CLLocationCoordinate2D, name: String)]) -> Bool {
        let n = name.lowercased()
        for e in scratch {
            let d = GeoMath.distanceMeters(coordinate, e.coord)
            if d > 75 { continue }
            let en = e.name.lowercased()
            if en == n || n.contains(en) || en.contains(n) { return true }
        }
        return false
    }

    private static func discoveryCategory(for mk: MKPointOfInterestCategory?) -> DiscoveryCategory {
        guard let mk else { return .hiddenGems }
        if [.restaurant, .cafe, .bakery, .brewery, .foodMarket, .winery].contains(mk) { return .food }
        if [.museum, .theater, .movieTheater, .nightlife].contains(mk) { return .entertainment }
        if [.nationalPark, .park, .beach].contains(mk) { return .outdoor }
        if [.store].contains(mk) { return .shopping }
        return .hiddenGems
    }
}
