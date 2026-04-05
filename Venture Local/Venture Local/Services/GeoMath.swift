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

    /// Ray casting in lon/lat plane (fine for city-sized polygons).
    static func polygonContains(_ p: CLLocationCoordinate2D, ring: [CLLocationCoordinate2D]) -> Bool {
        let x = p.longitude
        let y = p.latitude
        guard ring.count >= 3 else { return false }
        var inside = false
        var j = ring.count - 1
        for i in 0 ..< ring.count {
            let xi = ring[i].longitude
            let yi = ring[i].latitude
            let xj = ring[j].longitude
            let yj = ring[j].latitude
            let denom = yj - yi
            let eps = 1e-15
            if (yi > y) != (yj > y), abs(denom) > eps {
                let xInt = (xj - xi) * (y - yi) / denom + xi
                if x < xInt { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    static func pointInCityPolygons(_ p: CLLocationCoordinate2D, polygons: [(outer: [CLLocationCoordinate2D], holes: [[CLLocationCoordinate2D]])]) -> Bool {
        for poly in polygons {
            guard polygonContains(p, ring: poly.outer) else { continue }
            var inHole = false
            for h in poly.holes where polygonContains(p, ring: h) {
                inHole = true
                break
            }
            if !inHole { return true }
        }
        return false
    }

    static func intersectLatLonBBox(
        south: Double, north: Double, west: Double, east: Double,
        limSouth: Double, limNorth: Double, limWest: Double, limEast: Double
    ) -> (south: Double, north: Double, west: Double, east: Double)? {
        let s = max(south, limSouth)
        let n = min(north, limNorth)
        let w = max(west, limWest)
        let e = min(east, limEast)
        guard s < n, w < e else { return nil }
        return (s, n, w, e)
    }

    /// Squared distance in m² (local tangent plane). Same ordering as true distance for city-scale ranges; avoids `CLLocation` allocation — use for sorting many pins.
    static func distanceSquaredComparable(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let nx = (b.latitude - a.latitude) * .pi / 180 * 6_371_000
        let ex = (b.longitude - a.longitude) * .pi / 180 * 6_371_000 * cos(a.latitude * .pi / 180)
        return nx * nx + ex * ex
    }

    /// Rounded copy for map copy (not for navigation).
    static func formatApproximateMapDistance(meters m: Double, useMiles: Bool) -> String {
        guard m >= 0, m.isFinite else { return "—" }
        if useMiles {
            let mi = m / 1609.344
            if mi < 0.1 { return String(format: "%.2f mi", mi) }
            if mi < 10 { return String(format: "%.1f mi", mi) }
            return "\(Int(round(mi))) mi"
        } else {
            let km = m / 1000
            if km < 0.1 { return String(format: "%.2f km", km) }
            if km < 10 { return String(format: "%.1f km", km) }
            return "\(Int(round(km))) km"
        }
    }
}
