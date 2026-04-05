//
//  BadgeCatalog.swift
//  Venture Local
//

import Foundation
import SwiftData

enum BadgeTier: String, CaseIterable, Identifiable {
    case copper
    case silver
    case gold
    case platinum
    case special

    var id: String { rawValue }

    var title: String {
        switch self {
        case .copper: "Copper"
        case .silver: "Silver"
        case .gold: "Gold"
        case .platinum: "Platinum"
        case .special: "Special"
        }
    }

    var xpAward: Int {
        switch self {
        case .copper: 10
        case .silver: 30
        case .gold: 85
        case .platinum: 210
        case .special: 300
        }
    }
}

struct BadgeDefinition: Identifiable {
    let code: String
    let title: String
    let requirement: String
    let tier: BadgeTier
    let symbol: String
    let xpAward: Int
    let unlockRule: ((BadgeProgressSnapshot) -> Bool)?
    /// When locked, UI shows a mystery blurb instead of `requirement` until unlocked.
    let obscuresRequirementWhenLocked: Bool

    var id: String { code }
    var isTrackableNow: Bool { unlockRule != nil }
}

struct BadgeProgressSnapshot {
    var totalVisits: Int
    var nonChainVisits: Int
    var stamps: Int
    var level: Int
    var categoryCounts: [DiscoveryCategory: Int]
    var cityCompletion01: Double
    var cityCategories25: Bool
    var unlockedCount: Int
    var homeCityVisits: Int

    var savedPlaceCount: Int
    var favoritedPlaceCount: Int
    var maxPlacesSingleOuting: Int
    var maxPlacesSingleDay: Int
    var maxPlacesSingleWeekend: Int
    var distinctWeekendsWithVisit: Int
    var visitsBefore9AM: Int
    var visitsAfter8PM: Int
    /// Populated when visit-time weather is recorded (Phase C); otherwise rules stay false.
    var hadRainyVisit: Bool
    var placesWithTwoPlusCheckins: Int
    var hasAnyPlaceVisitedTwice: Bool
    var treasureSavedVisitedIntersect: Int
    var curiosityLongSaveVisit: Bool
    var hiddenAlley: Bool
    /// Distinct Hidden Gem POIs discovered (category), ignoring save order.
    var distinctHiddenGemPlaces: Int
    var natureBreakSameDay: Bool
    var picnicOuting: Bool
    var dateNightSameDay: Bool
    var dessertDashSameDay: Bool
    var trailMix: Bool
    var tripleThreatOutingCount: Int
    var partnerLocationsVisitedDistinct: Int
    var coffeeDistinct: Int
    var teaBobaDistinct: Int
    var dessertDistinct: Int
    var tacoDistinct: Int
    var pizzaDistinct: Int
    var burgerDistinct: Int
    var brunchDistinct: Int
    var bookstoreDistinct: Int
    var galleryDistinct: Int
    var gardenDistinct: Int
    var recordDistinct: Int
    var trailDistinct: Int
    var libraryDistinct: Int
    var communityDistinct: Int
    var farmersMarketDistinct: Int
    var placesWithJournalNote: Int

    /// Phase B: non-chain discoveries in selected city within ~1.4 km of local-business centroid.
    var downtownPlacesVisitedDistinct: Int
    /// Distinct grid “neighborhood” cells (non-chain) with at least one discovery in the selected city.
    var neighborhoodSectorsVisitedDistinct: Int
    /// Grid cells (selected city) with ≥3 local POIs where every POI is discovered.
    var fullyCompletedNeighborhoodCount: Int
    /// Curated + auto grid trails fully completed (selected city cache).
    var curatedTrailsCompletedCount: Int
    /// Distinct places with a local photo moment logged (see `PlacePhotoCheckIn`).
    var distinctPlacesWithPhotoCheckIn: Int
    /// ≥75% of locals in one grid cell (≥8 POIs) and ≥5 places there visited twice+.
    var neighborhoodHeroMet: Bool

