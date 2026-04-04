//
//  OverpassClient.swift
//  Venture Local
//
//  Uses the public Overpass interpreter endpoint. Replace `OverpassClient.endpoint`
//  if you self-host or use a different mirror (respect ~1 req/s etiquette).
//

import Foundation
import CoreLocation

actor OverpassClient {
    /// Public read endpoint; configure your own mirror via app settings in a future build.
    static var endpoint: URL = URL(string: "https://overpass-api.de/api/interpreter")!

    private var lastRequestStart: Date = .distantPast

    func runQuery(_ ql: String) async throws -> Data {
        let elapsed = Date().timeIntervalSince(lastRequestStart)
        if elapsed < 1.05 {
            try await Task.sleep(nanoseconds: UInt64((1.05 - elapsed) * 1_000_000_000))
        }
        lastRequestStart = Date()
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        // Overpass expects `data=<url-encoded query>`; encode conservatively for newlines and brackets.
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encoded = ql.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        request.httpBody = "data=\(encoded)".data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    static func poiQuery(south: Double, west: Double, north: Double, east: Double) -> String {
        """
        [out:json][timeout:25];
        (
          node["amenity"](\(south),\(west),\(north),\(east));
          way["amenity"](\(south),\(west),\(north),\(east));
          node["shop"](\(south),\(west),\(north),\(east));
          way["shop"](\(south),\(west),\(north),\(east));
          node["tourism"](\(south),\(west),\(north),\(east));
          way["tourism"](\(south),\(west),\(north),\(east));
          node["leisure"](\(south),\(west),\(north),\(east));
          way["leisure"](\(south),\(west),\(north),\(east));
          node["historic"](\(south),\(west),\(north),\(east));
          way["historic"](\(south),\(west),\(north),\(east));
        );
        out center tags;
        """
    }

    static func roadQuery(south: Double, west: Double, north: Double, east: Double) -> String {
        """
        [out:json][timeout:25];
        way["highway"~"^(motorway|trunk|primary|secondary|tertiary|unclassified|residential|living_street|pedestrian|footway|path|cycleway|service|track)$"](\(south),\(west),\(north),\(east));
        out geom tags;
        """
    }
}
