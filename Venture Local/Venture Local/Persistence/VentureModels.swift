//
//  VentureModels.swift
//  Venture Local
//

import Foundation
import SwiftData

@Model
final class ExplorerProfile {
    @Attribute(.unique) var singletonTag: String
    var displayName: String
    var avatarKindRaw: String
    var homeCityKey: String?
    var homeCityDisplayName: String?
    var totalXP: Int
    var onboardingComplete: Bool
    var selectedCityKey: String?
    /// When set, journal completion and stats use this city; nearby claims still follow live GPS.
    var pinnedExplorationCityKey: String?
    var partnerConfigJSON: Data?
    /// One-time backfill of `ExplorerEvent` from legacy data. Optional so existing stores migrate (`nil` = not done).
    var explorerEventBackfillDone: Bool?

    init(
        singletonTag: String = "me",
        displayName: String = "Explorer",
        avatarKindRaw: String = ExplorerAvatar.explorer.rawValue,
        homeCityKey: String? = nil,
        homeCityDisplayName: String? = nil,
        totalXP: Int = 0,
        onboardingComplete: Bool = false,
        selectedCityKey: String? = nil,
        pinnedExplorationCityKey: String? = nil,
        partnerConfigJSON: Data? = nil,
        explorerEventBackfillDone: Bool? = false
    ) {
        self.singletonTag = singletonTag
        self.displayName = displayName
        self.avatarKindRaw = avatarKindRaw
        self.homeCityKey = homeCityKey
        self.homeCityDisplayName = homeCityDisplayName
        self.totalXP = totalXP
        self.onboardingComplete = onboardingComplete
        self.selectedCityKey = selectedCityKey
        self.pinnedExplorationCityKey = pinnedExplorationCityKey
        self.partnerConfigJSON = partnerConfigJSON
        self.explorerEventBackfillDone = explorerEventBackfillDone
    }

    /// City for progress UI and completion stats: manual pin wins, then live GPS, then first-resolved profile key.
    func effectiveProgressCityKey(liveCityKey: String?) -> String? {
        if let p = pinnedExplorationCityKey, !p.isEmpty { return p }
        if let l = liveCityKey, !l.isEmpty { return l }
        if let s = selectedCityKey, !s.isEmpty { return s }
        return nil
    }
}

@Model
final class CachedPOI {
    @Attribute(.unique) var osmId: String
    var name: String
    var latitude: Double
    var longitude: Double
    var categoryRaw: String
    var isChain: Bool
    var chainLabel: String?
    var isPartner: Bool
    var partnerOffer: String?
    var stampCode: String?
    var addressSummary: String?
    var cacheDate: Date
    var cityKey: String

    init(
        osmId: String,
        name: String,
        latitude: Double,
        longitude: Double,
        categoryRaw: String,
        isChain: Bool,
        chainLabel: String?,
        isPartner: Bool,
        partnerOffer: String?,
        stampCode: String?,
        addressSummary: String?,
        cacheDate: Date = .now,
        cityKey: String
    ) {
        self.osmId = osmId
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.categoryRaw = categoryRaw
        self.isChain = isChain
        self.chainLabel = chainLabel
        self.isPartner = isPartner
        self.partnerOffer = partnerOffer
        self.stampCode = stampCode
        self.addressSummary = addressSummary
        self.cacheDate = cacheDate
        self.cityKey = cityKey
    }
}

@Model
final class DiscoveredPlace {
    @Attribute(.unique) var osmId: String
    var discoveredAt: Date
    var cityKey: String
    var explorerNote: String?

    init(osmId: String, discoveredAt: Date = .now, cityKey: String, explorerNote: String? = nil) {
        self.osmId = osmId
        self.discoveredAt = discoveredAt
        self.cityKey = cityKey
        self.explorerNote = explorerNote
    }
}

@Model
final class StampRecord {
    var id: UUID
    var osmId: String
    var stampedAt: Date
    var cityKey: String
    /// When true, this row was added from an in-app QR scan (subject to one QR scan per place per day).
    var viaPartnerQR: Bool

    init(id: UUID = UUID(), osmId: String, stampedAt: Date = .now, cityKey: String, viaPartnerQR: Bool = false) {
        self.id = id
        self.osmId = osmId
        self.stampedAt = stampedAt
        self.cityKey = cityKey
        self.viaPartnerQR = viaPartnerQR
    }
}

