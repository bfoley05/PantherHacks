//
//  StampQRParser.swift
//  Venture Local
//
//  QR payloads: `vl-stamp:TOKEN`, `venturelocal://stamp?code=TOKEN`, or raw token (partner `imageName`, optional `.png`).
//

import Foundation

enum StampQRParser {
    /// Returns the raw token to match against `PartnerCatalog.match(qrToken:)` (image base name), or nil if empty.
    static func extractStampCode(from raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }

        let lower = t.lowercased()
        if lower.hasPrefix("vl-stamp:") {
            let code = String(t.dropFirst("vl-stamp:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return code.isEmpty ? nil : code
        }

        if let url = URL(string: t), let comp = URLComponents(string: t) {
            let scheme = (url.scheme ?? "").lowercased()
            if scheme == "venturelocal" || scheme == "venture-local" {
                if let q = comp.queryItems?.first(where: { $0.name.lowercased() == "code" })?.value,
                   !q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return q.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if !path.isEmpty { return path }
            }
        }

        return t
    }
}
