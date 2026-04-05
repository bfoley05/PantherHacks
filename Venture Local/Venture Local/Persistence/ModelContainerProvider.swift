//
//  ModelContainerProvider.swift
//  Venture Local
//

import Foundation
import SwiftData

enum ModelContainerProvider {
    static let shared: ModelContainer = {
        let schema = Schema([
            ExplorerProfile.self,
            CachedPOI.self,
            DiscoveredPlace.self,
            StampRecord.self,
            VisitedRoadSegment.self,
            BadgeUnlock.self,
            ExplorerEvent.self,
            SavedPlace.self,
            FavoritePlace.self,
            PlacePhotoCheckIn.self,
            LedgerNotification.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("SwiftData container failed: \(error)")
        }
    }()
}
