//
//  MapVoicePlaceAssistant.swift
//  Venture Local
//
//  Speech-to-text + lightweight on-device parsing to rank cached POIs by
//  text match and distance from the user (or map center fallback).
//

import AVFoundation
import Combine
import CoreLocation
import Foundation
import NaturalLanguage
import Speech

// MARK: - Ranking

struct MapVoiceRankedPlace: Identifiable {
    var id: String { poi.osmId }
    let poi: CachedPOI
    /// Combined score in roughly 0...1 (higher is better).
    let combinedScore: Double
    let textScore: Double
    let distanceScore: Double
    let distanceMeters: Double
}

enum MapVoicePlaceRanker {
    private static let stopwords: Set<String> = [
        "a", "an", "the", "to", "i", "me", "my", "we", "us", "you", "it",
        "is", "are", "was", "be", "been", "being", "have", "has", "had",
        "do", "does", "did", "will", "would", "could", "should", "may",
        "and", "or", "but", "if", "of", "at", "by", "for", "with", "about",
        "into", "through", "from", "up", "down", "in", "out", "on", "off",
        "over", "under", "again", "then", "once", "here", "there", "when",
        "where", "why", "how", "all", "each", "every", "both", "few",
        "more", "most", "other", "some", "such", "no", "nor", "not",
        "only", "own", "same", "so", "than", "too", "very", "just",
        "want", "wanna", "gonna", "get", "go", "find", "show", "give",
        "can", "any", "isnt", "isn't",
        "place", "places", "spot", "somewhere", "something", "near", "nearby",
        "close", "best", "good", "nice", "please", "hey", "uh", "um",
        "place", "nearest", "closest",
    ]

    private static let categoryKeywords: [DiscoveryCategory: [String]] = [
        .food: [
            "coffee", "cafe", "espresso", "latte", "cappuccino", "mocha", "frappuccino",
            "barista", "roaster", "roastery", "eat", "food", "restaurant", "diner", "dining",
            "eatery", "bistro", "meal", "hungry",
            "sushi", "pizza", "pizzeria", "burger", "taco", "bbq", "barbecue", "ramen", "noodle",
            "bar", "pub", "brewery", "winery", "bakery", "brunch", "breakfast", "lunch", "dinner", "supper",
            "ice", "cream", "donut", "doughnut", "sandwich", "deli", "steak", "seafood",
            "vegan", "vegetarian", "thai", "italian", "mexican", "chinese", "japanese", "korean",
        ],
        /// Avoid bare "shop" here — it fires on "coffee shop" and steers to retail; see `retailShopKeywords`.
        .shopping: [
            "shopping", "store", "mall", "boutique", "market", "buy", "retail",
            "clothes", "clothing", "shoes", "book", "books", "gift", "gifts", "thrift",
        ],
        .outdoor: [
            "park", "parks", "hike", "hiking", "trail", "trails", "nature", "garden",
            "outdoor", "outside", "walk", "walking", "playground", "field", "lake", "beach",
        ],
        .entertainment: [
            "movie", "movies", "cinema", "theater", "theatre", "fun", "arcade", "bowling",
            "museum", "gallery", "concert", "music", "club", "nightlife", "game", "games",
            "mini", "golf", "miniature", "putt", "laser", "tag", "escape", "zoo", "aquarium",
            "entertainment", "amusement", "venue", "miniature_golf", "bowling_alley",
        ],
        .hiddenGems: [
            "hidden", "gem", "gems", "secret", "unique", "local", "special", "quirky",
            "off", "beaten", "path", "underrated", "unknown",
            "church", "churches", "chapel", "cathedral", "worship", "parish", "ministry",
            "temple", "mosque", "synagogue", "congregation", "faith", "religious",
        ],
    ]

    /// Avoid `kw.contains(tok)` for short tokens (e.g. "can" inside "mexican").
    private static func tokenMatchesCategoryKeyword(_ tok: String, kw: String) -> Bool {
        if tok == kw { return true }
        if tok.contains(kw) { return true }
        if tok.count >= 4, kw.contains(tok) { return true }
        return false
    }

    static func meaningfulTokens(from text: String) -> [String] {
        let lowered = text.lowercased()
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = lowered
        var tokens: [String] = []
        tokenizer.enumerateTokens(in: lowered.startIndex..<lowered.endIndex) { range, _ in
            let t = String(lowered[range])
            guard t.count >= 2, !stopwords.contains(t) else { return true }
            tokens.append(t)
            return true
        }
        return tokens
    }

