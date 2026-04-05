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
        let ck = cityKey
        let baselineFetch = FetchDescriptor<CityLocalsBaseline>(predicate: #Predicate<CityLocalsBaseline> { $0.cityKey == ck })
        let baseline = try modelContext.fetch(baselineFetch).first
        let categoryBaseline: [DiscoveryCategory: Int] = {
            guard let data = baseline?.categoryTotalsJSON,
                  let raw = try? JSONDecoder().decode([String: Int].self, from: data) else { return [:] }
            var out: [DiscoveryCategory: Int] = [:]
            for (k, v) in raw where v > 0 {
                if let c = DiscoveryCategory(rawValue: k) { out[c] = v }
            }
            return out
        }()

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

        // Baseline = one Overpass pass over the Nominatim city bounding box (`CityLocalsBaseline`). That count is stable;
        // cached `CachedPOI` rows still grow as you pan the map — do not use max(cached, baseline) or the denominator drifts upward.
        let cachedNonChainTotal = locals.count
        let baselineTotal = baseline?.nonChainLocalTotal ?? 0
        let localsTotal: Int = {
            if baselineTotal > 0 { return baselineTotal }
            return cachedNonChainTotal
        }()

        let localsDiscovered = locals.filter { discoveredSet.contains($0.osmId) }.count
        let completion01 = localsTotal == 0 ? 0 : Double(localsDiscovered) / Double(localsTotal)

        var slices: [DiscoveryCategory: CategorySlice] = [:]
        for c in DiscoveryCategory.allCases {
            let v = per[c] ?? (0, 0)
            let baseCat = categoryBaseline[c] ?? 0
            let catTotal: Int = {
                if baseCat > 0 { return baseCat }
                return v.total
            }()
            slices[c] = CategorySlice(discovered: v.found, total: catTotal)
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
