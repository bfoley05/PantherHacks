//
//  CityBoundaryResolver.swift
//  Venture Local
//
//  Reverse geocode at zoom=11 often still returns a single building polygon. We fall back to
//  Nominatim *search* for the city/town and pick an administrative polygon with a sane size.
//

import CoreLocation
import Foundation
import MapKit

enum CityBoundaryResolver {
    /// Minimum diagonal across the bounding box to treat as a “city-scale” outline (meters).
    private static let minimumCityDiagonalMeters: Double = 2_800

    static func diagonalMeters(of parsed: ParsedCityBoundary) -> Double {
        bboxDiagonalMeters(south: parsed.south, north: parsed.north, west: parsed.west, east: parsed.east)
    }

    static func bboxDiagonalMeters(south: Double, north: Double, west: Double, east: Double) -> Double {
        let sw = CLLocation(latitude: south, longitude: west)
        let ne = CLLocation(latitude: north, longitude: east)
        return sw.distance(from: ne)
    }

    /// True when reverse result is likely a single building / parcel, not a municipality.
    static func reverseLooksLikeMicroPlace(_ json: [String: Any]) -> Bool {
        let cls = (json["class"] as? String)?.lowercased() ?? ""
        let typ = (json["type"] as? String)?.lowercased() ?? ""
        if cls == "place" {
            if ["house", "building", "retail", "commercial", "allotments", "farm", "plot"].contains(typ) {
                return true
            }
        }
        if cls == "building" || cls == "shop" || cls == "amenity" { return true }
        if let cat = json["category"] as? String, cat.lowercased().contains("building") { return true }
        return false
    }

    static func isTooSmallForCity(_ parsed: ParsedCityBoundary) -> Bool {
        diagonalMeters(of: parsed) < minimumCityDiagonalMeters
    }

    static func buildSearchQuery(fromReverseJSON json: [String: Any], fallbackCityKey: String) -> String? {
        if let addr = json["address"] as? [String: Any] {
            let city = firstString(addr, keys: ["city", "town", "village", "municipality", "hamlet", "suburb"])
            let state = firstString(addr, keys: ["state", "region", "province"])
            let country = firstString(addr, keys: ["country"])
            let parts = [city, state, country].compactMap { $0 }.filter { !$0.isEmpty }
            if !parts.isEmpty { return parts.joined(separator: ", ") }
        }
        let display = json["display_name"] as? String
        if let d = display, !d.isEmpty {
            let head = d.split(separator: ",").prefix(4).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: ", ")
            if head.count > 4 { return head }
        }
        if fallbackCityKey.hasPrefix("map__") { return nil }
        return fallbackCityKey.replacingOccurrences(of: "__", with: ", ")
    }

    private static func firstString(_ dict: [String: Any], keys: [String]) -> String? {
        for k in keys {
            if let s = dict[k] as? String, !s.trimmingCharacters(in: .whitespaces).isEmpty { return s }
        }
        return nil
    }

    /// Pick the best search hit that has a polygon and looks city-sized.
    static func pickBestSearchResult(_ items: [[String: Any]]) -> [String: Any]? {
        let withGeo = items.filter { $0["geojson"] != nil }
        let pool = withGeo.isEmpty ? items : withGeo

        func score(_ o: [String: Any]) -> Double {
            var s = 0.0
            if let imp = o["importance"] as? Double { s += imp * 12 }
            let cls = (o["class"] as? String) ?? ""
            let typ = (o["type"] as? String) ?? ""
            if cls == "boundary" { s += 8 }
            if typ == "administrative" { s += 6 }
            let addType = (o["addresstype"] as? String) ?? ""
            if ["city", "town", "municipality", "village", "county"].contains(addType) { s += 5 }
            if cls == "place", ["city", "town", "municipality", "village"].contains(typ) { s += 5 }
            if let bb = o["boundingbox"] as? [String], bb.count == 4,
               let so = Double(bb[0]), let no = Double(bb[1]), let we = Double(bb[2]), let ea = Double(bb[3]) {
                let d = bboxDiagonalMeters(south: so, north: no, west: we, east: ea)
                if d < 1_500 { s -= 20 }
                if d >= minimumCityDiagonalMeters { s += 6 }
                if d > 8_000 { s += 1 }
            }
            return s
        }

        return pool.max(by: { score($0) < score($1) })
    }
}