    /// Phrase → extra tokens aligned with OSM tags and category hints (cheap; no network).
    private static func expansionTokens(for loweredFull: String) -> [String] {
        let f = loweredFull
        var extra: [String] = []

        if f.contains("dinner") || f.contains("supper") || f.contains("evening meal") {
            extra += ["restaurant", "dining", "food", "eatery"]
        }
        if f.contains("lunch") {
            extra += ["restaurant", "food", "cafe", "diner"]
        }
        if f.contains("breakfast") || f.contains("morning meal") {
            extra += ["restaurant", "cafe", "bakery", "brunch", "food"]
        }
        if f.contains("brunch") {
            extra += ["brunch", "restaurant", "cafe", "food"]
        }
        if f.contains("hungry") || f.contains("something to eat") || f.contains("get food")
            || f.contains("grab a bite") || f.contains("place to eat") {
            extra += ["restaurant", "food", "dining", "eat"]
        }

        if f.contains("mini golf") || f.contains("mini-golf") || f.contains("minigolf")
            || f.contains("miniature golf") || f.contains("putt putt") || f.contains("putt-putt")
            || f.contains("puttputt") {
            extra += ["miniature", "golf", "miniature_golf", "putt", "entertainment"]
        }
        if f.contains("laser tag") {
            extra += ["laser", "arcade", "entertainment", "fun"]
        }
        if f.contains("bowling") {
            // Omit "alley" — it matches street names and unrelated POIs.
            extra += ["bowling", "entertainment", "bowling_alley"]
        }
        if f.contains("arcade") || f.contains("video games") || f.contains("video game") {
            extra += ["arcade", "amusement", "entertainment", "games"]
        }
        if f.contains("escape room") || f.contains("escape game") {
            extra += ["escape", "entertainment", "fun"]
        }
        if f.contains("go karts") || f.contains("go-karts") || f.contains("gokarts") {
            extra += ["entertainment", "fun", "amusement"]
        }
        if f.contains("zoo") {
            extra += ["zoo", "aquarium", "animals", "entertainment"]
        }
        if f.contains("museum") {
            extra += ["museum", "gallery", "entertainment"]
        }
        if f.contains("taco") || f.contains("tacos") || f.contains("taqueria") {
            extra += ["mexican", "restaurant"]
        }
        if f.contains("church") || f.contains("churches") || f.contains("chapel") || f.contains("cathedral")
            || f.contains("mosque") || f.contains("synagogue") || f.contains("temple") || f.contains("worship") {
            extra += ["church", "chapel", "worship", "place_of_worship"]
        }

        return extra
    }

    /// NL tokens plus phrase-expanded synonyms (deduped, order preserved).
    private static func tokensForRanking(from text: String) -> [String] {
        let lowered = text.lowercased()
        var base = meaningfulTokens(from: text)
        var seen = Set(base)
        for t in expansionTokens(for: lowered) {
            guard t.count >= 2, !stopwords.contains(t) else { continue }
            if seen.insert(t).inserted {
                base.append(t)
            }
        }
        return base
    }

    private static func coffeeOrCafeIntent(_ full: String) -> Bool {
        let f = full.lowercased()
        let needles = [
            "coffee", "cafe", "café", "espresso", "latte", "cappuccino", "mocha",
            "frappuccino", "barista", "starbucks",
        ]
        return needles.contains { f.contains($0) }
    }

    /// Food / cuisine wording: "taco shop" is about tacos, not retail "shop".
    private static let foodVenueNeedles: [String] = [
        "taco", "tacos", "burrito", "burritos", "taqueria", "quesadilla", "mexican",
        "pizza", "burger", "burgers", "sushi", "ramen", "pho", "bbq", "barbecue",
        "deli", "sandwich", "bakery", "donut", "doughnut", "gyro", "kebab",
        "seafood", "steak", "wings", "nacho", "nachos", "falafel", "hot dog", "hotdog",
        "thai", "korean", "chinese", "japanese", "indian", "vietnamese", "teriyaki",
        "brunch", "breakfast", "lunch", "dinner", "supper", "eatery", "diner", "bistro",
        "hungry", "something to eat", "place to eat", "grab a bite",
    ]

    private static func foodVenueIntent(_ full: String) -> Bool {
        let f = full.lowercased()
        return foodVenueNeedles.contains { f.contains($0) }
    }

    /// When true, `shop` / `shops` are not used for matching or retail category hints.
    private static func shouldIgnoreShopTokensInQuery(_ full: String) -> Bool {
        let f = full.lowercased()
        if coffeeOrCafeIntent(f) { return true }
        if foodVenueIntent(f) { return true }
        if f.contains("tea shop") || f.contains("bubble tea") || f.contains("boba") { return true }
        if f.contains("ice cream") || f.contains("juice bar") { return true }
        return false
    }