@Model
final class VisitedRoadSegment {
    @Attribute(.unique) var segmentKey: String
    var wayId: Int64
    var polylineJSON: Data
    var firstVisitedAt: Date
    var cityKey: String?

    init(segmentKey: String, wayId: Int64, polylineJSON: Data, firstVisitedAt: Date = .now, cityKey: String?) {
        self.segmentKey = segmentKey
        self.wayId = wayId
        self.polylineJSON = polylineJSON
        self.firstVisitedAt = firstVisitedAt
        self.cityKey = cityKey
    }
}

@Model
final class BadgeUnlock {
    @Attribute(.unique) var code: String
    var title: String
    var tierRaw: String
    var xpAwarded: Int
    var unlockedAt: Date

    init(code: String, title: String, tierRaw: String, xpAwarded: Int, unlockedAt: Date = .now) {
        self.code = code
        self.title = title
        self.tierRaw = tierRaw
        self.xpAwarded = xpAwarded
        self.unlockedAt = unlockedAt
    }
}

enum LedgerNotificationKind: String, Codable {
    case badgeUnlocked
    case levelUp
}

/// In-app notification row (badge / level-up); mirrored with a low-interruption local notification when permitted.
@Model
final class LedgerNotification {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    var title: String
    var body: String
    var createdAt: Date
    var isRead: Bool
    var badgeCode: String?
    var levelReached: Int?

    init(
        id: UUID = UUID(),
        kind: LedgerNotificationKind,
        title: String,
        body: String,
        createdAt: Date = .now,
        isRead: Bool = false,
        badgeCode: String? = nil,
        levelReached: Int? = nil
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.isRead = isRead
        self.badgeCode = badgeCode
        self.levelReached = levelReached
    }

    var kind: LedgerNotificationKind { LedgerNotificationKind(rawValue: kindRaw) ?? .badgeUnlocked }
}

// MARK: - Badge activity log (Phase A)

enum ExplorerEventKind: String, Codable, CaseIterable {
    case visit
    case revisit
    case save
    case unsave
    case favorite
    case unfavorite
    case stamp
}

@Model
final class ExplorerEvent {
    var id: UUID
    var kindRaw: String
    var osmId: String
    var cityKey: String
    var categoryRaw: String
    var isChain: Bool
    var occurredAt: Date
    var payloadJSON: Data?

    init(
        id: UUID = UUID(),
        kind: ExplorerEventKind,
        osmId: String,
        cityKey: String,
        categoryRaw: String,
        isChain: Bool,
        occurredAt: Date = .now,
        payloadJSON: Data? = nil
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.osmId = osmId
        self.cityKey = cityKey
        self.categoryRaw = categoryRaw
        self.isChain = isChain
        self.occurredAt = occurredAt
        self.payloadJSON = payloadJSON
    }
}

@Model
final class SavedPlace {
    @Attribute(.unique) var osmId: String
    var savedAt: Date
    var cityKey: String

    init(osmId: String, savedAt: Date = .now, cityKey: String) {
        self.osmId = osmId
        self.savedAt = savedAt
        self.cityKey = cityKey
    }
}

@Model
final class FavoritePlace {
    @Attribute(.unique) var osmId: String
    var favoritedAt: Date
    var cityKey: String

    init(osmId: String, favoritedAt: Date = .now, cityKey: String) {
        self.osmId = osmId
        self.favoritedAt = favoritedAt
        self.cityKey = cityKey
    }
}

/// Local-only “I saved a photo for this place” check-in (no image binary stored on-device in MVP).
@Model
final class PlacePhotoCheckIn {
    @Attribute(.unique) var osmId: String
    var createdAt: Date
    var cityKey: String

    init(osmId: String, createdAt: Date = .now, cityKey: String) {
        self.osmId = osmId
        self.createdAt = createdAt
        self.cityKey = cityKey
    }
}

enum ExplorerAvatar: String, CaseIterable, Identifiable {
    case explorer, naturalist, cartographer, mystic
    var id: String { rawValue }
    var title: String {
        switch self {
        case .explorer: "Explorer"
        case .naturalist: "Naturalist"
        case .cartographer: "Cartographer"
        case .mystic: "Mystic"
        }
    }
    var symbol: String {
        switch self {
        case .explorer: "figure.hiking"
        case .naturalist: "leaf.circle"
        case .cartographer: "map"
        case .mystic: "moon.stars"
        }
    }
}
