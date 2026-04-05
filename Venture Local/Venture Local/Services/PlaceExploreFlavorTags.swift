//
//  PlaceExploreFlavorTags.swift
//  Venture Local
//
//  Single source for “type” hints: badge progress heuristics, map/voice labels, and voice-search tightening.
//

import Foundation

enum PlaceExploreFlavorKind: String, CaseIterable, Hashable {
    case coffee, teaBoba, dessert, taco, pizza, burger, brunch, sushi
    case bookstore, gallery, garden, record, trail, library, community, farmersMarket

    /// Short labels shown on the map sheet and place detail (ties to badge themes).
    var chipTitle: String {
        switch self {
        case .coffee: return "Coffee"
        case .teaBoba: return "Tea & boba"
        case .dessert: return "Dessert"
        case .taco: return "Tacos"
        case .pizza: return "Pizza"
        case .burger: return "Burgers"
        case .brunch: return "Brunch"
        case .sushi: return "Sushi"
        case .bookstore: return "Bookstore"
        case .gallery: return "Gallery"
        case .garden: return "Garden"
        case .record: return "Records"
        case .trail: return "Trail"
        case .library: return "Library"
        case .community: return "Community"
        case .farmersMarket: return "Farmers market"
        }
    }
}

enum PlaceExploreFlavorTags {
    /// All flavor signals for this POI (used for badges and voice intent matching).
    static func kinds(for poi: CachedPOI) -> Set<PlaceExploreFlavorKind> {
        let n = poi.name.lowercased()
        let cat = DiscoveryCategory(rawValue: poi.categoryRaw)
        var out: Set<PlaceExploreFlavorKind> = []

        if cat == .food {
            if n.contains("boba") || n.contains("bubble tea") || n.contains("milk tea") || n.contains("tea house") || n.contains("teahouse") {
                out.insert(.teaBoba)
            } else if n.contains("coffee") || n.contains("cafe") || n.contains("espresso") || n.contains("roaster") {
                out.insert(.coffee)
            }
            if isDessert(name: poi.name, category: cat) { out.insert(.dessert) }
            if n.contains("taco") || n.contains("taqueria") { out.insert(.taco) }
            if n.contains("pizza") { out.insert(.pizza) }
            if n.contains("burger") { out.insert(.burger) }
            if n.contains("brunch") { out.insert(.brunch) }
            if n.contains("sushi") || n.contains("sashimi") {
                out.insert(.sushi)
            }

            if let meta = POIExtendedMetadataCodec.decode(poi.extendedMetadataJSON),
               let c = meta.osmTags?["cuisine"]?.lowercased() {
                if c.contains("burger") || c.contains("hamburger") { out.insert(.burger) }
                if c.contains("pizza") { out.insert(.pizza) }
                if c.contains("taco") || c.contains("tex-mex") || c.contains("tex_mex") { out.insert(.taco) }
                if c.contains("sushi") { out.insert(.sushi) }
            }
        }

        if n.contains("book") && (n.contains("store") || n.contains("shop") || n.contains("books")) {
            out.insert(.bookstore)
        }
        if n.contains("gallery") || n.contains("mural") || n.contains("art museum") {
            out.insert(.gallery)
        }
        if n.contains("garden") || n.contains("nursery") || n.contains("plant") {
            out.insert(.garden)
        }
        if n.contains("record") || n.contains("vinyl") {
            out.insert(.record)
        }
        if cat == .outdoor, n.contains("trail") || n.contains("hike") {
            out.insert(.trail)
        }
        if n.contains("library") {
            out.insert(.library)
        }
        if (n.contains("community") && (n.contains("center") || n.contains("centre"))) || n.contains("event space") {
            out.insert(.community)
        }
        if n.contains("farmer") && n.contains("market") {
            out.insert(.farmersMarket)
        }

        return out
    }

    /// Up to four chips: structured flavors first, then a primary OSM cuisine word if it adds detail.
    static func displayChips(for poi: CachedPOI) -> [String] {
        let k = kinds(for: poi)
        let order: [PlaceExploreFlavorKind] = [
            .burger, .taco, .pizza, .sushi, .brunch,
            .coffee, .teaBoba, .dessert,
            .bookstore, .gallery, .garden, .record, .trail, .library, .community, .farmersMarket,
        ]
        var labels: [String] = []
        for x in order where k.contains(x) {
            labels.append(x.chipTitle)
        }
        if let cuisine = primaryOsmCuisineLabel(poi) {
            let cNorm = cuisine.lowercased()
            let redundant = labels.contains { $0.lowercased() == cNorm }
                || (cNorm.contains("mexican") && k.contains(.taco))
                || (cNorm.contains("italian") && k.contains(.pizza))
                || (cNorm.contains("american") && k.contains(.burger))
                || (cNorm.contains("japanese") && k.contains(.sushi))
            if !redundant {
                labels.append(cuisine)
            }
        }
        return Array(labels.prefix(4))
    }

    private static func primaryOsmCuisineLabel(_ poi: CachedPOI) -> String? {
        guard let meta = POIExtendedMetadataCodec.decode(poi.extendedMetadataJSON),
              let raw = meta.osmTags?["cuisine"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else { return nil }
        let first = raw.split(separator: ";").first.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? raw
        guard !first.isEmpty else { return nil }
        return first
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    private static func isDessert(name: String, category: DiscoveryCategory?) -> Bool {
        guard category == .food else { return false }
        let n = name.lowercased()
        return n.contains("dessert") || n.contains("ice cream") || n.contains("bakery")
            || n.contains("sweet") || n.contains("cake") || n.contains("donut") || n.contains("pastry")
    }
}
