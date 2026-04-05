//
//  CuratedTrailCatalog.swift
//  Venture Local
//

import Foundation

struct CuratedTrail: Codable, Hashable {
    var id: String
    var title: String
    /// OSM ids (`n/123` style) that must all be discovered to complete the trail (only stops present in cache count).
    var stops: [String]

    /// True when every stop exists in the user’s cache and has been discovered.
    func isComplete(discoveredOsmIds: Set<String>, cachedOsmIds: Set<String>) -> Bool {
        let relevant = stops.filter { cachedOsmIds.contains($0) }
        guard !relevant.isEmpty, relevant.count == stops.count else { return false }
        return relevant.allSatisfy { discoveredOsmIds.contains($0) }
    }
}

struct CuratedTrailCatalog: Codable {
    var trails: [CuratedTrail]

    static func load(from bundle: Bundle) -> CuratedTrailCatalog {
        let urls = [
            bundle.url(forResource: "trails", withExtension: "json", subdirectory: "Resources"),
            bundle.url(forResource: "trails", withExtension: "json"),
        ].compactMap { $0 }
        for url in urls {
            if let data = try? Data(contentsOf: url),
               let decoded = try? JSONDecoder().decode(CuratedTrailCatalog.self, from: data) {
                return decoded
            }
        }
        return CuratedTrailCatalog(trails: [])
    }

    /// JSON trails plus auto-generated grid loops so Trail Blazer can progress in dense cities.
    func mergedTrails(locals: [CachedPOI], stepDegrees: Double = 0.018, minStopsPerTrail: Int = 3, maxSynthetic: Int = 14) -> [CuratedTrail] {
        var byId: [String: CuratedTrail] = [:]
        for t in trails { byId[t.id] = t }
        for syn in Self.syntheticGridTrails(locals: locals, stepDegrees: stepDegrees, minPerTrail: minStopsPerTrail, maxSynthetic: maxSynthetic) {
            if byId[syn.id] == nil { byId[syn.id] = syn }
        }
        return byId.values.sorted { $0.id < $1.id }
    }

    private static func syntheticGridTrails(
        locals: [CachedPOI],
        stepDegrees: Double,
        minPerTrail: Int,
        maxSynthetic: Int
    ) -> [CuratedTrail] {
        let grouped = Dictionary(grouping: locals) {
            NeighborhoodGeography.gridKey(latitude: $0.latitude, longitude: $0.longitude, stepDegrees: stepDegrees)
        }
        var out: [CuratedTrail] = []
        for key in grouped.keys.sorted() {
            guard var bucket = grouped[key], bucket.count >= minPerTrail else { continue }
            bucket.sort { $0.osmId < $1.osmId }
            let stops = Array(bucket.prefix(minPerTrail).map(\.osmId))
            out.append(CuratedTrail(id: "grid__\(key)", title: "Neighborhood loop", stops: stops))
            if out.count >= maxSynthetic { break }
        }
        return out
    }
}
