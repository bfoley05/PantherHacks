//
//  CityLocalsBaseline.swift
//  Venture Local
//
//  Full-city counts from Overpass (city bounding box) so journal totals don’t grow as the map loads more tiles.
//

import Foundation
import SwiftData

extension Notification.Name {
    /// Posted when a full-city Overpass baseline is saved so the journal can refresh totals.
    static let ventureLocalCityBaselineUpdated = Notification.Name("VentureLocalCityBaselineUpdated")
}

@Model
final class CityLocalsBaseline {
    @Attribute(.unique) var cityKey: String
    /// Non-chain local businesses matching journal categories (same rules as CachedPOI merge).
    var nonChainLocalTotal: Int
    /// JSON object: category raw string → count.
    var categoryTotalsJSON: Data?
    var updatedAt: Date

    init(cityKey: String, nonChainLocalTotal: Int = 0, categoryTotalsJSON: Data? = nil, updatedAt: Date = .now) {
        self.cityKey = cityKey
        self.nonChainLocalTotal = nonChainLocalTotal
        self.categoryTotalsJSON = categoryTotalsJSON
        self.updatedAt = updatedAt
    }
}
