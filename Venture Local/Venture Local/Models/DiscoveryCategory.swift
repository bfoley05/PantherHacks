//
//  DiscoveryCategory.swift
//  Venture Local
//

import Foundation

enum DiscoveryCategory: String, CaseIterable, Codable, Identifiable {
    case shopping
    case entertainment
    case outdoor
    case food
    case hiddenGems

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .shopping: "Shopping"
        case .entertainment: "Entertainment"
        case .outdoor: "Outdoor"
        case .food: "Food"
        case .hiddenGems: "Hidden Gems"
        }
    }

    var symbol: String {
        switch self {
        case .shopping: "bag.fill"
        case .entertainment: "theatermasks.fill"
        case .outdoor: "leaf.fill"
        case .food: "fork.knife"
        case .hiddenGems: "sparkles"
        }
    }

    /// Maps OSM tags to discovery categories (MVP heuristic; refine with richer rules later).
    static func fromOSMTags(_ tags: [String: String]) -> DiscoveryCategory? {
        let amenity = tags["amenity"]?.lowercased()
        let shop = tags["shop"]?.lowercased()
        let leisure = tags["leisure"]?.lowercased()
        let tourism = tags["tourism"]?.lowercased()
        let historic = tags["historic"]?.lowercased()

        if let h = historic, ["monument", "memorial", "castle", "ruins", "archaeological_site"].contains(h) {
            return .hiddenGems
        }
        if tourism == "artwork" || tourism == "viewpoint" || tourism == "attraction" {
            return .hiddenGems
        }
        if leisure == "park" || leisure == "nature_reserve" || leisure == "garden" {
            return .outdoor
        }
        if amenity == "theatre" || amenity == "arts_centre" || amenity == "cinema"
            || amenity == "nightclub" || leisure == "bowling_alley" || leisure == "escape_game" {
            return .entertainment
        }
        if let a = amenity, ["restaurant", "cafe", "fast_food", "bar", "pub", "food_court", "ice_cream", "biergarten"].contains(a) {
            return .food
        }
        if shop != nil || amenity == "marketplace" {
            return .shopping
        }
        if tourism == "museum" || amenity == "museum" {
            return .entertainment
        }
        if amenity == "place_of_worship" {
            return .hiddenGems
        }
        return nil
    }
}
