//
//  PartnerCatalog.swift
//  Venture Local
//
//  Optional bundle JSON: override specific OSM ids as partners with offers + stamp codes.
//

import Foundation

struct PartnerCatalog: Codable {
    struct Entry: Codable {
        var osmId: String
        var offer: String
        var stampCode: String
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
}