    /// Distinct `cityKey` values among discoveries.
    var distinctCitiesWithDiscoveries: Int
    /// Profile: times user opened the Badges tab.
    var badgesScreenVisitCount: Int
    var onboardingComplete: Bool
    /// At least one claimed visit in a different state/region than the profile `homeCityKey` (parsed via `CityKey`).
    var hasVisitedOutsideHomeState: Bool
    /// Visited the Chapman Agora partner (see `partners.json`).
    var hasVisitedPantherPridePlace: Bool
    /// At least one discovered place lies in the San Diego metro area (see `CityKey.isInSanDiegoMetro`).
    var hasVisitedSanDiegoMetro: Bool

    var distinctCategoriesVisited: Int {
        categoryCounts.values.filter { $0 > 0 }.count
    }
}

enum BadgeCatalog {
    static let all: [BadgeDefinition] = {
        var rows: [BadgeDefinition] = []

        func symbolFor(_ title: String, tier: BadgeTier) -> String {
            let t = title.lowercased()
            if t.contains("coffee") || t.contains("caffeine") || t.contains("tea") || t.contains("boba") { return "cup.and.saucer.fill" }
            if t.contains("sweet") || t.contains("dessert") { return "birthday.cake.fill" }
            if t.contains("park") || t.contains("trail") || t.contains("nature") || t.contains("green") { return "leaf.fill" }
            if t.contains("hidden") || t.contains("treasure") { return "sparkles" }
            if t.contains("book") || t.contains("library") { return "books.vertical.fill" }
            if t.contains("shop") || t.contains("market") || t.contains("record") { return "bag.fill" }
            if t.contains("taco") || t.contains("pizza") || t.contains("burger") || t.contains("brunch") || t.contains("food") { return "fork.knife" }
            if t.contains("night") || t.contains("date") { return "moon.stars.fill" }
            if t.contains("sunrise") || t.contains("early") || t.contains("morning") { return "sun.max.fill" }
            if t.contains("passport") || t.contains("stamp") { return "seal.fill" }
            if t.contains("local") || t.contains("community") || t.contains("hometown") || t.contains("hero") { return "building.2.fill" }
            if t.contains("city") || t.contains("downtown") || t.contains("neighborhood") { return "building.columns.fill" }
            if t.contains("collection") || t.contains("collector") || t.contains("badge") { return "rosette" }
            if t.contains("legend") || t.contains("master") || t.contains("ambassador") { return "crown.fill" }
            if t.contains("threshold") || t.contains("download") { return "door.left.hand.open" }
            if t.contains("browser") || t.contains("serial") { return "eye.fill" }
            if t.contains("panther") || t.contains("pride") { return "pawprint.fill" }
            if t.contains("homecoming") { return "house.and.flag.fill" }
            if t.contains("state explorer") { return "globe.americas.fill" }
            if t.contains("summit") { return "mountain.2.fill" }
            if t.contains("laureate") { return "medal.star.fill" }
            if t.contains("century") { return "100.circle.fill" }
            if t.contains("borough") { return "map.fill" }
            if t.contains("network") { return "network" }
            if t.contains("indie") { return "hand.raised.fill" }
            if t.contains("photo") || t.contains("moment") { return "camera.fill" }
            switch tier {
            case .copper: return "shield.fill"
            case .silver: return "medal.fill"
            case .gold: return "trophy.fill"
            case .platinum: return "crown.fill"
            case .special: return "sparkles"
            }
        }

        func codeFor(_ title: String) -> String {
            title.lowercased()
                .replacingOccurrences(of: "’", with: "")
                .replacingOccurrences(of: "'", with: "")
                .replacingOccurrences(of: "—", with: " ")
                .split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
                .joined(separator: "_")
        }

        func rule(_ title: String) -> ((BadgeProgressSnapshot) -> Bool)? {
            switch title {
            case "First Steps": return { $0.totalVisits >= 1 }
            case "Hidden Find": return { ($0.categoryCounts[.hiddenGems] ?? 0) >= 1 }
            case "Shop Small": return { ($0.categoryCounts[.shopping] ?? 0) >= 3 }
            case "Around the Block": return { $0.totalVisits >= 5 }
            case "Passport Stamp": return { $0.stamps >= 1 }
            case "Passport Filled": return { $0.stamps >= 5 }
            case "Independent Only": return { $0.nonChainVisits >= 3 }
            case "City Sampler": return { $0.distinctCategoriesVisited >= 3 }
            case "Small Town Spirit": return { $0.homeCityVisits >= 3 }
            case "Hometown Hero": return { $0.cityCompletion01 >= 0.10 }
            case "Local Rookie": return { $0.level >= 2 }
            case "Explorer’s Start": return { $0.level >= 3 }
            case "Foodie Tour": return { ($0.categoryCounts[.food] ?? 0) >= 10 }
            case "Local Shopper": return { ($0.categoryCounts[.shopping] ?? 0) >= 10 }
            case "Outdoor Enthusiast": return { ($0.categoryCounts[.outdoor] ?? 0) >= 10 }
            case "Entertainment Expert": return { ($0.categoryCounts[.entertainment] ?? 0) >= 10 }
            case "Hidden Gem Collector": return { ($0.categoryCounts[.hiddenGems] ?? 0) >= 10 }
            case "Passport Page Complete": return { $0.stamps >= 10 }
            case "Local Legend in Training": return { $0.level >= 10 }
            case "Category Master": return { $0.cityCategories25 }
            case "No Chains Allowed": return { $0.nonChainVisits >= 20 }
            case "City Quarter": return { $0.cityCompletion01 >= 0.25 }
            case "First Collection": return { $0.unlockedCount >= 5 }
            case "Collector": return { $0.unlockedCount >= 25 }

            case "Coffee Run": return { $0.coffeeDistinct >= 2 }
            case "Sweet Tooth": return { $0.dessertDistinct >= 2 }
            case "Park Walker": return { ($0.categoryCounts[.outdoor] ?? 0) >= 2 }
            case "Book Hunter": return { $0.bookstoreDistinct >= 2 }
            case "Taco Time": return { $0.tacoDistinct >= 2 }
            case "Weekend Wanderer": return { $0.maxPlacesSingleWeekend >= 3 }
            case "Sunrise Explorer": return { $0.visitsBefore9AM >= 1 }
            case "Night Owl": return { $0.visitsAfter8PM >= 1 }
            case "Window Shopper": return { $0.savedPlaceCount >= 10 }
            case "Quick Trip": return { $0.maxPlacesSingleOuting >= 2 }
            case "Tea Time": return { $0.teaBobaDistinct >= 2 }
            case "Slice Seeker": return { $0.pizzaDistinct >= 2 }
            case "Nature Break": return { $0.natureBreakSameDay }
            case "Art Appreciator": return { $0.galleryDistinct >= 2 }
            case "Arcade Adventurer": return { ($0.categoryCounts[.entertainment] ?? 0) >= 2 }
            case "Picnic Planner": return { $0.picnicOuting }
            case "Brunch Club": return { $0.brunchDistinct >= 2 }
            case "Burger Quest": return { $0.burgerDistinct >= 2 }
            case "Local Loyalist": return { $0.hasAnyPlaceVisitedTwice }
            case "Hidden Alley": return { $0.hiddenAlley }
            case "Green Thumb": return { $0.gardenDistinct >= 2 }
            case "Record Collector": return { $0.recordDistinct >= 2 }
            case "Market Morning": return { $0.farmersMarketDistinct >= 1 }
            case "Trail Tester": return { $0.trailDistinct >= 2 }
            case "Dessert Dash": return { $0.dessertDashSameDay }
            case "Treasure Hunter": return { $0.treasureSavedVisitedIntersect >= 5 }
            case "New Favorite": return { $0.favoritedPlaceCount >= 1 }
            case "Library Explorer": return { $0.libraryDistinct >= 1 }
            case "Caffeine Circuit": return { $0.coffeeDistinct >= 3 }
            case "Date Night": return { $0.dateNightSameDay }
            case "Trail Mix": return { $0.trailMix }
            case "Community Corner": return { $0.communityDistinct >= 1 }
            case "Curiosity Badge": return { $0.curiosityLongSaveVisit }

            case "Full Day Adventure": return { $0.maxPlacesSingleDay >= 5 }
            case "Coffee Connoisseur": return { $0.coffeeDistinct >= 10 }
            case "Sweet Explorer": return { $0.dessertDistinct >= 10 }
            case "Night Explorer": return { $0.visitsAfter8PM >= 10 }
            case "Early Bird": return { $0.visitsBefore9AM >= 10 }
            case "Weekend Warrior": return { $0.distinctWeekendsWithVisit >= 5 }
            case "Hidden Trail": return { $0.distinctHiddenGemPlaces >= 4 }
            case "The Regular": return { $0.placesWithTwoPlusCheckins >= 5 }
            case "Triple Threat": return { $0.tripleThreatOutingCount >= 3 }
            case "Local Circle": return { $0.partnerLocationsVisitedDistinct >= 5 }

            case "City Storyteller": return { $0.placesWithJournalNote >= 25 }

            case "Downtown Dabbler": return { $0.downtownPlacesVisitedDistinct >= 3 }
            case "Across Town": return { $0.neighborhoodSectorsVisitedDistinct >= 3 }
            case "Downtown Complete": return { $0.fullyCompletedNeighborhoodCount >= 1 }
            case "Trail Blazer": return { $0.curatedTrailsCompletedCount >= 5 }
            case "Photo Finish": return { $0.distinctPlacesWithPhotoCheckIn >= 6 }
            case "Neighborhood Hero": return { $0.neighborhoodHeroMet }

            case "Stamp Circuit": return { $0.stamps >= 20 }
            case "Indie Champion": return { $0.nonChainVisits >= 55 }
            case "Half City Hero": return { $0.cityCompletion01 >= 0.5 }
            case "Trail Devotee": return { $0.curatedTrailsCompletedCount >= 8 }
            case "Borough Rover": return { $0.neighborhoodSectorsVisitedDistinct >= 8 }
            case "Partner Network": return { $0.partnerLocationsVisitedDistinct >= 8 }
            case "Century Stops": return { $0.totalVisits >= 100 }
            case "Badge Laureate": return { $0.unlockedCount >= 35 }

            case "Summit Seeker": return {
                $0.cityCompletion01 >= 0.88 && $0.level >= 20 && $0.nonChainVisits >= 70
            }

            case "Panther Pride": return { $0.hasVisitedPantherPridePlace }
            case "Homecoming": return { $0.hasVisitedSanDiegoMetro }
            case "The Threshold": return { $0.onboardingComplete }
            case "Serial Browser": return { $0.badgesScreenVisitCount >= 25 }
            case "State Explorer": return { $0.hasVisitedOutsideHomeState }

            case "Note Jotted": return { $0.placesWithJournalNote >= 1 }
            case "Two-City Tale": return { $0.distinctCitiesWithDiscoveries >= 2 }
            case "Saver’s Dozen": return { $0.savedPlaceCount >= 12 }
            case "Triple Hearts": return { $0.favoritedPlaceCount >= 3 }
            case "Ten Discoveries": return { $0.totalVisits >= 10 }
            case "Sector Scout": return { $0.neighborhoodSectorsVisitedDistinct >= 2 }
            case "Core Duo": return { $0.downtownPlacesVisitedDistinct >= 2 }
            case "Trail Hello": return { $0.trailDistinct >= 1 }
            case "Early Laurels": return { $0.unlockedCount >= 3 }
            case "Evening Habit": return { $0.visitsAfter8PM >= 3 }
            case "Friend Recommendation": return { $0.partnerLocationsVisitedDistinct >= 1 }
            case "Two Hidden Sparks": return { ($0.categoryCounts[.hiddenGems] ?? 0) >= 2 }

            default: return nil
            }
        }

        func add(
            _ tier: BadgeTier,
            _ title: String,
            _ requirement: String,
            obscuresRequirementWhenLocked: Bool = false,
            xpAwardOverride: Int? = nil
        ) {
            rows.append(BadgeDefinition(
                code: codeFor(title),
                title: title,
                requirement: requirement,
                tier: tier,
                symbol: symbolFor(title, tier: tier),
                xpAward: xpAwardOverride ?? tier.xpAward,
                unlockRule: rule(title),
                obscuresRequirementWhenLocked: obscuresRequirementWhenLocked
            ))
        }

        // Copper
        add(.copper, "First Steps", "Visit your first place")
        add(.copper, "Coffee Run", "Visit 2 coffee shops")
        add(.copper, "Sweet Tooth", "Visit 2 dessert spots")
        add(.copper, "Park Walker", "Visit 2 outdoor places")
        add(.copper, "Hidden Find", "Visit 1 Hidden Gem")
        add(.copper, "Book Hunter", "Visit 2 bookstores")
        add(.copper, "Shop Small", "Visit 3 local shops")
        add(.copper, "Taco Time", "Visit 2 taco places")
        add(.copper, "Weekend Wanderer", "Visit 3 places in one weekend")
        add(.copper, "Sunrise Explorer", "Visit a place before 9 AM")
        add(.copper, "Night Owl", "Visit a place after 8 PM")
        add(.copper, "Rain or Shine", "Visit a place on a rainy day")
        add(.copper, "Downtown Dabbler", "Visit 3 places downtown")
        add(.copper, "Window Shopper", "Save 10 places")
        add(.copper, "Local Rookie", "Reach Level 2")
        add(.copper, "Quick Trip", "Visit 2 places in one outing")
        add(.copper, "Tea Time", "Visit 2 tea or boba spots")
        add(.copper, "Slice Seeker", "Visit 2 pizza places")
        add(.copper, "Nature Break", "Visit 1 park and 1 cafe in one day")
        add(.copper, "Art Appreciator", "Visit 2 galleries or murals")
        add(.copper, "Arcade Adventurer", "Visit 2 entertainment spots")
        add(.copper, "Picnic Planner", "Visit a park and a food place in one outing")
        add(.copper, "Brunch Club", "Visit 2 brunch spots")
        add(.copper, "Burger Quest", "Visit 2 burger spots")
        add(.copper, "Around the Block", "Visit 5 places total")
        add(.copper, "Local Loyalist", "Revisit the same place twice")
        add(.copper, "Passport Stamp", "Earn your first business stamp")
        add(.copper, "Hidden Alley", "Visit a hidden gem and save another")
        add(.copper, "Green Thumb", "Visit 2 garden or plant shops")
        add(.copper, "Record Collector", "Visit 2 music or record stores")
        add(.copper, "Small Town Spirit", "Visit 3 places in your home city")
        add(.copper, "Market Morning", "Visit a farmers market")
        add(.copper, "Trail Tester", "Visit 2 trails")
        add(.copper, "Dessert Dash", "Visit 2 dessert places in one day")
        add(.copper, "Independent Only", "Visit 3 non-chain places")
        add(.copper, "City Sampler", "Visit 1 place in 3 different categories")
        add(.copper, "Treasure Hunter", "Save and visit 5 places")
        add(.copper, "Friend Recommendation", "Visit a featured partner location")
        add(.copper, "New Favorite", "Favorite your first place")
        add(.copper, "Library Explorer", "Visit a local library")
        add(.copper, "Caffeine Circuit", "Visit 3 cafes")
        add(.copper, "Date Night", "Visit 1 food and 1 entertainment place in the same night")
        add(.copper, "Hometown Hero", "Reach 10% completion in one city")
        add(.copper, "Trail Mix", "Visit an outdoor place and a hidden gem")
        add(.copper, "Two Hidden Sparks", "Visit 2 Hidden Gem places")
        add(.copper, "First Collection", "Earn 5 badges")
        add(.copper, "Community Corner", "Visit a local community center or event space")
        add(.copper, "Passport Filled", "Fill 5 stamp slots")
        add(.copper, "Curiosity Badge", "Visit a place you had saved for more than a week")
        add(.copper, "Explorer’s Start", "Reach Level 3")
        add(.copper, "Note Jotted", "Write a journal note on 1 discovered place")
        add(.copper, "Two-City Tale", "Discover places in 2 different cities")
        add(.copper, "Saver’s Dozen", "Save 12 places on the map")
        add(.copper, "Triple Hearts", "Favorite 3 places")
        add(.copper, "Ten Discoveries", "Log 10 place visits total")
        add(.copper, "Sector Scout", "Visit places in 2 map grid neighborhoods")
        add(.copper, "Core Duo", "Visit 2 places in the downtown band")
        add(.copper, "Trail Hello", "Visit 1 trail-style outdoor place")
        add(.copper, "Early Laurels", "Unlock 3 badges")
        add(.copper, "Evening Habit", "Visit 3 places after 8 PM")

        // Silver
        add(.silver, "Foodie Tour", "Visit 10 food places")
        add(.silver, "Local Shopper", "Visit 10 shopping places")
        add(.silver, "Outdoor Enthusiast", "Visit 10 outdoor places")
        add(.silver, "Entertainment Expert", "Visit 10 entertainment places")
        add(.silver, "Hidden Gem Collector", "Visit 10 hidden gems")
        add(.silver, "Full Day Adventure", "Visit 5 places in one day")
        add(.silver, "Across Town", "Visit places in 3 different neighborhoods")
        add(.silver, "Coffee Connoisseur", "Visit 10 coffee shops")
        add(.silver, "Sweet Explorer", "Visit 10 dessert places")
        add(.silver, "Night Explorer", "Visit 10 places after 8 PM")
        add(.silver, "Early Bird", "Visit 10 places before 9 AM")
        add(.silver, "Weekend Warrior", "Visit places on 5 different weekends")
        add(.silver, "Passport Page Complete", "Earn 10 business stamps")
        add(.silver, "Local Legend in Training", "Reach Level 10")
        add(.silver, "Category Master", "Reach 25% completion in all 5 categories")
        add(.silver, "Downtown Complete", "Visit every place in one neighborhood/downtown area")
        add(.silver, "No Chains Allowed", "Visit 20 independent businesses")
        add(.silver, "Trail Blazer", "Complete 5 curated trails")
        add(.silver, "Hidden Trail", "Visit 4 different Hidden Gem places")
        add(.silver, "The Regular", "Revisit 5 different places at least twice")
        add(.silver, "Photo Finish", "Log a photo moment at 6 discovered places (place detail)")
        add(.silver, "City Quarter", "Reach 25% completion in one city")
        add(.silver, "Triple Threat", "Visit food, shopping, and entertainment in one outing 3 times")
        add(.silver, "Local Circle", "Visit 5 business partner locations")
        add(.silver, "Collector", "Earn 25 total badges")

        // Gold
        add(.gold, "City Storyteller", "Write journal notes on 25 discovered places")
        add(.gold, "Stamp Circuit", "Collect 20 partner stamps")
        add(.gold, "Indie Champion", "Visit 55 non-chain places")
        add(.gold, "Half City Hero", "Reach 50% local completion in your journal city")
        add(.gold, "Trail Devotee", "Complete 8 curated trails in your journal city")
        add(.gold, "Borough Rover", "Visit places spanning 8 neighborhood grid cells")
        add(.gold, "Partner Network", "Visit 8 different partner locations")
        add(.gold, "Neighborhood Hero", "Dominate a dense cell: 75%+ locals there + 5+ double visits")
        add(.gold, "Century Stops", "Log 100 place visits")
        add(.gold, "Badge Laureate", "Unlock 35 badges")

        // Platinum + Special
        add(.platinum, "Summit Seeker", "Reach ~88% city completion, level 20, and 70 indie visits")
        add(.special, "The Threshold", "Secret: welcome milestone", obscuresRequirementWhenLocked: true, xpAwardOverride: 0)
        add(.special, "Panther Pride", "Secret: Chapman campus spirit", obscuresRequirementWhenLocked: true)
        add(.special, "Serial Browser", "Secret: curiosity about badges", obscuresRequirementWhenLocked: true)
        add(.special, "State Explorer", "Secret: cross a border", obscuresRequirementWhenLocked: true)
        add(.special, "Homecoming", "Visit any place in the San Diego area. Drew and Brandon are both from San Diego—say hi!", obscuresRequirementWhenLocked: true)

        return rows
    }()

