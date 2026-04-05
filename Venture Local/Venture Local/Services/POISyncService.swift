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
    // MARK: - Overpass merge (SwiftData apply on main actor; parse in ``OverpassMergePayloadFactory``)

    @discardableResult
    static func applyOverpassMergePayload(_ payload: OverpassMergePayload, cityKey: String, into context: ModelContext) throws -> Int {
        if !payload.chainOsmIdsToPurge.isEmpty {
            let idList = payload.chainOsmIdsToPurge
            let chunkSize = 400
            for chunkStart in stride(from: 0, to: idList.count, by: chunkSize) {
                let end = min(chunkStart + chunkSize, idList.count)
                let chunk = Set(idList[chunkStart..<end])
                let stale = try context.fetch(
                    FetchDescriptor<CachedPOI>(predicate: #Predicate<CachedPOI> { chunk.contains($0.osmId) })
                )
                for row in stale { context.delete(row) }
            }
        }

        var inserted = 0
        let cityRows = try context.fetch(FetchDescriptor<CachedPOI>(predicate: #Predicate { $0.cityKey == cityKey }))
        var appleOnlyRows = cityRows.filter { $0.osmId.hasPrefix("apple:") }

        for p in payload.rows {
            let osmId = p.osmId
            let fetch = FetchDescriptor<CachedPOI>(predicate: #Predicate<CachedPOI> { $0.osmId == osmId })
            if let existing = try context.fetch(fetch).first {
                existing.name = p.displayName
                existing.latitude = p.latitude
                existing.longitude = p.longitude
                existing.categoryRaw = p.categoryRaw
                existing.isChain = p.isChain
                existing.chainLabel = p.chainLabel
                existing.isPartner = p.isPartner
                existing.partnerOffer = p.partnerOffer
                existing.stampCode = p.stampCode
                existing.addressSummary = p.addressSummary
                existing.cacheDate = .now
                existing.cityKey = cityKey
                existing.extendedMetadataJSON = POIExtendedMetadataCodec.merge(into: existing.extendedMetadataJSON, osmTags: p.osmTagSlice)
            } else {
                let coord = CLLocationCoordinate2D(latitude: p.latitude, longitude: p.longitude)
                if let idx = appleOnlyRows.firstIndex(where: { apple in
                    OverpassPlaceDedupe.coordinatesAndNamesSuggestSamePlace(
                        coord, nameA: p.displayName, categoryRawA: p.categoryRaw,
                        CLLocationCoordinate2D(latitude: apple.latitude, longitude: apple.longitude),
                        nameB: apple.name,
                        categoryRawB: apple.categoryRaw
                    )
                }) {
                    let dup = appleOnlyRows.remove(at: idx)
                    try migrateOsmIdReferences(from: dup.osmId, to: p.osmId, in: context)
                    context.delete(dup)
                }
                let meta = POIExtendedMetadata(osmTags: p.osmTagSlice.isEmpty ? nil : p.osmTagSlice, mapKit: nil)
                let row = CachedPOI(
                    osmId: p.osmId,
                    name: p.displayName,
                    latitude: p.latitude,
                    longitude: p.longitude,
                    categoryRaw: p.categoryRaw,
                    isChain: p.isChain,
                    chainLabel: p.chainLabel,
                    isPartner: p.isPartner,
                    partnerOffer: p.partnerOffer,
                    stampCode: p.stampCode,
                    addressSummary: p.addressSummary,
                    cacheDate: .now,
                    cityKey: cityKey,
                    extendedMetadataJSON: POIExtendedMetadataCodec.encode(meta)
                )
                context.insert(row)
                inserted += 1
            }
        }
        return inserted
    }

    // MARK: - Cross-source deduplication (Overpass + Apple MapKit)

    // MARK: - Near-duplicate collapse (map + persistence)

    private static let dedupeGridStepDegrees = 0.00055

    private static func dedupeGridKey(_ c: CLLocationCoordinate2D) -> String {
        let gr = (c.latitude / dedupeGridStepDegrees).rounded(.down)
        let gc = (c.longitude / dedupeGridStepDegrees).rounded(.down)
        return "\(gr)_\(gc)"
    }

    /// When two cached pins are the same venue (slight name differences, apostrophes), keep one row.
    static func preferCachedPOIRepresentative(_ a: CachedPOI, _ b: CachedPOI) -> CachedPOI {
        if a.isPartner != b.isPartner { return a.isPartner ? a : b }
        if a.name.count != b.name.count { return a.name.count >= b.name.count ? a : b }
        return a.osmId < b.osmId ? a : b
    }

    /// Collapses near-duplicate pins for map rendering (same ~60m cell + fuzzy name match).
    static func dedupeCachedPOIsForMapDisplay(_ pois: [CachedPOI]) -> [CachedPOI] {
        guard pois.count > 1 else { return pois }
        var buckets: [String: [CachedPOI]] = [:]
        for p in pois {
            let c = CLLocationCoordinate2D(latitude: p.latitude, longitude: p.longitude)
            buckets[dedupeGridKey(c), default: []].append(p)
        }
        var out: [CachedPOI] = []
        for (_, bucket) in buckets {
            var kept: [CachedPOI] = []
            for p in bucket {
                if let i = kept.firstIndex(where: { q in
                    OverpassPlaceDedupe.coordinatesAndNamesSuggestSamePlace(
                        CLLocationCoordinate2D(latitude: p.latitude, longitude: p.longitude),
                        nameA: p.name, categoryRawA: p.categoryRaw,
                        CLLocationCoordinate2D(latitude: q.latitude, longitude: q.longitude),
                        nameB: q.name, categoryRawB: q.categoryRaw
                    )
                }) {
                    kept[i] = preferCachedPOIRepresentative(p, kept[i])
                } else {
                    kept.append(p)
                }
            }
            out.append(contentsOf: kept)
        }
        return out
    }

    /// Used when merging Apple POIs against SwiftData + in-memory scratch rows.
    static func isDuplicateAgainstPOISnapshot(
        coordinate: CLLocationCoordinate2D,
        name: String,
        category: DiscoveryCategory,
        snapshot: [(coord: CLLocationCoordinate2D, name: String, categoryRaw: String)]
    ) -> Bool {
        snapshot.contains { e in
            OverpassPlaceDedupe.coordinatesAndNamesSuggestSamePlace(
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
        OverpassPlaceDedupe.isUnwantedPOIName(raw)
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
        let payload = try OverpassMergePayloadFactory.buildOverpassMergePayload(
            from: data,
            chainDetector: chainDetector,
            partners: partners,
            priorityCenter: priorityCenter,
            maxPlacesToPersist: maxPlacesToPersist
        )
        return try applyOverpassMergePayload(payload, cityKey: cityKey, into: context)
    }

    static func purgeStalePOIs(olderThan days: Int, in context: ModelContext) throws {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .distantPast
        let fetch = FetchDescriptor<CachedPOI>(predicate: #Predicate { $0.cacheDate < cutoff })
        let old = try context.fetch(fetch)
        for o in old { context.delete(o) }
    }
}
