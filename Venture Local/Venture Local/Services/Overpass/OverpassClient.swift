//
//  OverpassClient.swift
//  Venture Local
//
//  Overpass expects the query as POST body: `text/plain` UTF-8 (not form-urlencoded).
//
//  TLS failures (NSURLError -1200, errSSL -9816) often affect one host or certificate chain;
//  we rotate through public mirrors and relax ATS slightly for those domains in Info.plist.
//

import Foundation

enum OverpassError: LocalizedError {
    case httpStatus(Int, String?)
    case serverJSON(String)
    case emptyBody
    case allHostsFailed(last: Error?)

    var errorDescription: String? {
        switch self {
        case let .httpStatus(code, detail):
            if let detail, !detail.isEmpty {
                return "Overpass HTTP \(code): \(detail)"
            }
            return "Overpass HTTP \(code). Try zooming in or try again in a minute."
        case let .serverJSON(msg):
            return msg
        case .emptyBody:
            return "Empty response from Overpass."
        case let .allHostsFailed(last):
            if let last {
                return "Could not reach any Overpass mirror: \(last.localizedDescription)"
            }
            return "Could not reach any Overpass mirror. Check date & time, VPN, or try another network."
        }
    }
}

actor OverpassClient {
    /// Default (first mirror). Change if you self-host.
    static var endpoint: URL { interpreterEndpoints[0] }

    /// Order: different operators / cert chains first to survive TLS handshake issues on some networks.
    private static let interpreterEndpoints: [URL] = [
        "https://overpass.openstreetmap.fr/api/interpreter",
        "https://overpass-api.de/api/interpreter",
        "https://lz4.overpass-api.de/api/interpreter",
        "https://overpass.kumi.systems/api/interpreter",
    ].compactMap { URL(string: $0) }

    private static let urlSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 55
        config.timeoutIntervalForResource = 90
        config.httpMaximumConnectionsPerHost = 2
        config.urlCache = nil
        if #available(iOS 15.0, *) {
            config.tlsMinimumSupportedProtocolVersion = .TLSv12
        }
        return URLSession(configuration: config)
    }()

    private var lastRequestStart: Date = .distantPast

    func runQuery(_ ql: String) async throws -> Data {
        let elapsed = Date().timeIntervalSince(lastRequestStart)
        if elapsed < 1.05 {
            try await Task.sleep(nanoseconds: UInt64((1.05 - elapsed) * 1_000_000_000))
        }
        lastRequestStart = Date()

        var lastError: Error?
        for url in Self.interpreterEndpoints {
            do {
                return try await Self.postQuery(ql, to: url)
            } catch {
                lastError = error
                if Self.shouldRotateHost(after: error) {
                    try await Task.sleep(nanoseconds: 450_000_000)
                    continue
                }
                if let over = error as? OverpassError, case let .httpStatus(code, _) = over, [429, 502, 503, 504].contains(code) {
                    try await Task.sleep(nanoseconds: 800_000_000)
                    continue
                }
                if let urlErr = error as? URLError, [.timedOut, .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet].contains(urlErr.code) {
                    try await Task.sleep(nanoseconds: 800_000_000)
                    continue
                }
                throw error
            }
        }
        throw OverpassError.allHostsFailed(last: lastError)
    }

    /// Handshake / trust failures: try another mirror before giving up.
    private static func shouldRotateHost(after error: Error) -> Bool {
        let urlErrors: [URLError] = {
            if let u = error as? URLError { return [u] }
            let ns = error as NSError
            if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? URLError {
                return [underlying]
            }
            return []
        }()
        for url in urlErrors {
            switch url.code {
            case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot, .clientCertificateRejected, .clientCertificateRequired:
                return true
            default:
                break
            }
        }
        return false
    }

    private static func postQuery(_ ql: String, to endpoint: URL) async throws -> Data {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("VentureLocal/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        request.httpBody = Data(ql.utf8)
        request.timeoutInterval = 55

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        let textSnippet = String(data: data.prefix(512), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard (200 ..< 300).contains(http.statusCode) else {
            throw OverpassError.httpStatus(http.statusCode, textSnippet)
        }

        guard !data.isEmpty else { throw OverpassError.emptyBody }

        try validateOverpassPayload(data)
        return data
    }

    private static func validateOverpassPayload(_ data: Data) throws {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        if let err = obj["error"] as? [String: Any] {
            let text = (err["text"] as? String) ?? String(describing: err)
            throw OverpassError.serverJSON(text)
        }

        if let remark = obj["remark"] as? String {
            let r = remark.lowercased()
            if r.contains("runtime error") || r.contains("too many requests") || r.contains("gateway timeout") || (r.contains("openstreetmap") && r.contains("blocked")) {
                throw OverpassError.serverJSON(remark)
            }
        }
    }

    /// `access` filter: drop `private`, `no`, and `permit` (Overpass `!~` keeps untagged features).
    private static let poiAccessFilter = #"["access"!~"^(private|no|permit)$"]"#

    static func poiQuery(south: Double, west: Double, north: Double, east: Double, timeoutSeconds: Int = 25) -> String {
        let ax = Self.poiAccessFilter
        let t = max(15, min(timeoutSeconds, 120))
        return """
        [out:json][timeout:\(t)];
        (
          node["amenity"]\(ax)(\(south),\(west),\(north),\(east));
          way["amenity"]\(ax)(\(south),\(west),\(north),\(east));
          node["shop"]\(ax)(\(south),\(west),\(north),\(east));
          way["shop"]\(ax)(\(south),\(west),\(north),\(east));
          node["tourism"]\(ax)(\(south),\(west),\(north),\(east));
          way["tourism"]\(ax)(\(south),\(west),\(north),\(east));
          node["leisure"]\(ax)(\(south),\(west),\(north),\(east));
          way["leisure"]\(ax)(\(south),\(west),\(north),\(east));
          node["historic"]\(ax)(\(south),\(west),\(north),\(east));
          way["historic"]\(ax)(\(south),\(west),\(north),\(east));
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
