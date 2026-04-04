//
//  NominatimClient.swift
//  Venture Local
//
//  Reverse (with zoom for city-level context) + search for administrative boundaries.
//  Policy: https://operations.osmfoundation.org/policies/nominatim/
//

import Foundation

actor NominatimClient {
    private var lastRequestStart: Date = .distantPast

    private func throttle() async {
        let elapsed = Date().timeIntervalSince(lastRequestStart)
        if elapsed < 1.1 {
            try? await Task.sleep(nanoseconds: UInt64((1.1 - elapsed) * 1_000_000_000))
        }
        lastRequestStart = Date()
    }

    /// `zoom` ~10–12 asks for city/town context; 18 returns buildings (too specific for “city zone”).
    func reverse(latitude: Double, longitude: Double, zoom: Int = 11) async throws -> [String: Any] {
        await throttle()
        var c = URLComponents(string: "https://nominatim.openstreetmap.org/reverse")!
        c.queryItems = [
            URLQueryItem(name: "format", value: "jsonv2"),
            URLQueryItem(name: "lat", value: String(latitude)),
            URLQueryItem(name: "lon", value: String(longitude)),
            URLQueryItem(name: "zoom", value: String(zoom)),
            URLQueryItem(name: "polygon_geojson", value: "1"),
            URLQueryItem(name: "addressdetails", value: "1"),
        ]
        guard let url = c.url else { throw URLError(.badURL) }
        return try await getJSON(url: url)
    }

    /// Forward search for a settlement / city polygon. Use `featuretype`: city, town, county (Nominatim docs).
    func search(query: String, featuretype: String? = nil) async throws -> [[String: Any]] {
        await throttle()
        var c = URLComponents(string: "https://nominatim.openstreetmap.org/search")!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "format", value: "jsonv2"),
            URLQueryItem(name: "polygon_geojson", value: "1"),
            URLQueryItem(name: "addressdetails", value: "1"),
            URLQueryItem(name: "limit", value: "18"),
        ]
        if let f = featuretype, !f.isEmpty {
            items.append(URLQueryItem(name: "featuretype", value: f))
        }
        c.queryItems = items
        guard let url = c.url else { throw URLError(.badURL) }
        let data = try await getData(url: url)
        return (try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }

    private func getJSON(url: URL) async throws -> [String: Any] {
        let data = try await getData(url: url)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.cannotDecodeContentData)
        }
        return obj
    }

    private func getData(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("VentureLocal/1.0 (com.Venture-Local)", forHTTPHeaderField: "User-Agent")
        request.setValue("en", forHTTPHeaderField: "Accept-Language")
        request.timeoutInterval = 35
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
