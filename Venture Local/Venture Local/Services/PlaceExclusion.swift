//
//  PlaceExclusion.swift
//  Venture Local
//
//  Drops private / restricted OSM features and school / medical POIs for both Overpass and MapKit.
//

import Foundation
import MapKit

enum PlaceExclusion {
    /// OSM `access` values we never show.
    private static let blockedAccess: Set<String> = ["private", "no", "permit"]

    static func shouldExcludeOSMTags(_ tags: [String: String]) -> Bool {
        let lower = Dictionary(uniqueKeysWithValues: tags.map { ($0.key.lowercased(), $0.value.lowercased()) })
        if isLandmarkLike(lower) { return false }

        if let a = lower["access"], blockedAccess.contains(a) { return true }

        if let h = lower["healthcare"], !h.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }

        if let am = lower["amenity"] {
            if medicalAmenities.contains(am) { return true }
            if schoolAmenities.contains(am) || am.contains("school") { return true }
            if automotiveAmenities.contains(am) { return true }
            if financialAmenities.contains(am) { return true }
            if governmentAmenities.contains(am) { return true }
            if industrialAmenities.contains(am) { return true }
            if logisticsAmenities.contains(am) { return true }
            if serviceAmenities.contains(am) { return true }
        }

        if let sh = lower["shop"] {
            if medicalShops.contains(sh) { return true }
            if automotiveShops.contains(sh) { return true }
            if financialShops.contains(sh) { return true }
            if logisticsShops.contains(sh) { return true }
            if industrialShops.contains(sh) { return true }
            if serviceShops.contains(sh) { return true }
        }

        if let off = lower["office"] {
            if medicalOffices.contains(off) { return true }
            if off.contains("medical") || off.contains("health") { return true }
            if professionalOffices.contains(off) { return true }
            if off.contains("school") || off.contains("university") || off.contains("college") { return true }
            if off.contains("government") || off.contains("county") || off.contains("city") { return true }
        }

        if let building = lower["building"], excludedBuildingValues.contains(building) { return true }
        if let landuse = lower["landuse"], excludedLanduseValues.contains(landuse) { return true }
        if let manMade = lower["man_made"], excludedManMadeValues.contains(manMade) { return true }
        if let highway = lower["highway"], excludedHighwayValues.contains(highway) { return true }
        if let railway = lower["railway"], excludedRailwayValues.contains(railway) { return true }

