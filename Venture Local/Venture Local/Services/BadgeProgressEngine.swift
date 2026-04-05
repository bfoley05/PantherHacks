//
//  BadgeProgressEngine.swift
//  Venture Local
//

import Foundation
import SwiftData

enum BadgeProgressEngine {
    static func makeSnapshot(
        context: ModelContext,
        profile: ExplorerProfile?,
        liveCityKey: String?,
        discoveries: [DiscoveredPlace],
        pois: [CachedPOI],
        stamps: [StampRecord],
        events: [ExplorerEvent],
        savedPlaces: [SavedPlace],
        favorites: [FavoritePlace],
        photoCheckIns: [PlacePhotoCheckIn],
        unlockedCount: Int,
        partners: PartnerCatalog
    ) -> BadgeProgressSnapshot {
        let poiById = Dictionary(uniqueKeysWithValues: pois.map { ($0.osmId, $0) })
        let cal = Calendar.current

        var categoryCounts: [DiscoveryCategory: Int] = [:]
        var nonChain = 0
        var homeCityVisits = 0

        for visit in discoveries {
            guard let poi = poiById[visit.osmId] else { continue }
            if let cat = DiscoveryCategory(rawValue: poi.categoryRaw) {
                categoryCounts[cat, default: 0] += 1
            }
            if !poi.isChain {
                nonChain += 1
            }
            if let home = profile?.homeCityKey, poi.cityKey == home {
                homeCityVisits += 1
            }
        }

        let cityCompletion01: Double = {
            guard let key = profile?.effectiveProgressCityKey(liveCityKey: liveCityKey),
                  let snap = try? ProgressStats.citySnapshot(modelContext: context, cityKey: key)
            else { return 0 }
            return snap.completion01
        }()

        let cityCategories25: Bool = {
            guard let key = profile?.effectiveProgressCityKey(liveCityKey: liveCityKey),
                  let snap = try? ProgressStats.citySnapshot(modelContext: context, cityKey: key)
            else { return false }
            return DiscoveryCategory.allCases.allSatisfy { (snap.perCategory[$0]?.percent01 ?? 0) >= 0.25 }
        }()

        let visitLike = events.filter { $0.kindRaw == ExplorerEventKind.visit.rawValue || $0.kindRaw == ExplorerEventKind.revisit.rawValue }
        let sortedVisitTimes = visitLike.map(\.occurredAt).sorted()

        var checkinsPerOsm: [String: Int] = [:]
        for e in visitLike {
            checkinsPerOsm[e.osmId, default: 0] += 1
        }
        let placesWithTwoPlusCheckins = checkinsPerOsm.values.filter { $0 >= 2 }.count
        let hasAnyPlaceVisitedTwice = checkinsPerOsm.values.contains { $0 >= 2 }

        var visitsBefore9 = 0
        var visitsAfter8 = 0
        for e in visitLike {
            if BadgeRuleHelpers.isBefore9AM(e.occurredAt, calendar: cal) { visitsBefore9 += 1 }
            if BadgeRuleHelpers.isAtOrAfter8PM(e.occurredAt, calendar: cal) { visitsAfter8 += 1 }
        }

        let outingIntervals = BadgeRuleHelpers.outingIntervals(sortedDates: sortedVisitTimes)
        var maxOutingDistinct = 0
        var maxDayDistinct = 0
        var tripleThreatOutingCount = 0
        var picnicMet = false
        var maxWeekendDistinct = 0

        var weekendStartsVisited = Set<Date>()
        for e in visitLike where BadgeRuleHelpers.isWeekend(e.occurredAt, calendar: cal) {
            weekendStartsVisited.insert(BadgeRuleHelpers.weekendSaturdayStart(containing: e.occurredAt, calendar: cal))
        }

        for interval in outingIntervals {
            let inOuting = visitLike.filter { $0.occurredAt >= interval.start && $0.occurredAt <= interval.end }
            let distinct = Set(inOuting.map(\.osmId))
            maxOutingDistinct = max(maxOutingDistinct, distinct.count)

            var catsInOuting = Set<DiscoveryCategory>()
            var sawOutdoor = false
            var sawFood = false
            for id in distinct {
                guard let poi = poiById[id], let c = DiscoveryCategory(rawValue: poi.categoryRaw) else { continue }
                catsInOuting.insert(c)
                if c == .outdoor { sawOutdoor = true }
                if c == .food { sawFood = true }
            }
            if catsInOuting.contains(.food), catsInOuting.contains(.shopping), catsInOuting.contains(.entertainment) {
                tripleThreatOutingCount += 1
            }
            if sawOutdoor && sawFood { picnicMet = true }
        }

        let daysWithVisits = Dictionary(grouping: visitLike) { cal.startOfDay(for: $0.occurredAt) }
        for (_, dayEvents) in daysWithVisits {
            let d = Set(dayEvents.map(\.osmId)).count
            maxDayDistinct = max(maxDayDistinct, d)
        }

        for ws in weekendStartsVisited {
            let wk = visitLike.filter {
                BadgeRuleHelpers.isWeekend($0.occurredAt, calendar: cal)
                    && BadgeRuleHelpers.weekendSaturdayStart(containing: $0.occurredAt, calendar: cal) == ws
            }
            maxWeekendDistinct = max(maxWeekendDistinct, Set(wk.map(\.osmId)).count)
        }

        var natureBreakSameDay = false
        var dessertDashSameDay = false
        var dateNightMet = false
        for (_, dayEvents) in daysWithVisits {
            let ids = Set(dayEvents.map(\.osmId))
            var sawOutdoor = false
            var sawCafe = false
            var dessertCount = 0
            var sawFoodNight = false
            var sawEntNight = false
            for oid in ids {
                guard let poi = poiById[oid] else { continue }
                let cat = DiscoveryCategory(rawValue: poi.categoryRaw)
                if cat == .outdoor { sawOutdoor = true }
                if PlaceHeuristic.isCafe(name: poi.name, category: cat) { sawCafe = true }
                if PlaceHeuristic.isDessert(name: poi.name, category: cat) { dessertCount += 1 }
            }
            if sawOutdoor && sawCafe { natureBreakSameDay = true }
            if dessertCount >= 2 { dessertDashSameDay = true }

            for ev in dayEvents where BadgeRuleHelpers.isAtOrAfter8PM(ev.occurredAt, calendar: cal) {
                guard let poi = poiById[ev.osmId], let cat = DiscoveryCategory(rawValue: poi.categoryRaw) else { continue }
                if cat == .food { sawFoodNight = true }
                if cat == .entertainment { sawEntNight = true }
            }
            if sawFoodNight && sawEntNight { dateNightMet = true }
        }

        let savedIds = Set(savedPlaces.map(\.osmId))
        let discoveredIds = Set(discoveries.map(\.osmId))
        let treasureIntersect = savedIds.intersection(discoveredIds).count

        var curiosityMet = false
        for d in discoveries {
            guard let sp = savedPlaces.first(where: { $0.osmId == d.osmId }) else { continue }
            if let weekLater = cal.date(byAdding: .day, value: 7, to: sp.savedAt), d.discoveredAt >= weekLater {
                curiosityMet = true
                break
            }
        }

        let hiddenGemDiscoveries = discoveries.filter {
            guard let poi = poiById[$0.osmId] else { return false }
            return DiscoveryCategory(rawValue: poi.categoryRaw) == .hiddenGems
        }
        let hasHiddenGemVisit = !hiddenGemDiscoveries.isEmpty
        let hiddenAlley = hasHiddenGemVisit && savedIds.count >= 1
        let distinctHiddenGemPlaces = Set(hiddenGemDiscoveries.map(\.osmId)).count

        let trailMix = (categoryCounts[.outdoor] ?? 0) >= 1 && (categoryCounts[.hiddenGems] ?? 0) >= 1

        let heuristicCounts = HeuristicDistinctCounts.compute(discoveries: discoveries, poiById: poiById)

        let partnerDistinct = Set(
            discoveries.compactMap { poiById[$0.osmId] }.filter(\.isPartner).map(\.osmId)
        ).count

        var downtownPlacesVisitedDistinct = 0
        var neighborhoodSectorsVisitedDistinct = 0
        var fullyCompletedNeighborhoodCount = 0
        var curatedTrailsCompletedCount = 0
        var neighborhoodHeroMet = false

        if let cityKey = profile?.effectiveProgressCityKey(liveCityKey: liveCityKey) {
            let localPredicate = #Predicate<CachedPOI> { $0.cityKey == cityKey && $0.isChain == false }
            let locals = (try? context.fetch(FetchDescriptor<CachedPOI>(predicate: localPredicate))) ?? []
            let cachedCityIds = Set(locals.map(\.osmId))
            let discoveredCityIds = Set(discoveries.filter { $0.cityKey == cityKey }.map(\.osmId))

            let centroid = NeighborhoodGeography.centroid(of: locals)
            var downtownIds = Set<String>()
            var sectorKeys = Set<String>()
            for osm in discoveredCityIds {
                guard let poi = poiById[osm], poi.cityKey == cityKey, !poi.isChain else { continue }
                sectorKeys.insert(NeighborhoodGeography.gridKey(latitude: poi.latitude, longitude: poi.longitude))
                if let c = centroid, NeighborhoodGeography.isDowntownPOI(poi, centroid: c) {
                    downtownIds.insert(osm)
                }
            }
            downtownPlacesVisitedDistinct = downtownIds.count
            neighborhoodSectorsVisitedDistinct = sectorKeys.count

            let localsByCell = Dictionary(grouping: locals) {
                NeighborhoodGeography.gridKey(latitude: $0.latitude, longitude: $0.longitude)
            }
            var fullCount = 0
            for (_, bucket) in localsByCell {
                let ids = bucket.map(\.osmId)
                guard ids.count >= 3 else { continue }
                if ids.allSatisfy({ discoveredCityIds.contains($0) }) { fullCount += 1 }
            }
            fullyCompletedNeighborhoodCount = fullCount

            for (_, bucket) in localsByCell {
                let ids = bucket.map(\.osmId)
                guard ids.count >= 8 else { continue }
                let disc = ids.filter { discoveredCityIds.contains($0) }.count
                guard Double(disc) / Double(ids.count) >= 0.75 else { continue }
                let revisitRich = ids.filter { (checkinsPerOsm[$0] ?? 0) >= 2 }.count
                if revisitRich >= 5 {
                    neighborhoodHeroMet = true
                    break
                }
            }

            let trailCatalog = CuratedTrailCatalog.load(from: .main)
            let mergedTrails = trailCatalog.mergedTrails(locals: locals)
            curatedTrailsCompletedCount = mergedTrails.filter {
                $0.isComplete(discoveredOsmIds: discoveredCityIds, cachedOsmIds: cachedCityIds)
            }.count
        }

        let distinctPhotoPlaces = Set(photoCheckIns.map(\.osmId)).count
        let distinctCitiesWithDiscoveries = Set(discoveries.map(\.cityKey)).count

        let homeState = profile?.homeCityKey.flatMap { CityKey.stateOrRegion(fromCityKey: $0) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        var hasVisitedOutsideHomeState = false
        if let hs = homeState, !hs.isEmpty {
            for d in discoveries {
                guard let vs = CityKey.stateOrRegion(fromCityKey: d.cityKey)
                    .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }), !vs.isEmpty else { continue }
                if vs.caseInsensitiveCompare(hs) != .orderedSame {
                    hasVisitedOutsideHomeState = true
                    break
                }
            }
        }

