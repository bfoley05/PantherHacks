//
//  ProgressStats.swift
//  Venture Local
//
//  City completion uses only non-chain businesses. Global XP comes from ExplorerProfile.totalXP.
//

import Foundation
import SwiftData

enum ProgressStats {
    struct CitySnapshot {
        var completion01: Double
        var localsDiscovered: Int
        var localsTotal: Int
        var perCategory: [DiscoveryCategory: CategorySlice]
    }

    struct CategorySlice {
        var discovered: Int
        var total: Int
        var percent01: Double {
            guard total > 0 else { return 0 }
            return Double(discovered) / Double(total)
        }
    }

    static func citySnapshot(
        modelContext: ModelContext,
        cityKey: String,
        includePOI: (CachedPOI) -> Bool = { _ in true }
    ) throws -> CitySnapshot {
        let localPredicate = #Predicate<CachedPOI> { poi in
            poi.cityKey == cityKey && poi.isChain == false
        }
        let locals = try modelContext.fetch(FetchDescriptor<CachedPOI>(predicate: localPredicate)).filter(includePOI)
        let discPredicate = #Predicate<DiscoveredPlace> { d in d.cityKey == cityKey }
        let discoveredRows = try modelContext.fetch(FetchDescriptor<DiscoveredPlace>(predicate: discPredicate))
        let discoveredSet = Set(discoveredRows.map(\.osmId))

        var per: [DiscoveryCategory: (found: Int, total: Int)] = [:]
        for p in locals {
            guard let cat = DiscoveryCategory(rawValue: p.categoryRaw) else { continue }
            var cur = per[cat] ?? (0, 0)
            cur.1 += 1
            if discoveredSet.contains(p.osmId) { cur.0 += 1 }
            per[cat] = cur
        }
        for c in DiscoveryCategory.allCases where per[c] == nil {
            per[c] = (0, 0)
        }

        let localsTotal = locals.count
        let localsDiscovered = locals.filter { discoveredSet.contains($0.osmId) }.count
        let completion01 = localsTotal == 0 ? 0 : Double(localsDiscovered) / Double(localsTotal)

        var slices: [DiscoveryCategory: CategorySlice] = [:]
        for c in DiscoveryCategory.allCases {
            let v = per[c] ?? (0, 0)
            slices[c] = CategorySlice(discovered: v.found, total: v.total)
        }

        return CitySnapshot(
            completion01: completion01,
            localsDiscovered: localsDiscovered,
            localsTotal: localsTotal,
            perCategory: slices
        )
    }

    static func recentDiscoveries(modelContext: ModelContext, limit: Int = 10) throws -> [DiscoveredPlace] {
        var d = FetchDescriptor<DiscoveredPlace>(sortBy: [SortDescriptor(\.discoveredAt, order: .reverse)])
        d.fetchLimit = limit
        return try modelContext.fetch(d)
    }
}