    static func badges(for tier: BadgeTier) -> [BadgeDefinition] {
        all.filter { $0.tier == tier }
    }

    static func evaluateAndAward(
        context: ModelContext,
        profile: ExplorerProfile?,
        liveCityKey: String?,
        discoveries: [DiscoveredPlace],
        pois: [CachedPOI],
        stamps: [StampRecord]
    ) throws -> (newUnlocks: [BadgeUnlock], xpAwarded: Int) {
        try ExplorerEventLog.ensureBackfill(
            context: context,
            profile: profile,
            discoveries: discoveries,
            pois: pois
        )

        var unlocked = try context.fetch(FetchDescriptor<BadgeUnlock>())
        var unlockedCodes = Set(unlocked.map(\.code))
        var newRows: [BadgeUnlock] = []
        var xpAwarded = 0

        var didUnlock = true
        while didUnlock {
            didUnlock = false
            let snapshot = makeSnapshot(
                context: context,
                profile: profile,
                liveCityKey: liveCityKey,
                discoveries: discoveries,
                pois: pois,
                stamps: stamps,
                unlockedCount: unlockedCodes.count
            )

            for badge in all where !unlockedCodes.contains(badge.code) {
                guard let rule = badge.unlockRule, rule(snapshot) else { continue }
                let row = BadgeUnlock(code: badge.code, title: badge.title, tierRaw: badge.tier.rawValue, xpAwarded: badge.xpAward)
                context.insert(row)
                unlockedCodes.insert(badge.code)
                unlocked.append(row)
                newRows.append(row)
                xpAwarded += badge.xpAward
                profile?.totalXP += badge.xpAward
                didUnlock = true
            }
        }

        if xpAwarded > 0 {
            try context.save()
        }

        return (newRows, xpAwarded)
    }

    private static func makeSnapshot(
        context: ModelContext,
        profile: ExplorerProfile?,
        liveCityKey: String?,
        discoveries: [DiscoveredPlace],
        pois: [CachedPOI],
        stamps: [StampRecord],
        unlockedCount: Int
    ) -> BadgeProgressSnapshot {
        let eventSort = [SortDescriptor(\ExplorerEvent.occurredAt)]
        let events = (try? context.fetch(FetchDescriptor<ExplorerEvent>(sortBy: eventSort))) ?? []
        let saved = (try? context.fetch(FetchDescriptor<SavedPlace>())) ?? []
        let favorites = (try? context.fetch(FetchDescriptor<FavoritePlace>())) ?? []
        let photos = (try? context.fetch(FetchDescriptor<PlacePhotoCheckIn>())) ?? []
        return BadgeProgressEngine.makeSnapshot(
            context: context,
            profile: profile,
            liveCityKey: liveCityKey,
            discoveries: discoveries,
            pois: pois,
            stamps: stamps,
            events: events,
            savedPlaces: saved,
            favorites: favorites,
            photoCheckIns: photos,
            unlockedCount: unlockedCount,
            partners: PartnerCatalog.load(from: .main)
        )
    }
}
