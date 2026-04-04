//
//  CityBoundaryParser.swift
//  Venture Local
//
//  Parses Nominatim `geojson` (Polygon / MultiPolygon) or `boundingbox` into map coordinates.
//

import CoreLocation
import Foundation
import MapKit

struct ParsedCityBoundary: Sendable {
    /// Each entry: outer ring + optional holes (for point-in-polygon).
    var polygons: [(outer: [CLLocationCoordinate2D], holes: [[CLLocationCoordinate2D]])]
    var south: Double
    var north: Double
    var west: Double
    var east: Double

    var mapRegion: MKCoordinateRegion {
        let clat = (south + north) / 2
        let clon = (west + east) / 2
        let padLat = max((north - south) * 0.08, 0.005)
        let padLon = max((east - west) * 0.08, 0.005)
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: clat, longitude: clon),
            span: MKCoordinateSpan(
                latitudeDelta: max(north - south + padLat, 0.02),
                longitudeDelta: max(east - west + padLon, 0.02)
            )
        )
    }

    /// Closed rings suitable for `MapPolygon` (first point repeated at end if needed).
    var mapPolygonOuters: [[CLLocationCoordinate2D]] {
        polygons.map { CityBoundaryParser.closedRing($0.outer) }
    }
}

enum CityBoundaryParser {
    static func parse(nominatimJSON obj: [String: Any]) -> ParsedCityBoundary? {
        if let gj = obj["geojson"] as? [String: Any], let type = gj["type"] as? String {
            switch type {
            case "Polygon":
                if let polys = parsePolygonCoordinates(gj["coordinates"]) {
                    if let b = boundingBox(of: polys) {
                        return ParsedCityBoundary(polygons: polys, south: b.south, north: b.north, west: b.west, east: b.east)
                    }
                }
            case "MultiPolygon":
                if let polys = parseMultiPolygonCoordinates(gj["coordinates"]) {
                    if let b = boundingBox(of: polys) {
                        return ParsedCityBoundary(polygons: polys, south: b.south, north: b.north, west: b.west, east: b.east)
                    }
                }
            default:
                break
            }
        }
        if let bb = obj["boundingbox"] as? [String], bb.count == 4,
           let south = Double(bb[0]), let north = Double(bb[1]),
           let west = Double(bb[2]), let east = Double(bb[3]) {
            let rect = rectangleRing(south: south, north: north, west: west, east: east)
            return ParsedCityBoundary(
                polygons: [(outer: rect, holes: [])],
                south: south, north: north, west: west, east: east
            )
        }
        return nil
    }

    private static func parsePolygonCoordinates(_ any: Any?) -> [(outer: [CLLocationCoordinate2D], holes: [[CLLocationCoordinate2D]])]? {
        guard let rings = any as? [[[Double]]], !rings.isEmpty else { return nil }
        let converted = rings.map { ringFromGeoJSON($0) }
        let outer = converted[0]
        let holes = Array(converted.dropFirst())
        return [(outer: outer, holes: holes)]
    }

    private static func parseMultiPolygonCoordinates(_ any: Any?) -> [(outer: [CLLocationCoordinate2D], holes: [[CLLocationCoordinate2D]])]? {
        guard let multi = any as? [[[[Double]]]] else { return nil }
        var out: [(outer: [CLLocationCoordinate2D], holes: [[CLLocationCoordinate2D]])] = []
        for polyRings in multi {
            guard !polyRings.isEmpty else { continue }
            let converted = polyRings.map { ringFromGeoJSON($0) }
            let outer = converted[0]
            let holes = Array(converted.dropFirst())
            out.append((outer: outer, holes: holes))
        }
        return out.isEmpty ? nil : out
    }

    private static func ringFromGeoJSON(_ ring: [[Double]]) -> [CLLocationCoordinate2D] {
        ring.compactMap { pair -> CLLocationCoordinate2D? in
            guard pair.count >= 2 else { return nil }
            return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
        }
    }

    private static func rectangleRing(south: Double, north: Double, west: Double, east: Double) -> [CLLocationCoordinate2D] {
        [
            CLLocationCoordinate2D(latitude: south, longitude: west),
            CLLocationCoordinate2D(latitude: south, longitude: east),
            CLLocationCoordinate2D(latitude: north, longitude: east),
            CLLocationCoordinate2D(latitude: north, longitude: west),
            CLLocationCoordinate2D(latitude: south, longitude: west),
        ]
    }

    private static func boundingBox(of polygons: [(outer: [CLLocationCoordinate2D], holes: [[CLLocationCoordinate2D]])]) -> (south: Double, north: Double, west: Double, east: Double)? {
        var s = Double.greatestFiniteMagnitude
        var n = -Double.greatestFiniteMagnitude
        var w = Double.greatestFiniteMagnitude
        var e = -Double.greatestFiniteMagnitude
        var any = false
        for p in polygons {
            for c in p.outer {
                any = true
                s = min(s, c.latitude)
                n = max(n, c.latitude)
                w = min(w, c.longitude)
                e = max(e, c.longitude)
            }
        }
        guard any else { return nil }
        return (s, n, w, e)
    }

    fileprivate static func closedRing(_ ring: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        guard let first = ring.first else { return ring }
        if let last = ring.last, last.latitude == first.latitude, last.longitude == first.longitude { return ring }
        return ring + [first]
    }
}