        let pantherEntry = partners.partners.first { entry in
            let t = entry.displayTitle.lowercased()
            return t.contains("agora") && (t.contains("gift") || t.contains("chapman"))
        }
        var hasVisitedPantherPridePlace = false
        if let pe = pantherEntry {
            for d in discoveries {
                guard let poi = poiById[d.osmId] else { continue }
                if let matched = partners.matchPartnerPOI(name: poi.name, osmId: poi.osmId), matched.osmId == pe.osmId {
                    hasVisitedPantherPridePlace = true
                    break
                }
                if pe.matchesListing(name: poi.name) {
                    hasVisitedPantherPridePlace = true
                    break
                }
            }
        }

        return BadgeProgressSnapshot(
            totalVisits: discoveries.count,
            nonChainVisits: nonChain,
            stamps: stamps.count,
            level: LevelFormula.level(for: profile?.totalXP ?? 0),
            categoryCounts: categoryCounts,
            cityCompletion01: cityCompletion01,
            cityCategories25: cityCategories25,
            unlockedCount: unlockedCount,
            homeCityVisits: homeCityVisits,
            savedPlaceCount: savedPlaces.count,
            favoritedPlaceCount: favorites.count,
            maxPlacesSingleOuting: maxOutingDistinct,
            maxPlacesSingleDay: maxDayDistinct,
            maxPlacesSingleWeekend: maxWeekendDistinct,
            distinctWeekendsWithVisit: weekendStartsVisited.count,
            visitsBefore9AM: visitsBefore9,
            visitsAfter8PM: visitsAfter8,
            hadRainyVisit: false,
            placesWithTwoPlusCheckins: placesWithTwoPlusCheckins,
            hasAnyPlaceVisitedTwice: hasAnyPlaceVisitedTwice,
            treasureSavedVisitedIntersect: treasureIntersect,
            curiosityLongSaveVisit: curiosityMet,
            hiddenAlley: hiddenAlley,
            distinctHiddenGemPlaces: distinctHiddenGemPlaces,
            natureBreakSameDay: natureBreakSameDay,
            picnicOuting: picnicMet,
            dateNightSameDay: dateNightMet,
            dessertDashSameDay: dessertDashSameDay,
            trailMix: trailMix,
            tripleThreatOutingCount: tripleThreatOutingCount,
            partnerLocationsVisitedDistinct: partnerDistinct,
            coffeeDistinct: heuristicCounts.coffee,
            teaBobaDistinct: heuristicCounts.teaBoba,
            dessertDistinct: heuristicCounts.dessert,
            tacoDistinct: heuristicCounts.taco,
            pizzaDistinct: heuristicCounts.pizza,
            burgerDistinct: heuristicCounts.burger,
            brunchDistinct: heuristicCounts.brunch,
            bookstoreDistinct: heuristicCounts.bookstore,
            galleryDistinct: heuristicCounts.gallery,
            gardenDistinct: heuristicCounts.garden,
            recordDistinct: heuristicCounts.record,
            trailDistinct: heuristicCounts.trail,
            libraryDistinct: heuristicCounts.library,
            communityDistinct: heuristicCounts.community,
            farmersMarketDistinct: heuristicCounts.farmersMarket,
            placesWithJournalNote: discoveries.filter { ($0.explorerNote ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }.count,
            downtownPlacesVisitedDistinct: downtownPlacesVisitedDistinct,
            neighborhoodSectorsVisitedDistinct: neighborhoodSectorsVisitedDistinct,
            fullyCompletedNeighborhoodCount: fullyCompletedNeighborhoodCount,
            curatedTrailsCompletedCount: curatedTrailsCompletedCount,
            distinctPlacesWithPhotoCheckIn: distinctPhotoPlaces,
            neighborhoodHeroMet: neighborhoodHeroMet,
            distinctCitiesWithDiscoveries: distinctCitiesWithDiscoveries,
            badgesScreenVisitCount: profile?.badgesScreenVisitCount ?? 0,
            onboardingComplete: profile?.onboardingComplete ?? false,
            hasVisitedOutsideHomeState: hasVisitedOutsideHomeState,
            hasVisitedPantherPridePlace: hasVisitedPantherPridePlace
        )
    }
}

