//
//  GeoMath.swift
//  Venture Local
//
//  Local tangent-plane approximation for short segments (good for city-scale snapping).
//

import CoreLocation
import Foundation

enum GeoMath {
    static func distanceMeters(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    /// Meters from point `p` to line segment `ab`.
    static func distancePointToSegmentMeters(p: CLLocationCoordinate2D, a: CLLocationCoordinate2D, b: CLLocationCoordinate2D) -> Double {
        let ax = 0.0
        let ay = 0.0
        let bx = metersEast(from: a, to: b)
        let by = metersNorth(from: a, to: b)
        let px = metersEast(from: a, to: p)
        let py = metersNorth(from: a, to: p)
        let abx = bx - ax
        let aby = by - ay
        let apx = px - ax
        let apy = py - ay
        let ab2 = abx * abx + aby * aby
        if ab2 < 1e-6 {
            return hypot(px, py)
        }
        let t = max(0, min(1, (apx * abx + apy * aby) / ab2))
        let cx = ax + t * abx
        let cy = ay + t * aby
        return hypot(px - cx, py - cy)
    }

    private static func metersNorth(from origin: CLLocationCoordinate2D, to coord: CLLocationCoordinate2D) -> Double {
        (coord.latitude - origin.latitude) * .pi / 180 * 6_371_000
    }

    private static func metersEast(from origin: CLLocationCoordinate2D, to coord: CLLocationCoordinate2D) -> Double {
        (coord.longitude - origin.longitude) * .pi / 180 * 6_371_000 * cos(origin.latitude * .pi / 180)
    }
}
