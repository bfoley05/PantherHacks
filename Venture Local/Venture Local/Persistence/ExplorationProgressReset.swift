//
//  ExplorationProgressReset.swift
//  Venture Local
//
//  Clears on-device exploration progress for testing (journal, passport, road XP).
//

import SwiftData

enum ExplorationProgressReset {
    /// Deletes all discovered places, passport stamps, visited road segments, and resets profile XP. Keeps profile name, cached map POIs, and settings.
    static func clearAllVisitAndExplorationData(in context: ModelContext) throws {
        try deleteAll(DiscoveredPlace.self, in: context)
        try deleteAll(StampRecord.self, in: context)
        try deleteAll(VisitedRoadSegment.self, in: context)
        try deleteAll(BadgeUnlock.self, in: context)
        try deleteAll(ExplorerEvent.self, in: context)
        try deleteAll(SavedPlace.self, in: context)
        try deleteAll(FavoritePlace.self, in: context)
        try deleteAll(PlacePhotoCheckIn.self, in: context)
        try deleteAll(LedgerNotification.self, in: context)
        if let p = try context.fetch(FetchDescriptor<ExplorerProfile>()).first {
            p.totalXP = 0
            p.explorerEventBackfillDone = nil
        }
        try context.save()
    }

    private static func deleteAll<T: PersistentModel>(_ type: T.Type, in context: ModelContext) throws {
        let rows = try context.fetch(FetchDescriptor<T>())
        for row in rows {
            context.delete(row)
        }
    }
}
