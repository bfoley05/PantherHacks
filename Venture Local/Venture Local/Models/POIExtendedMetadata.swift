//
//  POIExtendedMetadata.swift
//  Venture Local
//
//  OSM tag slice + optional MapKit snapshot for voice ranking and UI.
//

import Foundation

struct POIExtendedMetadata: Codable, Equatable, Sendable {
    var osmTags: [String: String]?
    var mapKit: MapKitPOISnapshot?
}

struct MapKitPOISnapshot: Codable, Equatable, Sendable {
    /// Debug string for `MKPointOfInterestCategory` (stable enough for keyword hints).
    var pointOfInterestCategoryDescription: String
    var refinedAt: Date
}

enum POIExtendedMetadataCodec {
    static func decode(_ json: String?) -> POIExtendedMetadata? {
        guard let json, let d = json.data(using: .utf8), !json.isEmpty else { return nil }
        return try? JSONDecoder().decode(POIExtendedMetadata.self, from: d)
    }

    static func encode(_ meta: POIExtendedMetadata) -> String? {
        guard let d = try? JSONEncoder().encode(meta) else { return nil }
        return String(data: d, encoding: .utf8)
    }

    /// Keys useful for voice / category fit (lowercased values).
    static func osmTagSlice(from tags: [String: String]) -> [String: String] {
        let keys = [
            "cuisine", "amenity", "leisure", "shop", "tourism", "historic",
            "natural", "sport", "takeaway", "delivery", "building",
        ]
        var out: [String: String] = [:]
        for k in keys {
            guard let v = tags[k]?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { continue }
            out[k] = v.lowercased()
        }
        return out
    }

    static func merge(into json: String?, osmTags: [String: String]?) -> String? {
        var m = decode(json) ?? POIExtendedMetadata()
        if let osmTags, !osmTags.isEmpty {
            m.osmTags = osmTags
        }
        return encode(m)
    }

    static func mergeMapKit(into json: String?, categoryDescription: String) -> String? {
        var m = decode(json) ?? POIExtendedMetadata()
        m.mapKit = MapKitPOISnapshot(pointOfInterestCategoryDescription: categoryDescription, refinedAt: .now)
        return encode(m)
    }
}
