//
//  OverpassMergePayloadFactory.swift
//  Venture Local
//
//  Heavy Overpass JSON parsing lives here without `import SwiftData` so work can run in `Task.detached`
//  without Swift 6 main-actor isolation on `POISyncService` static helpers.
//

import CoreLocation
import Foundation

struct OverpassMergeRow: Sendable {
    let osmId: String
    let displayName: String
    let latitude: Double
    let longitude: Double
    let categoryRaw: String
    let isChain: Bool
    let chainLabel: String?
    let isPartner: Bool
    let partnerOffer: String?
    let stampCode: String?
    let addressSummary: String?
    let osmTagSlice: [String: String]
}

struct OverpassMergePayload: Sendable {
    let chainOsmIdsToPurge: [String]
    let rows: [OverpassMergeRow]
}

/// Road polyline sample decoded from Overpass (kept out of ``POISyncService`` for background decoding).
struct OverpassRoadSegment: Sendable {
    var wayId: Int64
    var segmentIndex: Int
    var a: CLLocationCoordinate2D
    var b: CLLocationCoordinate2D
}

private struct PendingOverpassPOI {
    let osmId: String
    let displayName: String
    let coord: CLLocationCoordinate2D
    let category: DiscoveryCategory
    let isChain: Bool
    let chainLabel: String?
    let isPartner: Bool
    let partnerOffer: String?
    let stampCode: String?
    let addressSummary: String?
    let osmTagSlice: [String: String]
}

enum OverpassMergePayloadFactory {
    private static let dedupeGridStepDegrees = 0.00055

    private static func dedupeGridKey(_ c: CLLocationCoordinate2D) -> String {
        let gr = (c.latitude / dedupeGridStepDegrees).rounded(.down)
        let gc = (c.longitude / dedupeGridStepDegrees).rounded(.down)
        return "\(gr)_\(gc)"
    }

    private static func preferPendingRepresentative(_ a: PendingOverpassPOI, _ b: PendingOverpassPOI) -> PendingOverpassPOI {
        if a.isPartner != b.isPartner { return a.isPartner ? a : b }
        if a.displayName.count != b.displayName.count { return a.displayName.count >= b.displayName.count ? a : b }
        return a.osmId < b.osmId ? a : b
    }

    private static func balancedNearAndFarSelection(_ items: [PendingOverpassPOI], priorityCenter: CLLocationCoordinate2D?, maxCount: Int) -> [PendingOverpassPOI] {
        guard maxCount > 0 else { return [] }
        guard items.count > maxCount else { return items }
        guard let anchor = priorityCenter else {
            return Array(items.prefix(maxCount))
        }
        var unique: [String: PendingOverpassPOI] = [:]
        for p in items { unique[p.osmId] = p }
        let sorted = unique.values.sorted {
            GeoMath.distanceMeters($0.coord, anchor) < GeoMath.distanceMeters($1.coord, anchor)
        }
        let nearShare = 0.72
        let nearN = max(1, Int(Double(maxCount) * nearShare))
        var out: [PendingOverpassPOI] = []
        out.append(contentsOf: sorted.prefix(nearN))
        let remainder = Array(sorted.dropFirst(min(nearN, sorted.count)))
        let farSlots = maxCount - out.count
        if farSlots > 0, !remainder.isEmpty {
            let step = max(1, remainder.count / farSlots)
            var i = 0
            while out.count < maxCount, i < remainder.count {
                out.append(remainder[i])
                i += step
            }
        }
        if out.count < maxCount {
            var seen = Set(out.map(\.osmId))
            for p in sorted where out.count < maxCount {
                guard seen.insert(p.osmId).inserted else { continue }
                out.append(p)
            }
        }
        return Array(out.prefix(maxCount))
    }

    private static func dedupePendingForStorage(_ items: [PendingOverpassPOI]) -> [PendingOverpassPOI] {
        guard items.count > 1 else { return items }
        var buckets: [String: [PendingOverpassPOI]] = [:]
        for p in items {
            buckets[dedupeGridKey(p.coord), default: []].append(p)
        }
        var out: [PendingOverpassPOI] = []
        for (_, bucket) in buckets {
            var kept: [PendingOverpassPOI] = []
            for p in bucket {
                if let i = kept.firstIndex(where: { q in
                    OverpassPlaceDedupe.coordinatesAndNamesSuggestSamePlace(
                        p.coord, nameA: p.displayName, categoryRawA: p.category.rawValue,
                        q.coord, nameB: q.displayName, categoryRawB: q.category.rawValue
                    )
                }) {
                    kept[i] = preferPendingRepresentative(p, kept[i])
                } else {
                    kept.append(p)
                }
            }
            out.append(contentsOf: kept)
        }
        return out
    }

