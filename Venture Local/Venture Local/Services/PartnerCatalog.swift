//
//  PartnerCatalog.swift
//  Venture Local
//
//  Optional bundle JSON: partners by name (and optional OSM id) with image URL for QR matching.
//

import Foundation

struct PartnerCatalog: Codable {
    struct Entry: Codable, Hashable {
        /// Explicit OSM / Apple id when known; otherwise assigned when decoding minimal entries.
        var osmId: String
        var offer: String
        var imageName: String?
        var stampCode: String?
        var logoAssetName: String?

        var latitude: Double?
        var longitude: Double?

        /// Human-readable name from JSON (`name` key).
        var listingName: String?

        /// Full stamp artwork URL; the QR code at the venue should encode this exact URL (trimmed, case-insensitive match).
        var imageURLString: String?

        private enum CodingKeys: String, CodingKey {
            case osmId
            case offer
            case imageName
            case stampCode
            case logoAssetName
            case latitude
            case longitude
            case name
            case address
            case description
            case image
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            osmId = try c.decodeIfPresent(String.self, forKey: .osmId)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            offer = try c.decodeIfPresent(String.self, forKey: .offer)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            imageName = try c.decodeIfPresent(String.self, forKey: .imageName)
            stampCode = try c.decodeIfPresent(String.self, forKey: .stampCode)
            logoAssetName = try c.decodeIfPresent(String.self, forKey: .logoAssetName)
            latitude = try c.decodeIfPresent(Double.self, forKey: .latitude)
            longitude = try c.decodeIfPresent(Double.self, forKey: .longitude)

            let name = try c.decodeIfPresent(String.self, forKey: .name)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            _ = try c.decodeIfPresent(String.self, forKey: .address)
            let description = try c.decodeIfPresent(String.self, forKey: .description)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let image = try c.decodeIfPresent(String.self, forKey: .image)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            listingName = name
            imageURLString = image.flatMap { $0.isEmpty ? nil : $0 }

            if offer.isEmpty {
                if let name, let description, !description.isEmpty {
                    offer = "\(name) — \(description)"
                } else if let name, !name.isEmpty {
                    offer = name
                }
            }

            if osmId.isEmpty {
                let basis = name ?? image ?? offer
                osmId = basis.isEmpty ? "partner:unknown" : "partner:\(Self.stableId(from: basis))"
            }
        }

        /// Encode back for tests (full manual encode).
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(osmId, forKey: .osmId)
            try c.encode(offer, forKey: .offer)
            try c.encodeIfPresent(imageName, forKey: .imageName)
            try c.encodeIfPresent(stampCode, forKey: .stampCode)
            try c.encodeIfPresent(logoAssetName, forKey: .logoAssetName)
            try c.encodeIfPresent(latitude, forKey: .latitude)
            try c.encodeIfPresent(longitude, forKey: .longitude)
            try c.encodeIfPresent(listingName, forKey: .name)
            try c.encodeIfPresent(imageURLString, forKey: .image)
        }

        private static func stableId(from string: String) -> String {
            var h: UInt64 = 5381
            for u in string.utf8 {
                h = ((h << 5) &+ h) &+ UInt64(u)
            }
            return String(h, radix: 16, uppercase: false)
        }

        /// Local asset base name (no `.png`), if configured.
        var stampImageName: String {
            for key in [imageName, stampCode, logoAssetName] {
                guard let raw = key?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { continue }
                return Self.stripPNGExtension(raw)
            }
            return ""
        }

        /// Stored on `CachedPOI.stampCode` — URL token or asset token for debugging / future use.
        var stampCodeForStorage: String? {
            let asset = stampImageName
            if let url = imageURLString, !url.isEmpty { return PartnerCatalog.normalizeQRImagePayload(url) }
            return asset.isEmpty ? nil : asset
        }

        /// Value to compare with scanned QR text (after `StampQRParser.extractStampCode`).
        var qrMatchToken: String {
            if let url = imageURLString, !url.isEmpty {
                return PartnerCatalog.normalizeQRImagePayload(url)
            }
            return Entry.normalizeToken(stampImageName)
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

        var displayTitle: String {
            if let n = listingName, !n.isEmpty { return n }
            let o = offer.trimmingCharacters(in: .whitespacesAndNewlines)
            if let r = o.range(of: " — ") { return String(o[..<r.lowerBound]) }
            if let r = o.range(of: " - ") { return String(o[..<r.lowerBound]) }
            if !o.isEmpty { return o }
            let img = stampImageName
            return img.isEmpty ? osmId : img
        }

        func matchesListing(name poiName: String) -> Bool {
            let p = Self.normalizeListingName(poiName)
            let target = Self.normalizeListingName(displayTitle)
            guard !target.isEmpty, !p.isEmpty else { return false }
            if p == target { return true }
            if p.hasPrefix(target) {
                let rest = p.dropFirst(target.count).trimmingCharacters(in: .whitespacesAndNewlines)
                return rest.isEmpty || rest.hasPrefix(",") || rest.hasPrefix("-") || rest.hasPrefix("—")
            }
            return false
        }

        private static func normalizeListingName(_ s: String) -> String {
            s.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: "’", with: "'")
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

    /// Partner row for a cached map place: explicit id first, else **name** appears in `partners.json`.
    func matchPartnerPOI(name: String, osmId: String) -> Entry? {
        if let e = match(osmId: osmId) { return e }
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return nil }
        return partners.first { $0.matchesListing(name: n) }
    }

    /// QR must match the partner’s **image URL** (normalized) or legacy asset/stamp token.
    func match(qrToken raw: String) -> Entry? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let qURL = PartnerCatalog.normalizeQRImagePayload(trimmed)
        let qLegacy = Entry.normalizeToken(trimmed)

        return partners.first { entry in
            let tURL = entry.qrMatchToken
            if !tURL.isEmpty, tURL == qURL { return true }
            let legacy = Entry.normalizeToken(entry.stampImageName)
            return !legacy.isEmpty && legacy == qLegacy
        }
    }

    /// Normalize URLs and plain tokens for QR equality (trim, lowercase, strip trailing slashes).
    static func normalizeQRImagePayload(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while t.hasSuffix("/") { t.removeLast() }
        return t
    }
}
