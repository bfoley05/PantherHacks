//
//  PartnerCatalog.swift
//  Venture Local
//
//  Optional bundle JSON: override specific OSM ids as partners with offers + approved stamp image names.
//

import Foundation

struct PartnerCatalog: Codable {
    struct Entry: Codable {
        var osmId: String
        var offer: String
        /// Base name in the asset catalog (e.g. `Randall` for `Randall.png`). QR payload must match (case-insensitive; optional `.png` stripped).
        var imageName: String?
        /// Legacy: used when `imageName` is missing — same semantics as `imageName`.
        var stampCode: String?
        /// Legacy: treated like `imageName` when the others are absent.
        var logoAssetName: String?

        var latitude: Double?
        var longitude: Double?

        /// Token for QR matching and `Image(_)`; empty if the JSON entry is misconfigured.
        var stampImageName: String {
            for key in [imageName, stampCode, logoAssetName] {
                guard let raw = key?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { continue }
                return Self.stripPNGExtension(raw)
            }
            return ""
        }

        static func stripPNGExtension(_ s: String) -> String {
            var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.lowercased().hasSuffix(".png") {
                t = String(t.dropLast(4))
            }
            return t
        }

        static func normalizeToken(_ s: String) -> String {
            stripPNGExtension(s).lowercased()
        }
    }

    var partners: [Entry]

    static func load(from bundle: Bundle) -> PartnerCatalog {
        let urls = [
            bundle.url(forResource: "partners", withExtension: "json", subdirectory: "Resources"),
            bundle.url(forResource: "partners", withExtension: "json"),
        ].compactMap { $0 }
        for url in urls {
            if let data = try? Data(contentsOf: url),
               let p = try? JSONDecoder().decode(PartnerCatalog.self, from: data) {
                return p
            }
        }
        return PartnerCatalog(partners: [])
    }

    func match(osmId: String) -> Entry? {
        partners.first { $0.osmId == osmId }
    }

    /// Partner is approved when the QR payload matches a catalog `imageName` (or legacy `stampCode` / `logoAssetName`).
    func match(qrToken raw: String) -> Entry? {
        let q = Entry.normalizeToken(raw)
        guard !q.isEmpty else { return nil }
        return partners.first {
            let p = Entry.normalizeToken($0.stampImageName)
            return !p.isEmpty && p == q
        }
    }
}
