//
//  CityKey.swift
//  Venture Local
//
//  Stable key for grouping progress to a locality (MVP: geocoded components).
//

import CoreLocation
import Foundation

enum CityKey {
    static func make(locality: String?, administrativeArea: String?, country: String?) -> String {
        let l = (locality ?? "unknown").replacingOccurrences(of: " ", with: "_")
        let a = (administrativeArea ?? "").replacingOccurrences(of: " ", with: "_")
        let c = (country ?? "").replacingOccurrences(of: " ", with: "_")
        return [l, a, c].filter { !$0.isEmpty }.joined(separator: "__")
    }

    /// When reverse geocoding is not ready (or fails), still tag POIs so sync/journal work.
    static func mapRegionFallback(center: CLLocationCoordinate2D) -> String {
        let lat = String(format: "%.2f", center.latitude)
        let lon = String(format: "%.2f", center.longitude)
        return "map__\(lat)_\(lon)"
    }

    /// Readable label for a stored city key (settings / pickers).
    static func displayLabel(for key: String) -> String {
        if key.hasPrefix("map__") { return "Map region" }
        if key.isEmpty { return "Unknown city" }
        return key.replacingOccurrences(of: "__", with: ", ").replacingOccurrences(of: "_", with: " ")
    }
}
