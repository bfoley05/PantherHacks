//
//  DiscoveryCategory.swift
//  Venture Local
//

import Foundation
import SwiftUI

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

    /// Compact labels for map category chips so all fit without horizontal scrolling.
    var mapChipLabel: String {
        switch self {
        case .shopping: "Shop"
        case .entertainment: "Fun"
        case .outdoor: "Parks"
        case .food: "Food"
        case .hiddenGems: "Gems"
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

    /// Muted fills: Shop blue, Fun red, Parks green, Food orange, Gems purple (matches map pins).
    var mapPinMutedFill: Color {
        switch self {
        case .shopping:
            Color(red: 0.44, green: 0.56, blue: 0.72)
        case .entertainment:
            Color(red: 0.71, green: 0.40, blue: 0.42)
        case .outdoor:
            Color(red: 0.46, green: 0.62, blue: 0.50)
        case .food:
            Color(red: 0.76, green: 0.54, blue: 0.38)
        case .hiddenGems:
            Color(red: 0.58, green: 0.48, blue: 0.70)
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
        if tourism == "artwork" || tourism == "viewpoint" {
            return .hiddenGems
        }
        if leisure == "park" || leisure == "nature_reserve" || leisure == "garden" {
            return .outdoor
        }

        // Fun / entertainment — broad OSM coverage (mini golf, laser tag, arcades, etc.).
        let amenityFun: Set<String> = [
            "theatre", "arts_centre", "cinema", "nightclub", "karaoke_box", "planetarium",
            "events_venue", "conference_centre", "music_venue",
        ]
        let leisureFun: Set<String> = [
            "bowling_alley", "escape_game", "escape_room", "amusement_arcade",
            "miniature_golf", "trampoline_park", "water_park", "dance", "ice_rink",
            "karaoke_box", "adult_gaming_centre", "sports_hall", "disc_golf_course",
            "hackerspace", "indoor_play",
        ]
        let tourismFun: Set<String> = ["theme_park", "aquarium", "zoo", "gallery"]
        if let a = amenity, amenityFun.contains(a) { return .entertainment }
        if let l = leisure, leisureFun.contains(l) { return .entertainment }
        if let t = tourism, tourismFun.contains(t) { return .entertainment }

        if let sport = tags["sport"]?.lowercased() {
            let funSports: Set<String> = [
                "laser_tag", "karting", "paintball", "climbing", "trampoline",
                "skateboard", "roller_skating", "ice_skating", "archery", "shooting",
            ]
            if funSports.contains(sport) { return .entertainment }
        }
        if leisure == "sports_centre" || leisure == "pitch" || leisure == "track" {
            if let sport = tags["sport"]?.lowercased(),
               ["laser_tag", "karting", "paintball", "climbing", "trampoline", "skateboard"].contains(sport) {
                return .entertainment
            }
            if nameSuggestsFunVenue(tags["name"]) { return .entertainment }
        }

        // Generic attraction: sort into Fun when the name clearly describes an activity venue.
        if tourism == "attraction", nameSuggestsFunVenue(tags["name"]) { return .entertainment }
        if tourism == "attraction" { return .hiddenGems }

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
        if nameSuggestsFunVenue(tags["name"]) { return .entertainment }
        return nil
    }

    /// Name keywords for activity / entertainment venues (pairs with OSM tags and Apple POI names).
    static func nameSuggestsFunVenue(_ name: String?) -> Bool {
        guard let n = name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !n.isEmpty else { return false }
        let hints = [
            "mini golf", "miniature golf", "putt-putt", "putt putt", "puttputt",
            "laser tag", "lazer tag", "lasertag",
            "trampoline", "bounce park", "bounce house", "jump park",
            "video arcade", "barcade", "nickel arcade", " pinball", "pinball ",
            "escape room", "escape game",
            "bowling alley", "bowling lanes", "bowling center", "bowling centre",
            "bowl-a-rama", "bowlarama", "ten pin", "tenpin",
            "go-kart", "go kart", "gokart", "karting",
            "ax throwing", "axe throwing", "hatchet",
            "paintball", "airsoft",
            "vr ", "virtual reality", "vr lounge",
            "topgolf", "top golf", "top-golf",
            "dave and buster", "dave & buster", "round1", "round 1",
            "climbing gym", "rock climb", "bouldering",
            "laser maze", "mirror maze",
            "haunted house", "escape the",
            "zip line", "zipline", "rope course", "aerial adventure",
            "billiards", "pool hall", "snooker hall",
            "family fun", "fun center", "fun centre", "entertainment center", "entertainment centre",
            "amusement", "carnival", "fairground",
            "skating rink", "roller rink", "ice rink",
        ]
        return hints.contains { n.contains($0) }
    }
}