    /// "shop" counts toward retail hints only for plain shopping-style queries.
    private static func treatShopTokenAsRetailShopping(_ full: String) -> Bool {
        !shouldIgnoreShopTokensInQuery(full)
    }

    private static func pizzaIntent(_ full: String) -> Bool {
        let f = full.lowercased()
        return f.contains("pizza") || f.contains("pizzeria")
    }

    private static func burgerIntent(_ full: String) -> Bool {
        let f = full.lowercased()
        return f.contains("burger") || f.contains("burgers") || f.contains("hamburger") || f.contains("cheeseburger")
    }

    private static func tacoIntent(_ full: String) -> Bool {
        let f = full.lowercased()
        return f.contains("taco") || f.contains("tacos") || f.contains("taqueria") || f.contains("burrito") || f.contains("burritos")
    }

    private static func sushiIntent(_ full: String) -> Bool {
        let f = full.lowercased()
        return f.contains("sushi") || f.contains("sashimi") || f.contains("ramen") && f.contains("japanese")
    }

    /// Matches "shop" / "shops" as their own words (not "barbershop", "workshop", …).
    private static let standaloneShopRegex = try? NSRegularExpression(pattern: #"\bshops?\b"#, options: [.caseInsensitive])

    private static func textHasStandaloneShopWord(_ text: String) -> Bool {
        guard let re = standaloneShopRegex else { return text.contains("shop") }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return re.firstMatch(in: text, options: [], range: range) != nil
    }

    private static func tokenMatchesInLowercasedText(_ haystack: String, token: String, fullText: String) -> Bool {
        if shouldIgnoreShopTokensInQuery(fullText), token == "shop" || token == "shops" { return false }
        if token == "shop" || token == "shops" { return textHasStandaloneShopWord(haystack) }
        return haystack.contains(token)
    }

    private static func nameSuggestsPizza(_ name: String) -> Bool {
        let n = name.lowercased()
        if n.contains("pizza") || n.contains("pizzeria") { return true }
        if n.contains("domino") || n.contains("little caesar") || n.contains("papa john") { return true }
        if n.contains("blaze pizza") || n.contains("round table") { return true }
        return false
    }

    private static func nameSuggestsCoffeeOrCafe(_ name: String) -> Bool {
        let n = name.lowercased()
        let markers = [
            "coffee", "cafe", "café", "espresso", "latte", "starbucks", "peet",
            "dutch bros", "barista", "roaster", "roastery",
        ]
        return markers.contains { n.contains($0) }
    }

    private static func bowlingIntent(_ full: String) -> Bool {
        full.lowercased().contains("bowling")
    }

    private static func nameSuggestsBowling(_ name: String) -> Bool {
        let n = name.lowercased()
        let markers = [
            "bowling", "bowl-a-rama", "bowlarama", "tenpin", "ten pin", "ten-pin",
            "amf bowling", "brunswick zone",
        ]
        if markers.contains(where: { n.contains($0) }) { return true }
        if n.contains("bowling alley") || n.contains("bowling lanes") || n.contains("bowling lane")
            || n.contains("bowling center") || n.contains("bowling centre") { return true }
        return n.contains("lanes") && n.contains("bowl")
    }

    private static func poiSignalsBowlingFromMetadata(_ poi: CachedPOI) -> Bool {
        guard let meta = POIExtendedMetadataCodec.decode(poi.extendedMetadataJSON) else { return false }
        if let tags = meta.osmTags, tags["leisure"] == "bowling_alley" { return true }
        if let mk = meta.mapKit, mk.pointOfInterestCategoryDescription.lowercased().contains("bowling") { return true }
        return false
    }

    private static func worshipIntent(_ full: String) -> Bool {
        let f = full.lowercased()
        return [
            "church", "churches", "chapel", "cathedral", "mosque", "synagogue",
            "worship", "parish", "pastor", "sermon", "temple",
        ].contains { f.contains($0) }
    }

    private static func nameSuggestsWorship(_ name: String) -> Bool {
        let n = name.lowercased()
        if n.contains("temple"), ["thai", "sushi", "vietnamese", "cafe", "coffee"].contains(where: { n.contains($0) }) {
            return false
        }
        return [
            "church", "chapel", "cathedral", "mosque", "synagogue", "temple",
            "parish", "ministry", "worship center", "worship centre", "latter-day",
            "baptist", "methodist", "presbyterian", "catholic", "episcopal",
            "lutheran", "pentecostal", "orthodox church", "kingdom hall",
        ].contains { n.contains($0) }
    }

    private static func poiSignalsWorshipFromMetadata(_ poi: CachedPOI) -> Bool {
        guard let meta = POIExtendedMetadataCodec.decode(poi.extendedMetadataJSON) else { return false }
        if let tags = meta.osmTags, tags["amenity"] == "place_of_worship" { return true }
        if let mk = meta.mapKit {
            let b = mk.pointOfInterestCategoryDescription.lowercased()
            if b.contains("worship") || b.contains("church") || b.contains("mosque") || b.contains("synagogue") {
                return true
            }
        }
        return false
    }

    /// Keyword overlap → implied category weights (0…n).
    private static func categoryHints(for tokens: [String], fullText: String) -> [DiscoveryCategory: Double] {
        var scores: [DiscoveryCategory: Double] = [:]
        for (category, keywords) in categoryKeywords {
            var s = 0.0
            for kw in keywords {
                for tok in tokens where tokenMatchesCategoryKeyword(tok, kw: kw) {
                    s += 1
                }
            }
            if s > 0 { scores[category] = s }
        }
        if treatShopTokenAsRetailShopping(fullText) {
            for tok in tokens where tok == "shop" || tok == "shops" {
                scores[.shopping, default: 0] += 1.25
            }
        }
        return scores
    }

    private static func textMatchScore(
        poi: CachedPOI,
        tokens: [String],
        categoryHints: [DiscoveryCategory: Double],
        fullText: String
    ) -> Double {
        let name = poi.name.lowercased()
        var score = 0.0
        for tok in tokens {
            if tokenMatchesInLowercasedText(name, token: tok, fullText: fullText) {
                score += 4.5
            }
        }
        if let cat = DiscoveryCategory(rawValue: poi.categoryRaw), let hint = categoryHints[cat] {
            score += hint * 2.2
        }
        if let addr = poi.addressSummary?.lowercased() {
            for tok in tokens where tok.count >= 3 {
                if tokenMatchesInLowercasedText(addr, token: tok, fullText: fullText) { score += 1.2 }
            }
        }
        return score
    }

    /// OSM tag slice + stored MapKit category string vs query tokens (and light cuisine/category heuristics).
    private static func osmAndMapKitMatchScore(poi: CachedPOI, tokens: [String], fullText: String) -> Double {
        guard let meta = POIExtendedMetadataCodec.decode(poi.extendedMetadataJSON) else { return 0 }
        var score = 0.0
        let f = fullText.lowercased()

        if let tags = meta.osmTags, !tags.isEmpty {
            let flat = tags.map { "\($0.key)=\($0.value)" }.joined(separator: " ").lowercased()
            for tok in tokens where tok.count >= 2 {
                if shouldIgnoreShopTokensInQuery(f), tok == "shop" || tok == "shops" { continue }
                if tok == "shop" || tok == "shops" {
                    if textHasStandaloneShopWord(flat) { score += 3.4 }
                } else if flat.contains(tok) {
                    score += 3.4
                }
            }
            for (_, v) in tags {
                let parts = v.split(separator: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty }
                for part in parts {
                    for tok in tokens where tok.count >= 2 {
                        if shouldIgnoreShopTokensInQuery(f), tok == "shop" || tok == "shops" { continue }
                        if tok == "shop" || tok == "shops" {
                            if textHasStandaloneShopWord(part) { score += 4.2 }
                        } else if part.contains(tok) || tok.contains(part) {
                            score += 4.2
                        }
                    }
                }
            }
            if pizzaIntent(f), let c = tags["cuisine"], c.contains("pizza") { score += 8 }
            if burgerIntent(f), let c = tags["cuisine"], c.contains("burger") || c.contains("hamburger") { score += 8 }
            if tacoIntent(f), let c = tags["cuisine"], c.contains("taco") || c.contains("tex-mex") || c.contains("tex_mex") {
                score += 8
            }
            if sushiIntent(f), let c = tags["cuisine"], c.contains("sushi") { score += 6 }
            if coffeeOrCafeIntent(f) {
                if let c = tags["cuisine"], ["coffee_shop", "coffee", "cafe", "espresso"].contains(where: { c.contains($0) }) { score += 7 }
                if tags["amenity"] == "cafe" { score += 6 }
            }
            if bowlingIntent(f), tags["leisure"] == "bowling_alley" { score += 9 }
            if worshipIntent(f), tags["amenity"] == "place_of_worship" { score += 9 }
        }

        if let mk = meta.mapKit {
            let blob = mk.pointOfInterestCategoryDescription.lowercased()
            for tok in tokens where tok.count > 2 {
                if shouldIgnoreShopTokensInQuery(f), tok == "shop" || tok == "shops" { continue }
                if blob.contains(tok) { score += 2 }
            }
            if blob.contains("restaurant") || blob.contains("cafe") || blob.contains("bakery") || blob.contains("brewery") {
                let foodLoose = ["food", "eat", "restaurant", "coffee", "cafe", "pizza", "burger", "taco", "sushi", "lunch", "dinner", "brunch"]
                    .contains(where: { f.contains($0) })
                if foodLoose {
                    let flavors = PlaceExploreFlavorTags.kinds(for: poi)
                    if burgerIntent(f) {
                        if flavors.contains(.burger) { score += 2.5 }
                    } else if tacoIntent(f) {
                        if flavors.contains(.taco) { score += 2.5 }
                    } else if sushiIntent(f) {
                        if flavors.contains(.sushi) { score += 2.5 }
                    } else if pizzaIntent(f) {
                        if nameSuggestsPizza(poi.name) { score += 2.5 }
                    } else if coffeeOrCafeIntent(f) {
                        if nameSuggestsCoffeeOrCafe(poi.name) { score += 2.5 }
                    } else {
                        score += 2.5
                    }
                }
            }
            if blob.contains("park") || blob.contains("nationalpark") || blob.contains("beach") {
                if ["park", "hike", "trail", "nature", "outdoor"].contains(where: { f.contains($0) }) {
                    score += 2.5
                }
            }
            if bowlingIntent(f), blob.contains("bowling") { score += 3 }
            if worshipIntent(f), blob.contains("worship") || blob.contains("church") || blob.contains("mosque")
                || blob.contains("synagogue") {
                score += 3
            }
        }

        return score
    }

    /// After base lexical + category score, down-rank wrong venue types for specific intents.
    private static func applyIntentRefinements(
        baseScore: Double,
        poi: CachedPOI,
        fullText: String
    ) -> Double {
        var s = baseScore
        let cat = DiscoveryCategory(rawValue: poi.categoryRaw)

        if pizzaIntent(fullText) {
            if cat == .food {
                if nameSuggestsPizza(poi.name) {
                    s += 14
                } else {
                    s *= 0.18
                }
            } else if nameSuggestsPizza(poi.name) {
                s += 6
            } else {
                s *= 0.25
            }
        }

        if coffeeOrCafeIntent(fullText) {
            if cat == .food {
                if nameSuggestsCoffeeOrCafe(poi.name) {
                    s += 10
                } else {
                    s *= 0.32
                }
            } else if cat == .shopping {
                s *= 0.12
            }
        }

        if burgerIntent(fullText) {
            let hit = PlaceExploreFlavorTags.kinds(for: poi).contains(.burger)
            if hit {
                s += 14
            } else if cat == .food {
                s *= 0.09
            } else {
                s *= 0.22
            }
        }

        if tacoIntent(fullText) {
            let hit = PlaceExploreFlavorTags.kinds(for: poi).contains(.taco)
            if hit {
                s += 14
            } else if cat == .food {
                s *= 0.1
            } else {
                s *= 0.22
            }
        }

        if sushiIntent(fullText) {
            let hit = PlaceExploreFlavorTags.kinds(for: poi).contains(.sushi)
            if hit {
                s += 14
            } else if cat == .food {
                s *= 0.1
            } else {
                s *= 0.22
            }
        }

        if bowlingIntent(fullText) {
            let hit = nameSuggestsBowling(poi.name) || poiSignalsBowlingFromMetadata(poi)
            if hit {
                s += 14
            } else {
                s *= 0.12
            }
        }

        if worshipIntent(fullText) {
            let hit = nameSuggestsWorship(poi.name) || poiSignalsWorshipFromMetadata(poi)
            if hit {
                if cat == .hiddenGems { s += 16 }
                else { s += 7 }
            } else if cat == .food {
                s *= 0.06
            } else {
                s *= 0.18
            }
        }

        return s
    }

    /// Voice search never considers POIs farther than this from the reference point.
    private static let maxVoiceSearchMiles: Double = 40
    private static var maxVoiceSearchMeters: Double { maxVoiceSearchMiles * 1609.34 }

    private static func distanceScore(meters: Double) -> Double {
        let characteristicMeters = 450.0
        return 1.0 / (1.0 + meters / characteristicMeters)
    }

    /// Proximity within the 40 mi cap (for tie-breaking, not to surface irrelevant POIs).
    private static func distanceScoreCapped(meters: Double) -> Double {
        let cap = maxVoiceSearchMeters
        let clamped = min(max(0, meters), cap)
        return 1.0 - (clamped / cap)
    }

    /// Picks out a user-requested radius like "3 miles away" / "about 5 km" → meters (clamped to search cap).
    static func parseRequestedDistanceMeters(in fullText: String) -> Double? {
        let s = fullText.lowercased()
        let ns = s as NSString
        let milePattern = "(\\d+(?:\\.\\d+)?)\\s*(?:miles?|mi)\\b"
        let kmPattern = "(\\d+(?:\\.\\d+)?)\\s*(?:kilometers?|kms?|km)\\b"
        if let re = try? NSRegularExpression(pattern: milePattern, options: []),
           let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)),
           m.numberOfRanges > 1,
           let r = Range(m.range(at: 1), in: s),
           let v = Double(s[r]), v > 0, v < 500 {
            return min(v * 1609.34, maxVoiceSearchMeters)
        }
        if let re = try? NSRegularExpression(pattern: kmPattern, options: []),
           let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)),
           m.numberOfRanges > 1,
           let r = Range(m.range(at: 1), in: s),
           let v = Double(s[r]), v > 0, v < 800 {
            return min(v * 1000, maxVoiceSearchMeters)
        }
        return nil
    }

    /// ~3–6 mi window for a 5 mi ask: plateau between ~62% and ~122% of target, soft decay outside.
    private static func targetDistanceBandFit(meters: Double, targetMeters: Double) -> Double {
        let cap = maxVoiceSearchMeters
        let tgt = min(targetMeters, cap)
        guard tgt >= 200 else { return distanceScoreCapped(meters: meters) }
        let low = max(250, tgt * 0.62)
        let high = min(cap, tgt * 1.22)
        guard high > low + 50 else { return distanceScoreCapped(meters: meters) }
        if meters >= low, meters <= high {
            return 1
        }
        let distOutside: Double
        if meters < low {
            distOutside = low - meters
        } else {
            distOutside = meters - high
        }
        let decayLen = max(180, tgt * 0.11)
        return exp(-distOutside / decayLen)
    }

    /// Slightly wider band if the tight window has no good matches after filtering.
    private static func targetDistanceBandWide(meters: Double, targetMeters: Double) -> Bool {
        let cap = maxVoiceSearchMeters
        let tgt = min(targetMeters, cap)
        guard tgt >= 200 else { return true }
        let low = max(200, tgt * 0.48)
        let high = min(cap, tgt * 1.38)
        return meters >= low && meters <= high
    }

    private static func hasSpecificPlaceIntent(tokens: [String], hints: [DiscoveryCategory: Double], fullText: String) -> Bool {
        if !tokens.isEmpty { return true }
        if !hints.isEmpty { return true }
        if pizzaIntent(fullText) || coffeeOrCafeIntent(fullText) || foodVenueIntent(fullText) { return true }
        if burgerIntent(fullText) || tacoIntent(fullText) || sushiIntent(fullText) { return true }
        if bowlingIntent(fullText) || worshipIntent(fullText) { return true }
        if !expansionTokens(for: fullText.lowercased()).isEmpty { return true }
        return false
    }

    /// Stops “very close but irrelevant” POIs from riding distance to the top.
    private static func relevanceGate(textScore: Double, maxTextScore: Double) -> Double {
        guard maxTextScore > 0.5 else { return 1 }
        let floor = max(1.25, maxTextScore * 0.28)
        let linear = min(1, textScore / floor)
        return linear * linear
    }

    private static func minimumRelevanceScore(maxTextScore: Double, fullText: String) -> Double {
        guard maxTextScore > 0.4 else { return 0 }
        let f = fullText.lowercased()
        if burgerIntent(f) || tacoIntent(f) || sushiIntent(f) {
            return max(2.35, maxTextScore * 0.33)
        }
        return max(1.2, maxTextScore * 0.24)
    }

    /// Keeps only rows that match the question well enough; falls back if that would empty the list.
    private static func filterByRelevance(_ sorted: [MapVoiceRankedPlace], maxTextScore: Double, fullText: String) -> [MapVoiceRankedPlace] {
        guard !sorted.isEmpty else { return [] }
        let strict = minimumRelevanceScore(maxTextScore: maxTextScore, fullText: fullText)
        let strong = sorted.filter { $0.textScore >= strict }
        if !strong.isEmpty { return strong }
        let loose = max(0.45, maxTextScore * 0.12)
        let weak = sorted.filter { $0.textScore >= loose }
        return weak.isEmpty ? sorted : weak
    }

    /// When user asked for a distance, only return POIs in the target ring (tight, then wider) that also passed relevance.
    private static func filterByTargetRing(
        _ relevantOrdered: [MapVoiceRankedPlace],
        targetMeters: Double,
        maxCount: Int
    ) -> [MapVoiceRankedPlace] {
        let tight = relevantOrdered.filter { row in
            guard row.distanceMeters.isFinite else { return false }
            return targetDistanceBandFit(meters: row.distanceMeters, targetMeters: targetMeters) >= 0.99
        }
        if !tight.isEmpty {
            return Array(tight.prefix(maxCount))
        }
        let wide = relevantOrdered.filter { row in
            guard row.distanceMeters.isFinite else { return false }
            return targetDistanceBandWide(meters: row.distanceMeters, targetMeters: targetMeters)
        }
        if !wide.isEmpty {
            return Array(wide.prefix(maxCount))
        }
        return Array(relevantOrdered.prefix(maxCount))
    }

    /// Drops distance-from-user outliers so the list doesn’t mix a tight local cluster with one pin many miles out.
    /// Anchor = median of the ⌈n/2⌉ **smallest** distances among top results (robust to a single far score).
    private static func cohesionClusterByUserDistance(
        _ list: [MapVoiceRankedPlace],
        maxCount: Int,
        hasReference: Bool
    ) -> [MapVoiceRankedPlace] {
        guard hasReference, list.count >= 2 else {
            return Array(list.prefix(maxCount))
        }
        let sample = Array(list.prefix(min(24, list.count)))
        let finiteSample = sample.filter { $0.distanceMeters.isFinite }
        guard finiteSample.count >= 2 else {
            return Array(list.prefix(maxCount))
        }

        let sortedAsc = finiteSample.map(\.distanceMeters).sorted()
        let kSmallest = max(2, (sortedAsc.count + 1) / 2)
        let core = Array(sortedAsc.prefix(kSmallest))
        let anchor = core[core.count / 2]

        func kept(halfWidthMiles: Double) -> [MapVoiceRankedPlace] {
            let w = halfWidthMiles * 1609.34
            return list.filter { row in
                guard row.distanceMeters.isFinite else { return true }
                return abs(row.distanceMeters - anchor) <= w
            }
        }

        var halfMiles = 2.5
        var result = kept(halfWidthMiles: halfMiles)
        if result.count < min(4, finiteSample.count), result.count < list.count {
            halfMiles = 4
            let wider = kept(halfWidthMiles: halfMiles)
            if wider.count > result.count { result = wider }
        }
        if result.count < min(3, finiteSample.count), result.count < list.count {
            halfMiles = 6
            let wider = kept(halfWidthMiles: halfMiles)
            if wider.count > result.count { result = wider }
        }

        if result.isEmpty { result = list }
        return Array(result.prefix(maxCount))
    }

    /// Ranks POIs in `candidates` for `query`; uses `referenceLocation` for distance when set.
    static func ranked(
        candidates: [CachedPOI],
        query: String,
        referenceLocation: CLLocation?
    ) -> [MapVoiceRankedPlace] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let loweredFull = trimmed.lowercased()
        let tokens = tokensForRanking(from: trimmed)
        let hints = categoryHints(for: tokens, fullText: loweredFull)
        let requestedTargetM = parseRequestedDistanceMeters(in: loweredFull)
        let specificIntent = hasSpecificPlaceIntent(tokens: tokens, hints: hints, fullText: loweredFull)

        struct Pre {
            let poi: CachedPOI
            let tScore: Double
            let distanceMeters: Double
        }
        var pre: [Pre] = []
        pre.reserveCapacity(candidates.count)

        for poi in candidates {
            let osmMk = osmAndMapKitMatchScore(poi: poi, tokens: tokens, fullText: loweredFull)
            let baseTextScore: Double
            if tokens.isEmpty, hints.isEmpty {
                let nameHit = trimmed.isEmpty ? false : poi.name.lowercased().localizedStandardContains(loweredFull)
                baseTextScore = (nameHit ? 3.0 : 0) + osmMk
            } else {
                baseTextScore = textMatchScore(poi: poi, tokens: tokens, categoryHints: hints, fullText: loweredFull) + osmMk
            }
            let tScore = applyIntentRefinements(baseScore: baseTextScore, poi: poi, fullText: loweredFull)
            let poiLoc = CLLocation(latitude: poi.latitude, longitude: poi.longitude)
            let meters: Double
            if let ref = referenceLocation {
                meters = ref.distance(from: poiLoc)
                if meters > maxVoiceSearchMeters { continue }
            } else {
                meters = .nan
            }
            pre.append(Pre(poi: poi, tScore: tScore, distanceMeters: meters))
        }

        let maxT = pre.map(\.tScore).max() ?? 0

        var rows: [MapVoiceRankedPlace] = []
        for p in pre {
            let dProximity: Double
            if p.distanceMeters.isFinite {
                dProximity = distanceScoreCapped(meters: p.distanceMeters)
            } else {
                dProximity = 0.32
            }

            let dBlended: Double
            if let tgt = requestedTargetM, p.distanceMeters.isFinite {
                let band = targetDistanceBandFit(meters: p.distanceMeters, targetMeters: tgt)
                dBlended = 0.84 * band + 0.16 * dProximity
            } else if p.distanceMeters.isFinite {
                dBlended = distanceScore(meters: p.distanceMeters)
            } else {
                dBlended = 0.32
            }

            let gate = relevanceGate(textScore: p.tScore, maxTextScore: maxT)
            let gatedDistance = dBlended * gate

            let textNorm = min(1.0, p.tScore / 28.0)
            let textW: Double
            if requestedTargetM != nil {
                textW = 0.76
            } else if specificIntent {
                textW = 0.74
            } else {
                textW = 0.52
            }
            let combined = textW * textNorm + (1 - textW) * gatedDistance

            rows.append(
                MapVoiceRankedPlace(
                    poi: p.poi,
                    combinedScore: combined,
                    textScore: p.tScore,
                    distanceScore: gatedDistance,
                    distanceMeters: p.distanceMeters
                )
            )
        }

        let sorted = rows.sorted { lhs, rhs in
            if lhs.combinedScore != rhs.combinedScore {
                return lhs.combinedScore > rhs.combinedScore
            }
            if lhs.textScore != rhs.textScore {
                return lhs.textScore > rhs.textScore
            }
            return lhs.distanceMeters < rhs.distanceMeters
        }

        let relevancePass = filterByRelevance(sorted, maxTextScore: maxT, fullText: loweredFull)
        let hasRef = referenceLocation != nil
        let pool: [MapVoiceRankedPlace]
        if let tgt = requestedTargetM, hasRef {
            pool = filterByTargetRing(relevancePass, targetMeters: tgt, maxCount: 20)
        } else {
            pool = Array(relevancePass.prefix(20))
        }
        return cohesionClusterByUserDistance(pool, maxCount: 12, hasReference: hasRef)
    }

    /// Re-order after async MapKit writes so refined categories affect ordering.
    static func resortWithPostEnrichment(_ rows: [MapVoiceRankedPlace], query: String) -> [MapVoiceRankedPlace] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = tokensForRanking(from: trimmed)
        let lowered = trimmed.lowercased()

        func boost(_ poi: CachedPOI) -> Double {
            var b = 0.0
            guard let meta = POIExtendedMetadataCodec.decode(poi.extendedMetadataJSON) else { return 0 }
            if let mk = meta.mapKit {
                let blob = mk.pointOfInterestCategoryDescription.lowercased()
                for tok in tokens where tok.count > 2 {
                    if shouldIgnoreShopTokensInQuery(lowered), tok == "shop" || tok == "shops" { continue }
                    if blob.contains(tok) { b += 0.028 }
                }
            }
            if pizzaIntent(lowered), let tags = meta.osmTags, let c = tags["cuisine"], c.contains("pizza") {
                b += 0.04
            }
            return b
        }

        return rows.sorted { a, b in
            let sa = a.combinedScore + boost(a.poi)
            let sb = b.combinedScore + boost(b.poi)
            if sa != sb { return sa > sb }
            if a.textScore != b.textScore { return a.textScore > b.textScore }
            return a.distanceMeters < b.distanceMeters
        }
    }
}

