//
//  FriendsView.swift
//  Venture Local
//

import SwiftUI
import UIKit

struct FriendsView: View {
    @EnvironmentObject private var theme: ThemeSettings
    @EnvironmentObject private var auth: AuthSessionController

    @State private var friendIdDraft = ""
    @State private var items: [CloudFriendshipItem] = []
    @State private var isLoading = false
    @State private var banner: String?

    private var explorerIdText: String {
        auth.currentSupabaseUserId ?? "—"
    }

    var body: some View {
        let _ = theme.useDarkVintagePalette
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Share your Venture ID so friends can send you a request.")
                        .font(.vlCaption(12))
                        .foregroundStyle(VLColor.dustyBlue)

                    HStack {
                        Text(explorerIdText)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(VLColor.ink)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                        Spacer()
                        Button("Copy") {
                            UIPasteboard.general.string = explorerIdText
                            banner = "Copied Venture ID"
                        }
                        .font(.vlBody(15).weight(.semibold))
                        .foregroundStyle(VLColor.burgundy)
                    }
                    .padding(14)
                    .background(VLColor.paperSurface)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(VLColor.burgundy.opacity(0.3), lineWidth: 1.2))
                    .cornerRadius(12)

                    if let banner {
                        Text(banner)
                            .font(.vlCaption(12))
                            .foregroundStyle(VLColor.darkTeal)
                    }

                    Text("Add friend by ID")
                        .font(.vlCaption())
                        .foregroundStyle(VLColor.ink)
                    TextField("Friend’s Venture ID", text: $friendIdDraft)
                        .textContentType(.none)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(VLColor.ink)
                        .tint(VLColor.burgundy)
                        .padding(14)
                        .background(VLColor.paperSurface)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(VLColor.burgundy.opacity(0.35), lineWidth: 2))
                        .cornerRadius(12)

                    Button {
                        Task { await sendRequest() }
                    } label: {
                        Text("Send friend request")
                            .font(.vlBody(16).weight(.semibold))
                            .foregroundStyle(VLColor.cream)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(VLColor.burgundy)
                            .cornerRadius(12)
                    }
                    .buttonStyle(.plain)

                    if isLoading {
                        ProgressView()
                            .tint(VLColor.burgundy)
                            .frame(maxWidth: .infinity)
                    }

                    friendshipSection(title: "Friends", filter: { $0.status == "accepted" })
                }
                .padding(20)
            }
            .scrollContentBackground(.hidden)
            .refreshable { await reload() }
        }
        .navigationTitle("")
        .vintageNavigationChrome()
        .task { await reload() }
    }

    @ViewBuilder
    private func friendshipSection(title: String, filter: (CloudFriendshipItem) -> Bool) -> some View {
        let rows = items.filter(filter)
        if !rows.isEmpty {
            Text(title)
                .font(.vlCaption())
                .foregroundStyle(VLColor.subtleInk)
                .padding(.top, 8)
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(row.otherDisplayName)
                            .font(.vlBody(16))
                            .foregroundStyle(VLColor.ink)
                        Spacer()
                        Text(row.status.capitalized)
                            .font(.vlCaption(11))
                            .foregroundStyle(VLColor.darkTeal)
                    }
                    if row.status == "accepted" {
                        Button("Remove friend") {
                            Task { await remove(row) }
                        }
                        .font(.vlCaption(12))
                        .foregroundStyle(VLColor.dustyBlue)
                    }
                }
                .padding(14)
                .background(VLColor.paperSurface.opacity(0.95))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(VLColor.burgundy.opacity(0.22), lineWidth: 1))
                .cornerRadius(12)
            }
        }
    }

    private func reload() async {
        CloudSyncService.shared.bind(auth: auth)
        guard auth.isSignedIn else {
            items = []
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await CloudSyncService.shared.loadFriendships()
        } catch is CancellationError {
            return
        } catch {
            banner = error.localizedDescription
        }
    }

    private func sendRequest() async {
        banner = nil
        let trimmed = friendIdDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let uuid = UUID(uuidString: trimmed) else {
            banner = "That doesn’t look like a valid Venture ID."
            return
        }
        do {
            try await CloudSyncService.shared.sendFriendRequest(toAddresseeId: uuid)
            friendIdDraft = ""
            banner = "Request sent."
            await reload()
        } catch {
            banner = error.localizedDescription
        }
    }

    private func remove(_ row: CloudFriendshipItem) async {
        do {
            try await CloudSyncService.shared.deleteFriendship(friendshipId: row.id)
            await reload()
        } catch {
            banner = error.localizedDescription
        }
    }
}
