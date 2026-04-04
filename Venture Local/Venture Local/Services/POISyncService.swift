//
//  POISyncService.swift
//  Venture Local
//
//  Decodes Overpass elements into CachedPOI rows with category + chain detection.
//

import CoreLocation
import Foundation
import SwiftData

enum POISyncService {
    /// Names we never store or show (OSM/MapKit placeholders).
    static func isUnwantedPOIName(_ raw: String) -> Bool {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.isEmpty { return true }
        if t == "unknown" || t.hasPrefix("unknown ") { return true }
        if t == "unnamed" || t == "unnamed place" || t.hasPrefix("unnamed ") { return true }
        return false
    }

    struct RoadSegmentSample: Sendable {
        var wayId: Int64
        var segmentIndex: Int
        var a: CLLocationCoordinate2D
        var b: CLLocationCoordinate2D
    }

    static func decodeRoadSegments(from data: Data) throws -> [RoadSegmentSample] {
        let resp = try JSONDecoder().decode(OverpassResponse.self, from: data)
        var out: [RoadSegmentSample] = []
        out.reserveCapacity(resp.elements.count * 4)
        for el in resp.elements {
            guard el.type == "way", let geom = el.geometry, geom.count >= 2 else { continue }
            for i in 0 ..< (geom.count - 1) {
                let a = CLLocationCoordinate2D(latitude: geom[i].lat, longitude: geom[i].lon)
                let b = CLLocationCoordinate2D(latitude: geom[i + 1].lat, longitude: geom[i + 1].lon)
                out.append(RoadSegmentSample(wayId: el.id, segmentIndex: i, a: a, b: b))
            }
        }
        return out
    }

    static func mergePOIs(from data: Data, cityKey: String, chainDetector: ChainDetector, partners: PartnerCatalog, into context: ModelContext) throws -> Int {
        let resp = try JSONDecoder().decode(OverpassResponse.self, from: data)
        var inserted = 0
        for el in resp.elements {
            guard el.type == "node" || el.type == "way" else { continue }
            let tags = el.tags ?? [:]
            if PlaceExclusion.shouldExcludeOSMTags(tags) { continue }
            guard let category = DiscoveryCategory.fromOSMTags(tags) else { continue }
            let coord: CLLocationCoordinate2D? = {
                if let la = el.lat, let lo = el.lon { return CLLocationCoordinate2D(latitude: la, longitude: lo) }
                if let c = el.center { return CLLocationCoordinate2D(latitude: c.lat, longitude: c.lon) }
                return nil
            }()
            guard let coord else { continue }
            let name = tags["name"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName: String = {
                guard let name, !name.isEmpty else { return "" }
                return name
            }()
            if Self.isUnwantedPOIName(displayName) { continue }
            let osmId = "\(el.type)/\(el.id)"
            let chain = chainDetector.evaluate(name: displayName, tags: tags)
            let partner = partners.match(osmId: osmId)
            let isPartner = partner != nil
            let offer = partner?.offer
            let stamp = partner.map(\.stampImageName).flatMap { $0.isEmpty ? nil : $0 }
            let addr = [tags["addr:housenumber"], tags["addr:street"], tags["addr:city"]].compactMap { $0 }.joined(separator: " ")

            let fetch = FetchDescriptor<CachedPOI>(predicate: #Predicate { $0.osmId == osmId })
            if let existing = try context.fetch(fetch).first {
                existing.name = displayName
                existing.latitude = coord.latitude
                existing.longitude = coord.longitude
                existing.categoryRaw = category.rawValue
                existing.isChain = chain.0
                existing.chainLabel = chain.1
                existing.isPartner = isPartner
                existing.partnerOffer = offer
                existing.stampCode = stamp
                existing.addressSummary = addr.isEmpty ? nil : addr
                existing.cacheDate = .now
                existing.cityKey = cityKey
            } else {
                let row = CachedPOI(
                    osmId: osmId,
                    name: displayName,
                    latitude: coord.latitude,
                    longitude: coord.longitude,
                    categoryRaw: category.rawValue,
                    isChain: chain.0,
                    chainLabel: chain.1,
                    isPartner: isPartner,
                    partnerOffer: offer,
                    stampCode: stamp,
                    addressSummary: addr.isEmpty ? nil : addr,
                    cacheDate: .now,
                    cityKey: cityKey
                )
                context.insert(row)
                inserted += 1
            }
        }
        return inserted
    }

    static func purgeStalePOIs(olderThan days: Int, in context: ModelContext) throws {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .distantPast
        let fetch = FetchDescriptor<CachedPOI>(predicate: #Predicate { $0.cacheDate < cutoff })
        let old = try context.fetch(fetch)
        for o in old { context.delete(o) }
    }
}