// MARK: - Speech

@MainActor
final class MapSpeechTranscriptionController: ObservableObject {
    @Published private(set) var isListening = false
    /// Editable from the map search sheet (typing) and updated live while dictating.
    @Published var transcript = ""
    @Published var errorMessage: String?

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let recognizer: SFSpeechRecognizer?

    init() {
        recognizer = SFSpeechRecognizer(locale: Locale.current)
    }

    func resetTranscript() {
        transcript = ""
        errorMessage = nil
    }

    private func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func startListening() async {
        errorMessage = nil

        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition isn’t available on this device."
            return
        }

        let speechStatus = await requestSpeechAuthorization()
        guard speechStatus == .authorized else {
            errorMessage = "Allow speech recognition in Settings to use voice search."
            return
        }

        let micOK = await requestMicrophonePermission()
        guard micOK else {
            errorMessage = "Microphone access is needed to hear your request."
            return
        }

        stopListening()

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Could not set up audio: \(error.localizedDescription)"
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else {
            errorMessage = "Could not create speech request."
            return
        }
        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak recognitionRequest] buffer, _ in
            recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            errorMessage = "Could not start microphone: \(error.localizedDescription)"
            cleanupAudio()
            return
        }

        isListening = true

        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if error != nil {
                    self.stopListening()
                }
            }
        }
    }

    func stopListening() {
        guard isListening || audioEngine.isRunning else {
            cleanupAudio()
            return
        }

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isListening = false

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func cleanupAudio() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isListening = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