        if let name = lower["name"], looksLikeNonLeisureName(name) { return true }
        return false
    }

    private static let schoolAmenities: Set<String> = [
        "school", "kindergarten", "childcare", "children_centre", "college", "university",
        "driving_school", "language_school", "surf_school", "music_school", "dancing_school",
    ]

    private static let medicalAmenities: Set<String> = [
        "hospital", "clinic", "doctors", "dentist", "pharmacy", "social_facility",
        "nursing_home", "ambulance_station", "blood_donation", "blood_bank", "first_aid",
        "health_centre", "baby_hatch",
    ]

    private static let medicalShops: Set<String> = [
        "chemist", "medical_supply", "hearing_aids", "optician",
    ]

    private static let medicalOffices: Set<String> = [
        "physician", "dentist", "therapist", "healthcare", "medical",
    ]

    private static let automotiveAmenities: Set<String> = [
        "car_wash", "vehicle_inspection", "fuel", "charging_station",
    ]

    private static let financialAmenities: Set<String> = [
        "bank", "atm", "bureau_de_change", "money_transfer",
    ]

    private static let governmentAmenities: Set<String> = [
        "courthouse", "post_office", "police", "fire_station", "townhall",
        "ranger_station", "embassy",
    ]

    private static let industrialAmenities: Set<String> = [
        "waste_transfer_station", "recycling", "compressed_air",
    ]

    private static let logisticsAmenities: Set<String> = [
        "bus_station", "ferry_terminal", "truck_stop",
    ]

    private static let serviceAmenities: Set<String> = [
        "car_rental", "car_sharing", "motorcycle_parking", "vending_machine",
        "laundry",
    ]

    private static let automotiveShops: Set<String> = [
        "car", "car_repair", "car_parts", "tyres", "tire", "fuel",
        "motorcycle", "motorcycle_repair", "truck_repair",
    ]

    private static let financialShops: Set<String> = [
        "money_lender", "pawnbroker", "insurance",
    ]

    private static let logisticsShops: Set<String> = [
        "gas", "fuel", "trade",
    ]

    private static let industrialShops: Set<String> = [
        "storage_rental", "wholesale", "industrial",
    ]

    private static let serviceShops: Set<String> = [
        "plumber", "electrical", "hvac", "security", "copyshop",
        "laundry", "dry_cleaning",
    ]

    private static let professionalOffices: Set<String> = [
        "lawyer", "accountant", "financial", "insurance", "estate_agent",
        "real_estate_agent", "administrative", "company", "it",
        "employment_agency", "government", "energy_supplier",
    ]

    private static let excludedBuildingValues: Set<String> = [
        "industrial", "warehouse", "factory", "office", "government", "civic",
        "service", "garages", "garage", "hospital", "school",
    ]

    private static let excludedLanduseValues: Set<String> = [
        "industrial", "commercial", "retail_park", "construction", "depot",
        "garages", "railway", "port", "military",
    ]

    private static let excludedManMadeValues: Set<String> = [
        "works", "wastewater_plant", "water_works", "silo", "storage_tank",
        "pipeline", "power_wind", "power_hydro",
    ]

    private static let excludedHighwayValues: Set<String> = [
        "service", "rest_area", "motorway_junction", "bus_stop",
        "platform", "traffic_signals",
    ]

    private static let excludedRailwayValues: Set<String> = [
        "station", "halt", "platform", "yard", "depot",
    ]

    private static let nonLeisureNamePhrases: [String] = [
        "auto repair", "mechanic", "tire shop", "tyre shop", "oil change",
        "car wash", "smog check", "transmission", "body shop",
        "hospital", "clinic", "urgent care", "dentist", "dental", "pharmacy",
        "medical center", "health center", "imaging center",
        "bank", "credit union", "atm", "insurance", "tax service", "tax prep",
        "dmv", "courthouse", "post office", "police", "city hall", "county office",
        "warehouse", "distribution center", "fulfillment center", "factory",
        "storage", "self storage", "public storage",
        "law office", "attorney", "accounting", "real estate", "property management",
        "plumbing", "electric", "hvac", "roofing", "contractor",
        "cleaner", "cleaners", "cleaning service", "house cleaning", "janitorial",
        "dry cleaner", "dry cleaners", "dry cleaning", "laundry", "laundromat",
        "gas station", "truck stop", "freight", "logistics",
        "office park", "corporate office", "business park",
        "elementary school", "middle school", "high school", "academy", "campus",
    ]

    private static func looksLikeNonLeisureName(_ name: String) -> Bool {
        nonLeisureNamePhrases.contains { name.contains($0) }
    }

    private static func isLandmarkLike(_ lowerTags: [String: String]) -> Bool {
        if let historic = lowerTags["historic"], !historic.isEmpty { return true }
        if let tourism = lowerTags["tourism"], ["museum", "attraction", "artwork", "viewpoint", "gallery"].contains(tourism) {
            return true
        }
        if let heritage = lowerTags["heritage"], heritage == "yes" || heritage == "1" { return true }
        return false
    }

    /// MapKit categories we never merge (school / medical).
    static func shouldExcludeAppleMapItem(name: String, category: MKPointOfInterestCategory?) -> Bool {
        if let c = category, excludedAppleCategories.contains(c) { return true }
        let n = name.lowercased()
        for phrase in appleNamePhrases where n.contains(phrase) { return true }
        if n.hasSuffix(" school") || n.contains(" school ") { return true }
        return false
    }

    static func shouldExcludeChain(name: String, tags: [String: String], chainDetector: ChainDetector) -> Bool {
        chainDetector.evaluate(name: name, tags: tags).0
    }

    private static let appleNamePhrases: [String] = [
        "hospital", "medical center", "health center", "urgent care", "clinic", "pharmacy",
        "elementary school", "high school", "middle school", "preschool",
        "university", "dental", "dentist", "veterinary", "animal hospital",
        "auto repair", "mechanic", "oil change", "car wash", "tire", "tyre",
        "bank", "atm", "credit union", "insurance", "tax service",
        "dmv", "courthouse", "post office", "police", "city hall",
        "warehouse", "distribution center", "factory", "self storage",
        "law office", "attorney", "accounting", "real estate",
        "plumbing", "electric", "hvac", "roofing", "contractor",
        "cleaner", "cleaners", "cleaning service", "janitorial",
        "dry cleaner", "dry cleaners", "dry cleaning", "laundry", "laundromat",
        "gas station", "truck stop", "logistics", "office park", "corporate office",
    ]

    /// Cases vary by SDK; name heuristics in `appleNamePhrases` cover dentist / vet wording.
    private static let excludedAppleCategories: [MKPointOfInterestCategory] = [
        .hospital, .pharmacy, .school, .university,
    ]
}
