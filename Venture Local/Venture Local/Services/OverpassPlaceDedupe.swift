//
//  OverpassPlaceDedupe.swift
//  Venture Local
//
//  Pure string/coordinate matching with no SwiftData import — safe to call from `Task.detached` while
//  `POISyncService` remains main-actor-isolated due to persistence APIs.
//

import CoreLocation
import Foundation

enum OverpassPlaceDedupe {
    /// Lowercase, diacritic-folded, alphanumeric tokens — comparable across OSM vs Apple naming.
    static func normalizedPlaceName(_ raw: String) -> String {
        let folded = raw.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
        var t = folded.lowercased()
        t = t.replacingOccurrences(of: "\u{2019}", with: "")
        t = t.replacingOccurrences(of: "'", with: "")
        t = t.replacingOccurrences(of: "`", with: "")
        let parts = t.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        return parts.joined(separator: " ")
    }

    static func isUnwantedPOIName(_ raw: String) -> Bool {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.isEmpty { return true }
        if t == "unknown" || t.hasPrefix("unknown ") { return true }
        if t == "unnamed" || t == "unnamed place" || t.hasPrefix("unnamed ") { return true }
        return false
    }

    /// True when two pins are likely the same venue despite OSM vs Apple naming differences.
    static func coordinatesAndNamesSuggestSamePlace(
        _ coordA: CLLocationCoordinate2D, nameA: String, categoryRawA: String,
        _ coordB: CLLocationCoordinate2D, nameB: String, categoryRawB: String
    ) -> Bool {
        let d = GeoMath.distanceMeters(coordA, coordB)
        let sameCategory = categoryRawA == categoryRawB
        let na = normalizedPlaceName(nameA)
        let nb = normalizedPlaceName(nameB)

        if na.isEmpty, nb.isEmpty { return d <= 22 }
        if na == nb, d <= 115 { return true }

        let shorter = na.count <= nb.count ? na : nb
        let longer = na.count <= nb.count ? nb : na
        if shorter.count >= 4, longer.contains(shorter), d <= 95 { return true }

        let j = tokenJaccard(na, nb)
        if sameCategory {
            if j >= 0.72, d <= 88 { return true }
            if j >= 0.58, d <= 62 { return true }
            if j >= 0.5, d <= 48 { return true }
            if j >= 0.34, d <= 30 { return true }
        } else {
            if j >= 0.82, d <= 52 { return true }
        }

        let ca = na.filter { $0.isLetter || $0.isNumber }
        let cb = nb.filter { $0.isLetter || $0.isNumber }
        if ca.count >= 4, cb.count >= 4, d <= 58 {
            if levenshteinRatio(String(ca), String(cb)) >= 0.86 { return true }
        }
        if ca.count >= 5, cb.count >= 5, d <= 48 {
            if levenshteinRatio(String(ca), String(cb)) >= 0.88 { return true }
        }

        return false
    }

    private static func tokenJaccard(_ normalizedA: String, _ normalizedB: String) -> Double {
        let a = Set(normalizedA.split(separator: " ").map(String.init))
        let b = Set(normalizedB.split(separator: " ").map(String.init))
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        let i = a.intersection(b).count
        return Double(i) / Double(a.union(b).count)
    }

    private static func levenshteinRatio(_ s1: String, _ s2: String) -> Double {
        let a = Array(s1)
        let b = Array(s2)
        let m = a.count, n = b.count
        if m == 0 { return n == 0 ? 1 : 0 }
        if n == 0 { return 0 }
        var dp = Array(0 ... n)
        for i in 1 ... m {
            var prev = dp[0]
            dp[0] = i
            for j in 1 ... n {
                let temp = dp[j]
                if a[i - 1] == b[j - 1] {
                    dp[j] = prev
                } else {
                    dp[j] = min(prev + 1, dp[j] + 1, dp[j - 1] + 1)
                }
                prev = temp
            }
        }
        let dist = dp[n]
        return 1.0 - Double(dist) / Double(max(m, n))
    }
}
