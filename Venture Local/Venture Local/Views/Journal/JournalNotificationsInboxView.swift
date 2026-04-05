//
//  JournalNotificationsInboxView.swift
//  Venture Local
//

import SwiftData
import SwiftUI

struct JournalNotificationsInboxView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var theme: ThemeSettings
    @EnvironmentObject private var auth: AuthSessionController

    @Query(sort: \LedgerNotification.createdAt, order: .reverse) private var items: [LedgerNotification]

    @State private var friendActionError: String?

    var onOpenBadgesTab: () -> Void
    var onOpenJournalTab: () -> Void

    var body: some View {
        let _ = theme.useDarkVintagePalette
        ZStack {
            PaperBackground()
            VStack(spacing: 0) {
                if let friendActionError {
                    Text(friendActionError)
                        .font(.vlCaption(12))
                        .foregroundStyle(VLColor.burgundy)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
            Group {
                if items.isEmpty {
                    Text("No notifications yet. Badge unlocks, level-ups, and friend requests appear here.")
                        .font(.vlBody(15))
                        .foregroundStyle(VLColor.dustyBlue)
                        .multilineTextAlignment(.center)
                        .padding(24)
                } else {
                    List {
                        ForEach(items, id: \.id) { row in
                            if row.kind == .friendRequest {
                                friendRequestRow(row)
                            } else {
                                standardRow(row)
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .vintageNavigationChrome()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if items.contains(where: { !$0.isRead }) {
                    Button("Mark all read") {
                        for row in items where !row.isRead {
                            row.isRead = true
                        }
                        try? modelContext.save()
                    }
                    .font(.vlCaption(12))
                    .foregroundStyle(VLColor.burgundy)
                }
            }
        }
        .onAppear {
            friendActionError = nil
            Task { await FriendRequestLedgerSync.sync(modelContext: modelContext, auth: auth) }
        }
        .refreshable {
            await FriendRequestLedgerSync.sync(modelContext: modelContext, auth: auth)
        }
    }

    @ViewBuilder
    private func iconForRow(_ row: LedgerNotification) -> some View {
        let name: String = {
            switch row.kind {
            case .badgeUnlocked: return "rosette"
            case .levelUp: return "arrow.up.circle.fill"
            case .friendRequest: return "person.2.fill"
            }
        }()
        Image(systemName: name)
            .font(.title3)
            .foregroundStyle(row.isRead ? VLColor.subtleInk : VLColor.mutedGold)
            .frame(width: 28)
    }

    @ViewBuilder
    private func standardRow(_ row: LedgerNotification) -> some View {
        Button {
            markRead(row)
            switch row.kind {
            case .badgeUnlocked:
                dismiss()
                onOpenBadgesTab()
            case .levelUp:
                dismiss()
                onOpenJournalTab()
            case .friendRequest:
                break
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                iconForRow(row)
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.title)
                        .font(.vlBody(16).weight(row.isRead ? .regular : .semibold))
                        .foregroundStyle(VLColor.ink)
                    Text(row.body)
                        .font(.vlCaption(12))
                        .foregroundStyle(VLColor.dustyBlue)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(row.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.vlCaption(10))
                        .foregroundStyle(VLColor.subtleInk)
                }
                Spacer(minLength: 0)
                if !row.isRead {
                    Circle()
                        .fill(VLColor.burgundy)
                        .frame(width: 8, height: 8)
                        .accessibilityLabel("Unread")
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .listRowBackground(VLColor.paperSurface.opacity(0.92))
    }

    @ViewBuilder
    private func friendRequestRow(_ row: LedgerNotification) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                iconForRow(row)
                VStack(alignment: .leading, spacing: 4) {
                    Text("NEW")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(VLColor.cream)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(VLColor.burgundy)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    Text("Friend request")
                        .font(.vlCaption(11).weight(.semibold))
                        .foregroundStyle(VLColor.darkTeal)
                    Text(row.title)
                        .font(.vlBody(16).weight(row.isRead ? .regular : .semibold))
                        .foregroundStyle(VLColor.ink)
                    Text(row.body)
                        .font(.vlCaption(12))
                        .foregroundStyle(VLColor.dustyBlue)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(row.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.vlCaption(10))
                        .foregroundStyle(VLColor.subtleInk)
                }
                Spacer(minLength: 0)
                if !row.isRead {
                    Circle()
                        .fill(VLColor.burgundy)
                        .frame(width: 8, height: 8)
                }
            }
            HStack(spacing: 10) {
                Button {
                    friendActionError = nil
                    Task { await acceptFriendRequest(row) }
                } label: {
                    Text("Accept")
                        .font(.vlBody(14).weight(.semibold))
                        .foregroundStyle(VLColor.cream)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(VLColor.darkTeal)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
                Button {
                    friendActionError = nil
                    Task { await declineFriendRequest(row) }
                } label: {
                    Text("Decline")
                        .font(.vlBody(14).weight(.semibold))
                        .foregroundStyle(VLColor.burgundy)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .listRowBackground(VLColor.paperSurface.opacity(0.92))
    }

    private func markRead(_ row: LedgerNotification) {
        row.isRead = true
        try? modelContext.save()
    }

    private func deleteLedgerRow(_ row: LedgerNotification) {
        modelContext.delete(row)
        try? modelContext.save()
    }

    private func acceptFriendRequest(_ row: LedgerNotification) async {
        guard let fidStr = row.friendshipIdString, let fid = UUID(uuidString: fidStr) else {
            friendActionError = "Missing request id."
            return
        }
        CloudSyncService.shared.bind(auth: auth)
        do {
            try await CloudSyncService.shared.acceptFriendship(friendshipId: fid)
            deleteLedgerRow(row)
            await FriendRequestLedgerSync.sync(modelContext: modelContext, auth: auth)
        } catch {
            friendActionError = error.localizedDescription
        }
    }

    private func declineFriendRequest(_ row: LedgerNotification) async {
        guard let fidStr = row.friendshipIdString, let fid = UUID(uuidString: fidStr) else {
            friendActionError = "Missing request id."
            return
        }
        CloudSyncService.shared.bind(auth: auth)
        do {
            try await CloudSyncService.shared.deleteFriendship(friendshipId: fid)
            deleteLedgerRow(row)
            await FriendRequestLedgerSync.sync(modelContext: modelContext, auth: auth)
        } catch {
            friendActionError = error.localizedDescription
        }
    }
}
