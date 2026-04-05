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

        if let a = lower["access"], blockedAccess.contains(a) { return true }

        if let h = lower["healthcare"], !h.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }

        if let am = lower["amenity"] {
            if medicalAmenities.contains(am) { return true }
            if schoolAmenities.contains(am) || am.contains("school") { return true }
        }

        if let sh = lower["shop"], medicalShops.contains(sh) { return true }

        if let off = lower["office"] {
            if medicalOffices.contains(off) { return true }
            if off.contains("medical") || off.contains("health") { return true }
        }

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
    ]

    /// Cases vary by SDK; name heuristics in `appleNamePhrases` cover dentist / vet wording.
    private static let excludedAppleCategories: [MKPointOfInterestCategory] = [
        .hospital, .pharmacy, .school, .university,
    ]
}
