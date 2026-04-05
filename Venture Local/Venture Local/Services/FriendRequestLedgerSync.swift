//
//  FriendRequestLedgerSync.swift
//  Venture Local
//
//  Mirrors incoming Supabase friend requests into the journal ledger + toast.
//

import Foundation
import SwiftData

@MainActor
enum FriendRequestLedgerSync {
    static func sync(modelContext: ModelContext, auth: AuthSessionController) async {
        CloudSyncService.shared.bind(auth: auth)
        guard auth.isSignedIn else { return }

        let links: [CloudFriendshipItem]
        do {
            links = try await CloudSyncService.shared.loadFriendships()
        } catch {
            return
        }

        let incomingPending = links.filter { $0.isIncoming && $0.status == "pending" }
        let pendingIds = Set(incomingPending.map { $0.id.uuidString })

        let frPred = #Predicate<LedgerNotification> { $0.kindRaw == "friendRequest" }
        let friendRows = (try? modelContext.fetch(FetchDescriptor<LedgerNotification>(predicate: frPred))) ?? []

        for row in friendRows {
            guard let fid = row.friendshipIdString, !pendingIds.contains(fid) else { continue }
            modelContext.delete(row)
        }

        let remainingFriendRows = (try? modelContext.fetch(FetchDescriptor<LedgerNotification>(predicate: frPred))) ?? []
        var knownFriendshipIds = Set(remainingFriendRows.compactMap(\.friendshipIdString))

        for item in incomingPending {
            let fid = item.id.uuidString
            if knownFriendshipIds.contains(fid) { continue }
            knownFriendshipIds.insert(fid)

            let row = LedgerNotification(
                kind: .friendRequest,
                title: item.otherDisplayName,
                body: "Wants to connect on Venture Local.",
                friendshipIdString: fid
            )
            modelContext.insert(row)
            InAppToastNotification.post(kind: .friend, title: item.otherDisplayName, subtitle: "Friend request")
        }

        try? modelContext.save()
    }
}
