//
//  ChainDetector.swift
//  Venture Local
//
//  MVP: bundled list + OSM brand/operator tags. Remote JSON can replace bundle on launch later.
//

import Foundation

struct ChainDatabase: Codable {
    var version: Int
    var chains: [String]
}

final class ChainDetector: @unchecked Sendable {
    private let queue = DispatchQueue(label: "ChainDetector")
    private var normalizedNames: Set<String> = []

    init(bundle: Bundle = .main) {
        loadFromBundle(bundle)
    }

    func reload(from data: Data) throws {
        let decoded = try JSONDecoder().decode(ChainDatabase.self, from: data)
        let set = Set(decoded.chains.map { Self.normalize($0) })
        queue.sync { normalizedNames = set }
    }

    private func loadFromBundle(_ bundle: Bundle) {
        let urls = [
            bundle.url(forResource: "chains", withExtension: "json", subdirectory: "Resources"),
            bundle.url(forResource: "chains", withExtension: "json"),
        ].compactMap { $0 }
        guard let url = urls.first, let data = try? Data(contentsOf: url) else { return }
        try? reload(from: data)
    }

    /// Returns (isChain, label) when a chain is detected from name/tags.
    func evaluate(name: String, tags: [String: String]) -> (Bool, String?) {
        if let brand = tags["brand"]?.trimmingCharacters(in: .whitespacesAndNewlines), !brand.isEmpty {
            return (true, brand)
        }
        if let op = tags["operator"]?.trimmingCharacters(in: .whitespacesAndNewlines), !op.isEmpty {
            let n = Self.normalize(op)
            if queue.sync(execute: { normalizedNames.contains(where: { n.contains($0) || $0.contains(n) }) }) {
                return (true, op)
            }
        }
        let nName = Self.normalize(name)
        if nName.isEmpty { return (false, nil) }
        let hit = queue.sync {
            normalizedNames.contains { chain in
                nName.contains(chain) || chain.contains(nName)
            }
        }
        if hit {
            return (true, name)
        }
        return (false, nil)
    }

    private static func normalize(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
