//
//  MainShellTabRouter.swift
//  Venture Local
//

import Combine
import SwiftUI

@MainActor
final class MainShellTabRouter: ObservableObject {
    enum Tab: Int, Hashable {
        case badges = 0
        case map = 1
        case journal = 2
        case passport = 3
        case social = 4
    }

    @Published var selectedTab: Tab = .journal
    @Published var pendingMapPlace: PendingMapPlace?
    /// Bumps on each Social → map handoff so `onChange` runs even if the same place is tapped twice.
    @Published var mapFocusGeneration: Int = 0

    struct PendingMapPlace: Equatable {
        var osmId: String
        var cityKey: String
        var name: String
        var latitude: Double
        var longitude: Double
    }

    func focusPlaceOnMap(_ place: PendingMapPlace) {
        pendingMapPlace = place
        mapFocusGeneration += 1
        selectedTab = .map
    }
}
