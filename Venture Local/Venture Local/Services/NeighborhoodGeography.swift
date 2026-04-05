//
//  NeighborhoodGeography.swift
//  Venture Local
//
//  Grid-based “neighborhood” buckets + downtown as a radius around local-business centroid.
//

import CoreLocation
import Foundation

enum NeighborhoodGeography {
    /// ~2 km cells at mid-latitudes; stable string keys for badge grouping.
    static func gridKey(latitude: Double, longitude: Double, stepDegrees: Double = 0.018) -> String {
        let latBin = Int(floor(latitude / stepDegrees))
        let lonBin = Int(floor(longitude / stepDegrees))
        return "\(latBin)_\(lonBin)"
    }

    static func centroid(of pois: [CachedPOI]) -> CLLocationCoordinate2D? {
        guard !pois.isEmpty else { return nil }
        let lat = pois.reduce(0.0) { $0 + $1.latitude } / Double(pois.count)
        let lon = pois.reduce(0.0) { $0 + $1.longitude } / Double(pois.count)
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    static func isDowntownPOI(_ poi: CachedPOI, centroid: CLLocationCoordinate2D, radiusMeters: Double = 1_400) -> Bool {
        let p = CLLocationCoordinate2D(latitude: poi.latitude, longitude: poi.longitude)
        return GeoMath.distanceMeters(p, centroid) <= radiusMeters
    }
}
