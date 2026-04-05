//
//  FriendRequestLedgerSync.swift
//  Venture Local
//
//  Mirrors incoming Supabase friend requests into the journal ledger + toast,
//  and records “friend accepted” confirmations for both parties (deduped).
//

import Foundation
import SwiftData

private enum FriendAcceptedNotifiedStore {
    private static let idsKey = "VentureLocalFriendAcceptedNotifiedUUIDs"
    private static let didMigrateKey = "VentureLocalFriendAcceptedNotifiedDidMigrate"

    static func all() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: idsKey) ?? [])
    }

    static func contains(_ id: UUID) -> Bool {
        all().contains(id.uuidString)
    }

    static func insert(_ id: UUID) {
        var s = all()
        guard s.insert(id.uuidString).inserted else { return }
        UserDefaults.standard.set(Array(s), forKey: idsKey)
    }

    static var didMigrate: Bool {
        get { UserDefaults.standard.bool(forKey: didMigrateKey) }
        set { UserDefaults.standard.set(newValue, forKey: didMigrateKey) }
    }
}

@MainActor
enum FriendRequestLedgerSync {
    /// Call after a friendship becomes `accepted` (e.g. current user tapped Accept). Deduped with cloud sync.
    static func recordFriendAcceptedIfNeeded(
        modelContext: ModelContext,
        friendshipId: UUID,
        otherDisplayName: String,
        postToast: Bool
    ) {
        guard !FriendAcceptedNotifiedStore.contains(friendshipId) else { return }
        FriendAcceptedNotifiedStore.insert(friendshipId)

        let title = "You and \(otherDisplayName) are now friends!"
        let row = LedgerNotification(
            kind: .friendAccepted,
            title: title,
            body: "",
            friendshipIdString: friendshipId.uuidString
        )
        modelContext.insert(row)
        try? modelContext.save()

        if postToast {
            InAppToastNotification.post(kind: .friend, title: title, subtitle: nil)
        }
    }

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

        // Accepted friendships: notify once per friendship id (requester sees this after the other person accepts).
        let acceptedItems = links.filter { $0.status == "accepted" }
        if !FriendAcceptedNotifiedStore.didMigrate {
            for item in acceptedItems {
                FriendAcceptedNotifiedStore.insert(item.id)
            }
            FriendAcceptedNotifiedStore.didMigrate = true
        } else {
            for item in acceptedItems {
                recordFriendAcceptedIfNeeded(
                    modelContext: modelContext,
                    friendshipId: item.id,
                    otherDisplayName: item.otherDisplayName,
                    postToast: true
                )
            }
        }

        try? modelContext.save()
    }
}
