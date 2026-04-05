//
//  CityKey.swift
//  Venture Local
//
//  Stable key for grouping progress to a locality (MVP: geocoded components).
//

import CoreLocation
import Foundation

enum CityKey {
    /// Builds a stable key. When `locality` is missing (common in unincorporated / CDP areas), uses
    /// `subAdministrativeArea` (e.g. “Orange County”) so keys stay specific instead of many `unknown__CA__US` collisions.
    static func make(
        locality: String?,
        administrativeArea: String?,
        country: String?,
        subAdministrativeArea: String? = nil
    ) -> String {
        let locTrim = locality?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let subTrim = subAdministrativeArea?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let primary = locTrim.isEmpty ? (subTrim.isEmpty ? "" : subTrim) : locTrim
        let l = (primary.isEmpty ? "unknown" : primary).replacingOccurrences(of: " ", with: "_")
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

    /// US-style keys are usually `Locality__ST__US`; returns the middle segment (e.g. `CA`) when parseable.
    static func stateOrRegion(fromCityKey key: String) -> String? {
        guard !key.hasPrefix("map__"), !key.isEmpty else { return nil }
        let parts = key.split(separator: "__").map(String.init).filter { !$0.isEmpty }
        guard parts.count >= 2 else { return nil }
        let idx = parts.count >= 3 ? parts.count - 2 : 1
        let raw = parts[idx].replacingOccurrences(of: "_", with: " ")
        return raw.isEmpty ? nil : raw
    }
}
