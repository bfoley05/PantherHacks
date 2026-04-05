//
//  ExplorerEventLog.swift
//  Venture Local
//

import Foundation
import SwiftData

enum ExplorerEventLog {
    /// Inserts synthetic `visit` rows from legacy discoveries once per profile.
    static func ensureBackfill(
        context: ModelContext,
        profile: ExplorerProfile?,
        discoveries: [DiscoveredPlace],
        pois: [CachedPOI]
    ) throws {
        guard let profile else { return }
        if profile.explorerEventBackfillDone == true { return }

        let already = try context.fetch(FetchDescriptor<ExplorerEvent>()).count
        if already > 0 {
            profile.explorerEventBackfillDone = true
            try context.save()
            return
        }

        let poiById = Dictionary(uniqueKeysWithValues: pois.map { ($0.osmId, $0) })

        for d in discoveries {
            let poi = poiById[d.osmId]
            let category = poi?.categoryRaw ?? ""
            let chain = poi?.isChain ?? false
            context.insert(ExplorerEvent(
                kind: .visit,
                osmId: d.osmId,
                cityKey: d.cityKey,
                categoryRaw: category,
                isChain: chain,
                occurredAt: d.discoveredAt
            ))
        }

        profile.explorerEventBackfillDone = true
        try context.save()
    }

    static func recordVisit(context: ModelContext, poi: CachedPOI, cityKey: String, at date: Date = .now) {
        context.insert(ExplorerEvent(
            kind: .visit,
            osmId: poi.osmId,
            cityKey: cityKey,
            categoryRaw: poi.categoryRaw,
            isChain: poi.isChain,
            occurredAt: date
        ))
    }

    static func recordRevisit(context: ModelContext, poi: CachedPOI, cityKey: String, at date: Date = .now) {
        context.insert(ExplorerEvent(
            kind: .revisit,
            osmId: poi.osmId,
            cityKey: cityKey,
            categoryRaw: poi.categoryRaw,
            isChain: poi.isChain,
            occurredAt: date
        ))
    }

    static func recordStamp(context: ModelContext, poi: CachedPOI, cityKey: String, at date: Date = .now) {
        context.insert(ExplorerEvent(
            kind: .stamp,
            osmId: poi.osmId,
            cityKey: cityKey,
            categoryRaw: poi.categoryRaw,
            isChain: poi.isChain,
            occurredAt: date
        ))
    }

    static func recordSave(context: ModelContext, poi: CachedPOI, cityKey: String, at date: Date = .now) {
        context.insert(ExplorerEvent(
            kind: .save,
            osmId: poi.osmId,
            cityKey: cityKey,
            categoryRaw: poi.categoryRaw,
            isChain: poi.isChain,
            occurredAt: date
        ))
    }

    static func recordUnsave(context: ModelContext, poi: CachedPOI, cityKey: String, at date: Date = .now) {
        context.insert(ExplorerEvent(
            kind: .unsave,
            osmId: poi.osmId,
            cityKey: cityKey,
            categoryRaw: poi.categoryRaw,
            isChain: poi.isChain,
            occurredAt: date
        ))
    }

    static func recordFavorite(context: ModelContext, poi: CachedPOI, cityKey: String, at date: Date = .now) {
        context.insert(ExplorerEvent(
            kind: .favorite,
            osmId: poi.osmId,
            cityKey: cityKey,
            categoryRaw: poi.categoryRaw,
            isChain: poi.isChain,
            occurredAt: date
        ))
    }

    static func recordUnfavorite(context: ModelContext, poi: CachedPOI, cityKey: String, at date: Date = .now) {
        context.insert(ExplorerEvent(
            kind: .unfavorite,
            osmId: poi.osmId,
            cityKey: cityKey,
            categoryRaw: poi.categoryRaw,
            isChain: poi.isChain,
            occurredAt: date
        ))
    }

    /// At most one revisit event per place per calendar day (avoids GPS spam).
    static func shouldRecordRevisit(
        context: ModelContext,
        osmId: String,
        on day: Date
    ) throws -> Bool {
        let cal = Calendar.current
        let kindRevisit = ExplorerEventKind.revisit.rawValue
        let fetch = FetchDescriptor<ExplorerEvent>(
            predicate: #Predicate { e in
                e.osmId == osmId && e.kindRaw == kindRevisit
            }
        )
        let rows = try context.fetch(fetch)
        return !rows.contains { cal.isDate($0.occurredAt, inSameDayAs: day) }
    }
}
