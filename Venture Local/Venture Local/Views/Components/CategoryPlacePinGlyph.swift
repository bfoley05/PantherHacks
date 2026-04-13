//
//  CategoryPlacePinGlyph.swift
//  Venture Local
//
//  Map-style category pin (colored disk + symbol) for lists and shared UI.
//

import SwiftUI

enum CategoryPinChrome {
    static let symbolOnPin = Color(red: 0xF5 / 255, green: 0xE9 / 255, blue: 0xD3 / 255)
    static let unknownCategoryFill = Color(red: 0.52, green: 0.48, blue: 0.46)
    static let partnerSeal = Color(red: 0xC8 / 255, green: 0x9B / 255, blue: 0x3C / 255)
}

struct CategoryPlacePinGlyph: View {
    let categoryRaw: String
    /// Matches undiscovered circular POI pins on the map (size, tinted fill, symbol scale).
    var matchesMapUndiscoveredPin: Bool = true
    /// Larger list variant when not matching map metrics.
    var diameter: CGFloat = 34
    var symbolPointSize: CGFloat = 13

    private var category: DiscoveryCategory? {
        DiscoveryCategory(rawValue: categoryRaw)
    }

    var body: some View {
        let base = category?.mapPinMutedFill ?? CategoryPinChrome.unknownCategoryFill
        let pinFill = matchesMapUndiscoveredPin ? base.opacity(0.62) : base.opacity(0.9)
        let d = matchesMapUndiscoveredPin ? 28.0 : diameter
        ZStack {
            Circle()
                .fill(pinFill)
                .frame(width: d, height: d)
            Image(systemName: category?.symbol ?? "mappin")
                .font(matchesMapUndiscoveredPin ? .caption.weight(.semibold) : .system(size: symbolPointSize, weight: .semibold))
                .foregroundStyle(CategoryPinChrome.symbolOnPin)
        }
        .frame(width: 36, height: 36)
        .accessibilityHidden(true)
    }
}
