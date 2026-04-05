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
    // MARK: - Cross-source deduplication (Overpass + Apple MapKit)

    /// Lowercase, diacritic-folded, alphanumeric tokens — comparable across OSM vs Apple naming.
    static func normalizedPlaceName(_ raw: String) -> String {
        let folded = raw.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
        let parts = folded.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        return parts.joined(separator: " ")
    }

    private static func tokenJaccard(_ normalizedA: String, _ normalizedB: String) -> Double {
        let a = Set(normalizedA.split(separator: " ").map(String.init))
        let b = Set(normalizedB.split(separator: " ").map(String.init))
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        let i = a.intersection(b).count
        return Double(i) / Double(a.union(b).count)
    }

    private static func levenshteinRatio(_ s1: String, _ s2: String) -> Double {
        let a = Array(s1)
        let b = Array(s2)
        let m = a.count, n = b.count
        if m == 0 { return n == 0 ? 1 : 0 }
        if n == 0 { return 0 }
        var dp = Array(0 ... n)
        for i in 1 ... m {
            var prev = dp[0]
            dp[0] = i
            for j in 1 ... n {
                let temp = dp[j]
                if a[i - 1] == b[j - 1] {
                    dp[j] = prev
                } else {
                    dp[j] = min(prev + 1, dp[j] + 1, dp[j - 1] + 1)
                }
                prev = temp
            }
        }
        let dist = dp[n]
        return 1.0 - Double(dist) / Double(max(m, n))
    }

    /// True when two pins are likely the same venue despite OSM vs Apple naming differences.
    static func coordinatesAndNamesSuggestSamePlace(
        _ coordA: CLLocationCoordinate2D, nameA: String, categoryRawA: String,
        _ coordB: CLLocationCoordinate2D, nameB: String, categoryRawB: String
    ) -> Bool {
        let d = GeoMath.distanceMeters(coordA, coordB)
        let sameCategory = categoryRawA == categoryRawB
        let na = normalizedPlaceName(nameA)
        let nb = normalizedPlaceName(nameB)

        if na.isEmpty, nb.isEmpty { return d <= 22 }
        if na == nb, d <= 92 { return true }

        let shorter = na.count <= nb.count ? na : nb
        let longer = na.count <= nb.count ? nb : na
        if shorter.count >= 4, longer.contains(shorter), d <= 82 { return true }

        let j = tokenJaccard(na, nb)
        if sameCategory {
            if j >= 0.72, d <= 76 { return true }
            if j >= 0.5, d <= 48 { return true }
            if j >= 0.34, d <= 30 { return true }
        } else {
            if j >= 0.82, d <= 52 { return true }
        }

        let ca = na.filter { $0.isLetter || $0.isNumber }
        let cb = nb.filter { $0.isLetter || $0.isNumber }
        if ca.count >= 5, cb.count >= 5, d <= 44 {
            if levenshteinRatio(String(ca), String(cb)) >= 0.88 { return true }
        }

        return false
    }

    /// Used when merging Apple POIs against SwiftData + in-memory scratch rows.
    static func isDuplicateAgainstPOISnapshot(
        coordinate: CLLocationCoordinate2D,
        name: String,
        category: DiscoveryCategory,
        snapshot: [(coord: CLLocationCoordinate2D, name: String, categoryRaw: String)]
    ) -> Bool {
        snapshot.contains { e in
            coordinatesAndNamesSuggestSamePlace(
                coordinate, nameA: name, categoryRawA: category.rawValue,
                e.coord, nameB: e.name, categoryRawB: e.categoryRaw
            )
        }
    }

    /// Re-point user-linked rows from an Apple-only map pin id to a stable Overpass `osmId`.
    static func migrateOsmIdReferences(from oldId: String, to newId: String, in context: ModelContext) throws {
        guard oldId != newId, oldId.hasPrefix("apple:") else { return }

        func moveOrDropUniqueOld<Row>(
            oldRows: [Row],
            newExists: Bool,
            delete: (Row) -> Void,
            reassign: (Row) -> Void
        ) {
            for r in oldRows {
                if !newExists { reassign(r) } else { delete(r) }
            }
        }

        let oldDisc = try context.fetch(FetchDescriptor<DiscoveredPlace>(predicate: #Predicate { $0.osmId == oldId }))
        let newDiscExists = try !context.fetch(FetchDescriptor<DiscoveredPlace>(predicate: #Predicate { $0.osmId == newId })).isEmpty
        moveOrDropUniqueOld(oldRows: oldDisc, newExists: newDiscExists, delete: context.delete) { $0.osmId = newId }

        let oldSaved = try context.fetch(FetchDescriptor<SavedPlace>(predicate: #Predicate { $0.osmId == oldId }))
        let newSavedExists = try !context.fetch(FetchDescriptor<SavedPlace>(predicate: #Predicate { $0.osmId == newId })).isEmpty
        moveOrDropUniqueOld(oldRows: oldSaved, newExists: newSavedExists, delete: context.delete) { $0.osmId = newId }

        let oldFav = try context.fetch(FetchDescriptor<FavoritePlace>(predicate: #Predicate { $0.osmId == oldId }))
        let newFavExists = try !context.fetch(FetchDescriptor<FavoritePlace>(predicate: #Predicate { $0.osmId == newId })).isEmpty
        moveOrDropUniqueOld(oldRows: oldFav, newExists: newFavExists, delete: context.delete) { $0.osmId = newId }

        let oldPhoto = try context.fetch(FetchDescriptor<PlacePhotoCheckIn>(predicate: #Predicate { $0.osmId == oldId }))
        let newPhotoExists = try !context.fetch(FetchDescriptor<PlacePhotoCheckIn>(predicate: #Predicate { $0.osmId == newId })).isEmpty
        moveOrDropUniqueOld(oldRows: oldPhoto, newExists: newPhotoExists, delete: context.delete) { $0.osmId = newId }

        let stamps = try context.fetch(FetchDescriptor<StampRecord>(predicate: #Predicate { $0.osmId == oldId }))
        for s in stamps { s.osmId = newId }

        let events = try context.fetch(FetchDescriptor<ExplorerEvent>(predicate: #Predicate { $0.osmId == oldId }))
        for e in events { e.osmId = newId }
    }

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

    private struct PendingPOI {
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
    }

    /// Keeps most slots for places near `priorityCenter`, then samples farther POIs so the map isn’t empty at the edges.
    private static func balancedNearAndFarSelection(_ items: [PendingPOI], priorityCenter: CLLocationCoordinate2D?, maxCount: Int) -> [PendingPOI] {
        guard maxCount > 0 else { return [] }
        guard items.count > maxCount else { return items }
        guard let anchor = priorityCenter else {
            return Array(items.prefix(maxCount))
        }
        var unique: [String: PendingPOI] = [:]
        for p in items { unique[p.osmId] = p }
        let sorted = unique.values.sorted {
            GeoMath.distanceMeters($0.coord, anchor) < GeoMath.distanceMeters($1.coord, anchor)
        }
        let nearShare = 0.72
        let nearN = max(1, Int(Double(maxCount) * nearShare))
        var out: [PendingPOI] = []
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

    /// Merges Overpass results into SwiftData. When `maxPlacesToPersist` is set, only the nearest-majority + a spread of farther places are written (avoids freezing on huge bbox responses).
    static func mergePOIs(
        from data: Data,
        cityKey: String,
        chainDetector: ChainDetector,
        partners: PartnerCatalog,
        into context: ModelContext,
        priorityCenter: CLLocationCoordinate2D?,
        maxPlacesToPersist: Int?
    ) throws -> Int {
        let resp = try JSONDecoder().decode(OverpassResponse.self, from: data)
        var pending: [PendingPOI] = []
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
            if Self.isUnwantedPOIName(displayName) { continue }
            let osmId = "\(el.type)/\(el.id)"
            let chain = chainDetector.evaluate(name: displayName, tags: tags)
            if chain.0 {
                if let existing = try context.fetch(FetchDescriptor<CachedPOI>(predicate: #Predicate { $0.osmId == osmId })).first {
                    context.delete(existing)
                }
                continue
            }
            let partner = partners.matchPartnerPOI(name: displayName, osmId: osmId)
            let isPartner = partner != nil
            let offer = partner?.offer
            let stamp = partner?.stampCodeForStorage
            let addr = [tags["addr:housenumber"], tags["addr:street"], tags["addr:city"]].compactMap { $0 }.joined(separator: " ")

            pending.append(
                PendingPOI(
                    osmId: osmId,
                    displayName: displayName,
                    coord: coord,
                    category: category,
                    isChain: chain.0,
                    chainLabel: chain.1,
                    isPartner: isPartner,
                    partnerOffer: offer,
                    stampCode: stamp,
                    addressSummary: addr.isEmpty ? nil : addr
                )
            )
        }

        let selected: [PendingPOI] = {
            guard let cap = maxPlacesToPersist, pending.count > cap else { return pending }
            return balancedNearAndFarSelection(pending, priorityCenter: priorityCenter, maxCount: cap)
        }()

        let cityRows = try context.fetch(FetchDescriptor<CachedPOI>(predicate: #Predicate { $0.cityKey == cityKey }))
        var appleOnlyRows = cityRows.filter { $0.osmId.hasPrefix("apple:") }

        var inserted = 0
        for p in selected {
            let osmId = p.osmId
            let fetch = FetchDescriptor<CachedPOI>(predicate: #Predicate<CachedPOI> { $0.osmId == osmId })
            if let existing = try context.fetch(fetch).first {
                existing.name = p.displayName
                existing.latitude = p.coord.latitude
                existing.longitude = p.coord.longitude
                existing.categoryRaw = p.category.rawValue
                existing.isChain = p.isChain
                existing.chainLabel = p.chainLabel
                existing.isPartner = p.isPartner
                existing.partnerOffer = p.partnerOffer
                existing.stampCode = p.stampCode
                existing.addressSummary = p.addressSummary
                existing.cacheDate = .now
                existing.cityKey = cityKey
            } else {
                if let idx = appleOnlyRows.firstIndex(where: { apple in
                    coordinatesAndNamesSuggestSamePlace(
                        p.coord, nameA: p.displayName, categoryRawA: p.category.rawValue,
                        CLLocationCoordinate2D(latitude: apple.latitude, longitude: apple.longitude),
                        nameB: apple.name,
                        categoryRawB: apple.categoryRaw
                    )
                }) {
                    let dup = appleOnlyRows.remove(at: idx)
                    try migrateOsmIdReferences(from: dup.osmId, to: p.osmId, in: context)
                    context.delete(dup)
                }
                let row = CachedPOI(
                    osmId: p.osmId,
                    name: p.displayName,
                    latitude: p.coord.latitude,
                    longitude: p.coord.longitude,
                    categoryRaw: p.category.rawValue,
                    isChain: p.isChain,
                    chainLabel: p.chainLabel,
                    isPartner: p.isPartner,
                    partnerOffer: p.partnerOffer,
                    stampCode: p.stampCode,
                    addressSummary: p.addressSummary,
                    cacheDate: .now,
                    cityKey: cityKey
                )
                context.insert(row)
                inserted += 1
            }
        }
        return inserted
    }

    /// Limits road geometry retained for snapping/XP so a dense Overpass response doesn’t freeze the main thread.
    static func capRoadSegments(_ segments: [RoadSegmentSample], priorityCenter: CLLocationCoordinate2D, maxCount: Int) -> [RoadSegmentSample] {
        guard maxCount > 0, segments.count > maxCount else { return segments }
        let sorted = segments.sorted {
            let da = min(GeoMath.distanceMeters(priorityCenter, $0.a), GeoMath.distanceMeters(priorityCenter, $0.b))
            let db = min(GeoMath.distanceMeters(priorityCenter, $1.a), GeoMath.distanceMeters(priorityCenter, $1.b))
            return da < db
        }
        let nearN = max(1, Int(Double(maxCount) * 0.78))
        var out: [RoadSegmentSample] = []
        out.append(contentsOf: sorted.prefix(nearN))
        let remainder = Array(sorted.dropFirst(min(nearN, sorted.count)))
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
            var seen = Set(out.map { "\($0.wayId):\($0.segmentIndex)" })
            for s in sorted where out.count < maxCount {
                let k = "\(s.wayId):\(s.segmentIndex)"
                guard seen.insert(k).inserted else { continue }
                out.append(s)
            }
        }
        return Array(out.prefix(maxCount))
    }

    static func purgeStalePOIs(olderThan days: Int, in context: ModelContext) throws {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .distantPast
        let fetch = FetchDescriptor<CachedPOI>(predicate: #Predicate { $0.cacheDate < cutoff })
        let old = try context.fetch(fetch)
        for o in old { context.delete(o) }
    }
}