    static func buildOverpassMergePayload(
        from data: Data,
        chainDetector: ChainDetector,
        partners: PartnerCatalog,
        priorityCenter: CLLocationCoordinate2D?,
        maxPlacesToPersist: Int?
    ) throws -> OverpassMergePayload {
        let resp = try JSONDecoder().decode(OverpassResponse.self, from: data)
        var pending: [PendingOverpassPOI] = []
        var chainOsmIds = Set<String>()
        pending.reserveCapacity(min(resp.elements.count, maxPlacesToPersist ?? 1024))

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
            if OverpassPlaceDedupe.isUnwantedPOIName(displayName) { continue }
            let osmId = "\(el.type)/\(el.id)"
            let chain = chainDetector.evaluate(name: displayName, tags: tags)
            if chain.0 {
                chainOsmIds.insert(osmId)
                continue
            }
            let partner = partners.matchPartnerPOI(name: displayName, osmId: osmId)
            let isPartner = partner != nil
            let offer = partner?.offer
            let stamp = partner?.stampCodeForStorage
            let addr = [tags["addr:housenumber"], tags["addr:street"], tags["addr:city"]].compactMap { $0 }.joined(separator: " ")
            let tagSlice = POIExtendedMetadataCodec.osmTagSlice(from: tags)

            pending.append(
                PendingOverpassPOI(
                    osmId: osmId,
                    displayName: displayName,
                    coord: coord,
                    category: category,
                    isChain: chain.0,
                    chainLabel: chain.1,
                    isPartner: isPartner,
                    partnerOffer: offer,
                    stampCode: stamp,
                    addressSummary: addr.isEmpty ? nil : addr,
                    osmTagSlice: tagSlice
                )
            )
        }

        let selected: [PendingOverpassPOI] = {
            guard let cap = maxPlacesToPersist, pending.count > cap else { return pending }
            return balancedNearAndFarSelection(pending, priorityCenter: priorityCenter, maxCount: cap)
        }()
        let dedupedSelected = dedupePendingForStorage(selected)

        let rows = dedupedSelected.map { p in
            OverpassMergeRow(
                osmId: p.osmId,
                displayName: p.displayName,
                latitude: p.coord.latitude,
                longitude: p.coord.longitude,
                categoryRaw: p.category.rawValue,
                isChain: p.isChain,
                chainLabel: p.chainLabel,
                isPartner: p.isPartner,
                partnerOffer: p.partnerOffer,
                stampCode: p.stampCode,
                addressSummary: p.addressSummary,
                osmTagSlice: p.osmTagSlice
            )
        }
        return OverpassMergePayload(chainOsmIdsToPurge: Array(chainOsmIds), rows: rows)
    }

    /// Full scan (no persistence cap): same inclusion rules as map merge, for journal city denominators.
    static func countNonChainLocalsFromOverpassData(
        _ data: Data,
        chainDetector: ChainDetector,
        partners: PartnerCatalog
    ) throws -> (total: Int, perCategory: [String: Int]) {
        let resp = try JSONDecoder().decode(OverpassResponse.self, from: data)
        var perCategory: [String: Int] = [:]
        var total = 0
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
            guard coord != nil else { continue }
            let name = tags["name"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName: String = {
                guard let name, !name.isEmpty else { return "" }
                return name
            }()
            if OverpassPlaceDedupe.isUnwantedPOIName(displayName) { continue }
            let osmId = "\(el.type)/\(el.id)"
            let chain = chainDetector.evaluate(name: displayName, tags: tags)
            if chain.0 { continue }
            _ = partners.matchPartnerPOI(name: displayName, osmId: osmId)
            perCategory[category.rawValue, default: 0] += 1
            total += 1
        }
        return (total, perCategory)
    }

    static func decodeRoadSegments(from data: Data) throws -> [OverpassRoadSegment] {
        let resp = try JSONDecoder().decode(OverpassResponse.self, from: data)
        var out: [OverpassRoadSegment] = []
        out.reserveCapacity(resp.elements.count * 4)
        for el in resp.elements {
            guard el.type == "way", let geom = el.geometry, geom.count >= 2 else { continue }
            for i in 0 ..< (geom.count - 1) {
                let a = CLLocationCoordinate2D(latitude: geom[i].lat, longitude: geom[i].lon)
                let b = CLLocationCoordinate2D(latitude: geom[i + 1].lat, longitude: geom[i + 1].lon)
                out.append(OverpassRoadSegment(wayId: el.id, segmentIndex: i, a: a, b: b))
            }
        }
        return out
    }

    static func capRoadSegments(
        _ segments: [OverpassRoadSegment],
        priorityCenter: CLLocationCoordinate2D,
        maxCount: Int
    ) -> [OverpassRoadSegment] {
        guard maxCount > 0, segments.count > maxCount else { return segments }
        let sorted = segments.sorted {
            let da = min(GeoMath.distanceMeters(priorityCenter, $0.a), GeoMath.distanceMeters(priorityCenter, $0.b))
            let db = min(GeoMath.distanceMeters(priorityCenter, $1.a), GeoMath.distanceMeters(priorityCenter, $1.b))
            return da < db
        }
        let nearN = max(1, Int(Double(maxCount) * 0.78))
        var out: [OverpassRoadSegment] = []
        out.append(contentsOf: sorted.prefix(nearN))
        let remainder = Array(sorted.dropFirst(min(nearN, sorted.count)))
        let farSlots = maxCount - out.count
        if farSlots > 0, !remainder.isEmpty {
            let step = max(1, remainder.count / farSlots)
            var i = 0
            while out.count < maxCount, i < remainder.count {
                out.append(remainder[i])
                i += step
            }
        }
        if out.count < maxCount {
            var seen = Set(out.map { "\($0.wayId):\($0.segmentIndex)" })
            for s in sorted where out.count < maxCount {
                let k = "\(s.wayId):\(s.segmentIndex)"
                guard seen.insert(k).inserted else { continue }
                out.append(s)
            }
        }
        return Array(out.prefix(maxCount))
    }
}
