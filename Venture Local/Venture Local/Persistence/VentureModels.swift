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
    var partnerConfigJSON: Data?

    init(
        singletonTag: String = "me",
        displayName: String = "Explorer",
        avatarKindRaw: String = ExplorerAvatar.explorer.rawValue,
        homeCityKey: String? = nil,
        homeCityDisplayName: String? = nil,
        totalXP: Int = 0,
        onboardingComplete: Bool = false,
        selectedCityKey: String? = nil,
        partnerConfigJSON: Data? = nil
    ) {
        self.singletonTag = singletonTag
        self.displayName = displayName
        self.avatarKindRaw = avatarKindRaw
        self.homeCityKey = homeCityKey
        self.homeCityDisplayName = homeCityDisplayName
        self.totalXP = totalXP
        self.onboardingComplete = onboardingComplete
        self.selectedCityKey = selectedCityKey
        self.partnerConfigJSON = partnerConfigJSON
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
