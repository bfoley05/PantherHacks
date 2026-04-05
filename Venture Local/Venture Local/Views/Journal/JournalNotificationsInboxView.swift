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

    @Query(sort: \LedgerNotification.createdAt, order: .reverse) private var items: [LedgerNotification]

    var onOpenBadgesTab: () -> Void
    var onOpenJournalTab: () -> Void

    var body: some View {
        let _ = theme.useDarkVintagePalette
        ZStack {
            PaperBackground()
            Group {
                if items.isEmpty {
                    Text("No notifications yet. Badge unlocks and level-ups will appear here.")
                        .font(.vlBody(15))
                        .foregroundStyle(VLColor.dustyBlue)
                        .multilineTextAlignment(.center)
                        .padding(24)
                } else {
                    List {
                        ForEach(items, id: \.id) { row in
                            Button {
                                markRead(row)
                                switch row.kind {
                                case .badgeUnlocked:
                                    dismiss()
                                    onOpenBadgesTab()
                                case .levelUp:
                                    dismiss()
                                    onOpenJournalTab()
                                }
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: row.kind == .badgeUnlocked ? "rosette" : "arrow.up.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(row.isRead ? VLColor.subtleInk : VLColor.mutedGold)
                                        .frame(width: 28)
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
                    }
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .navigationTitle("Notifications")
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
    }

    private func markRead(_ row: LedgerNotification) {
        row.isRead = true
        try? modelContext.save()
    }
}
