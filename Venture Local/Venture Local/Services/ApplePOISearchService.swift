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
        .amusementPark, .aquarium, .zoo, .stadium, .musicVenue, .planetarium,
    ])

    static func mergePointsOfInterest(
        region: MKCoordinateRegion,
        cityKey: String,
        chainDetector: ChainDetector,
        partners: PartnerCatalog,
        context: ModelContext,
        priorityCenter: CLLocationCoordinate2D,
        maxItemsToMerge: Int
    ) async throws -> Int {
        let request = MKLocalPointsOfInterestRequest(coordinateRegion: region)
        request.pointOfInterestFilter = poiFilter
        let search = MKLocalSearch(request: request)
        let response = try await search.start()
        let existing = try context.fetch(FetchDescriptor<CachedPOI>(predicate: #Predicate { $0.cityKey == cityKey }))
        var scratch: [(coord: CLLocationCoordinate2D, name: String, categoryRaw: String)] = existing.map {
            (
                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude),
                $0.name,
                $0.categoryRaw
            )
        }
        var inserted = 0

        let mapItems = balancedMapItemsSample(response.mapItems, anchor: priorityCenter, maxCount: max(1, maxItemsToMerge))

        for item in mapItems {
            guard let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { continue }
            if POISyncService.isUnwantedPOIName(name) { continue }
            if PlaceExclusion.shouldExcludeAppleMapItem(name: name, category: item.pointOfInterestCategory) {
                continue
            }
            var category = discoveryCategory(for: item.pointOfInterestCategory)
            if DiscoveryCategory.nameSuggestsFunVenue(name) {
                switch category {
                case .food, .outdoor: break
                default: category = .entertainment
                }
            }
            let coord = item.placemark.coordinate
            guard CLLocationCoordinate2DIsValid(coord) else { continue }
            if POISyncService.isDuplicateAgainstPOISnapshot(
                coordinate: coord,
                name: name,
                category: category,
                snapshot: scratch
            ) { continue }

            let osmId = stableApplePOIId(name: name, coordinate: coord)
            let chain = chainDetector.evaluate(name: name, tags: [:])
            if chain.0 {
                if let existing = try context.fetch(FetchDescriptor<CachedPOI>(predicate: #Predicate { $0.osmId == osmId })).first {
                    context.delete(existing)
                }
                continue
            }
            let partner = partners.matchPartnerPOI(name: name, osmId: osmId)
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
                row.stampCode = partner?.stampCodeForStorage
                row.addressSummary = addr.isEmpty ? nil : addr
                row.cacheDate = .now
                row.cityKey = cityKey
                Self.applyMapKitMetadata(to: row, pointOfInterestCategory: item.pointOfInterestCategory)
            } else {
                let newRow = CachedPOI(
                    osmId: osmId,
                    name: name,
                    latitude: coord.latitude,
                    longitude: coord.longitude,
                    categoryRaw: category.rawValue,
                    isChain: chain.0,
                    chainLabel: chain.1,
                    isPartner: partner != nil,
                    partnerOffer: partner?.offer,
                    stampCode: partner?.stampCodeForStorage,
                    addressSummary: addr.isEmpty ? nil : addr,
                    cacheDate: .now,
                    cityKey: cityKey
                )
                Self.applyMapKitMetadata(to: newRow, pointOfInterestCategory: item.pointOfInterestCategory)
                context.insert(newRow)
                inserted += 1
            }
            scratch.append((coord, name, category.rawValue))
        }
        return inserted
    }

    /// Prefer POIs near the user; sprinkle in farther results so the set isn’t only one cluster.
    private static func balancedMapItemsSample(_ items: [MKMapItem], anchor: CLLocationCoordinate2D, maxCount: Int) -> [MKMapItem] {
        guard maxCount > 0 else { return [] }
        let valid = items.filter { CLLocationCoordinate2DIsValid($0.placemark.coordinate) }
        guard valid.count > maxCount else { return valid }
        let sorted = valid.sorted {
            GeoMath.distanceMeters($0.placemark.coordinate, anchor) < GeoMath.distanceMeters($1.placemark.coordinate, anchor)
        }
        let nearN = max(1, Int(Double(maxCount) * 0.72))
        var out: [MKMapItem] = []
        out.append(contentsOf: sorted.prefix(nearN))
        var remainder = Array(sorted.dropFirst(min(nearN, sorted.count)))
        var farSlots = maxCount - out.count
        if farSlots > 0, !remainder.isEmpty {
            let step = max(1, remainder.count / farSlots)
            var i = 0
            while out.count < maxCount, i < remainder.count {
                out.append(remainder[i])
                i += step
            }
        }
        if out.count < maxCount {
            var seen = Set(out.map(mapItemDedupKey))
            for item in sorted where out.count < maxCount {
                let k = mapItemDedupKey(item)
                guard seen.insert(k).inserted else { continue }
                out.append(item)
            }
        }
        return Array(out.prefix(maxCount))
    }

    private static func mapItemDedupKey(_ item: MKMapItem) -> String {
        let c = item.placemark.coordinate
        let n = (item.name ?? "").lowercased()
        return String(format: "%.5f,%.5f|%@", c.latitude, c.longitude, n)
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

    private static func discoveryCategory(for mk: MKPointOfInterestCategory?) -> DiscoveryCategory {
        guard let mk else { return .hiddenGems }
        if [.restaurant, .cafe, .bakery, .brewery, .foodMarket, .winery].contains(mk) { return .food }
        if [.library].contains(mk) { return .hiddenGems }
        if [
            .museum, .theater, .movieTheater, .nightlife, .planetarium, .musicVenue,
            .amusementPark, .aquarium, .zoo, .stadium,
        ].contains(mk) { return .entertainment }
        if [.nationalPark, .park, .beach].contains(mk) { return .outdoor }
        if [.store].contains(mk) { return .shopping }
        return .hiddenGems
    }

    private static func applyMapKitMetadata(to row: CachedPOI, pointOfInterestCategory: MKPointOfInterestCategory?) {
        let desc = pointOfInterestCategory.map { String(describing: $0) } ?? "none"
        row.extendedMetadataJSON = POIExtendedMetadataCodec.mergeMapKit(into: row.extendedMetadataJSON, categoryDescription: desc)
    }
}