// MARK: - Name heuristics (food subtypes & POI flavor)

private enum PlaceHeuristic {
    static func norm(_ name: String) -> String {
        name.lowercased()
    }

    static func isCafe(name: String, category: DiscoveryCategory?) -> Bool {
        guard category == .food else { return false }
        let n = norm(name)
        return n.contains("cafe") || n.contains("coffee") || n.contains("espresso")
    }

    static func isDessert(name: String, category: DiscoveryCategory?) -> Bool {
        guard category == .food else { return false }
        let n = norm(name)
        return n.contains("dessert") || n.contains("ice cream") || n.contains("bakery")
            || n.contains("sweet") || n.contains("cake") || n.contains("donut") || n.contains("pastry")
    }
}

private struct HeuristicDistinctCounts {
    var coffee = 0
    var teaBoba = 0
    var dessert = 0
    var taco = 0
    var pizza = 0
    var burger = 0
    var brunch = 0
    var bookstore = 0
    var gallery = 0
    var garden = 0
    var record = 0
    var trail = 0
    var library = 0
    var community = 0
    var farmersMarket = 0

    static func compute(discoveries: [DiscoveredPlace], poiById: [String: CachedPOI]) -> HeuristicDistinctCounts {
        var c = HeuristicDistinctCounts()
        for d in discoveries {
            guard let poi = poiById[d.osmId] else { continue }
            let name = poi.name
            let n = PlaceHeuristic.norm(name)
            let cat = DiscoveryCategory(rawValue: poi.categoryRaw)

            if cat == .food {
                if n.contains("boba") || n.contains("bubble tea") || n.contains("milk tea") || n.contains("tea house") || n.contains("teahouse") {
                    c.teaBoba += 1
                } else if n.contains("coffee") || n.contains("cafe") || n.contains("espresso") || n.contains("roaster") {
                    c.coffee += 1
                }
                if PlaceHeuristic.isDessert(name: name, category: cat) { c.dessert += 1 }
                if n.contains("taco") { c.taco += 1 }
                if n.contains("pizza") { c.pizza += 1 }
                if n.contains("burger") { c.burger += 1 }
                if n.contains("brunch") { c.brunch += 1 }
            }
            if n.contains("book") && (n.contains("store") || n.contains("shop") || n.contains("books")) {
                c.bookstore += 1
            }
            if n.contains("gallery") || n.contains("mural") || n.contains("art museum") {
                c.gallery += 1
            }
            if n.contains("garden") || n.contains("nursery") || n.contains("plant") {
                c.garden += 1
            }
            if n.contains("record") || n.contains("vinyl") {
                c.record += 1
            }
            if cat == .outdoor, n.contains("trail") || n.contains("hike") {
                c.trail += 1
            }
            if n.contains("library") {
                c.library += 1
            }
            if (n.contains("community") && (n.contains("center") || n.contains("centre"))) || n.contains("event space") {
                c.community += 1
            }
            if n.contains("farmer") && n.contains("market") {
                c.farmersMarket += 1
            }
        }
        return c
    }
}
