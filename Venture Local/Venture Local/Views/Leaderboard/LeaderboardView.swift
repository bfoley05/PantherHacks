//
//  LeaderboardView.swift
//  Venture Local
//

import SwiftData
import SwiftUI

struct LeaderboardView: View {
    @EnvironmentObject private var theme: ThemeSettings
    @EnvironmentObject private var auth: AuthSessionController
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [ExplorerProfile]

    private enum Scope: String, CaseIterable {
        case global = "Global"
        case friends = "Friends"
    }

    @State private var scope: Scope = .global
    @State private var cloudRows: [CloudLeaderboardEntry] = []
    @State private var isLoading = false
    @State private var loadError: String?

    private var myUserId: UUID? {
        guard let s = auth.currentSupabaseUserId else { return nil }
        return UUID(uuidString: s)
    }

    var body: some View {
        let _ = theme.useDarkVintagePalette
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Leaderboard")
                        .font(.vlTitle(24))
                        .foregroundStyle(VLColor.burgundy)

                    Picker("Scope", selection: $scope) {
                        ForEach(Scope.allCases, id: \.self) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                    .tint(VLColor.burgundy)

                    if auth.configurationMissing {
                        Text("Supabase isn’t configured; showing this device only.")
                            .font(.vlBody(14))
                            .foregroundStyle(VLColor.dustyBlue)
                        localFallbackList
                    } else if !auth.isSignedIn {
                        Text("Sign in to load the cloud leaderboard and friends.")
                            .font(.vlBody(14))
                            .foregroundStyle(VLColor.dustyBlue)
                        localFallbackList
                    } else {
                        if let loadError {
                            Text(loadError)
                                .font(.vlCaption(13))
                                .foregroundStyle(VLColor.burgundy)
                        }
                        if isLoading && cloudRows.isEmpty {
                            ProgressView()
                                .tint(VLColor.burgundy)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 24)
                        } else if cloudRows.isEmpty {
                            Text(scope == .friends ? "No friends yet — add explorers from Profile → Friends." : "No rankings loaded.")
                                .font(.vlBody(14))
                                .foregroundStyle(VLColor.darkTeal)
                        } else {
                            ForEach(Array(cloudRows.enumerated()), id: \.element.id) { idx, row in
                                leaderboardRow(rank: idx + 1, entry: row, highlight: row.id == myUserId)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .scrollContentBackground(.hidden)
            .refreshable { await refresh() }
        }
        .navigationTitle("Leaderboard")
        .vintageNavigationChrome()
        .task(id: scope) {
            await refresh()
        }
    }

    @ViewBuilder
    private var localFallbackList: some View {
        if profiles.isEmpty {
            Text("No explorers yet.")
                .font(.vlBody())
                .foregroundStyle(VLColor.darkTeal)
        } else {
            let sorted = profiles.sorted { $0.totalXP > $1.totalXP }
            ForEach(Array(sorted.enumerated()), id: \.element.persistentModelID) { idx, profile in
                localDeviceRow(rank: idx + 1, profile: profile)
            }
        }
    }

    private func localDeviceRow(rank: Int, profile: ExplorerProfile) -> some View {
        HStack {
            Text("#\(rank)")
                .font(.vlCaption())
                .foregroundStyle(VLColor.mutedGold)
                .frame(width: 34, alignment: .leading)
            Text(profile.displayName)
                .font(.vlBody(16))
                .foregroundStyle(VLColor.ink)
            Spacer()
            Text("\(profile.totalXP) XP")
                .font(.vlCaption())
                .foregroundStyle(VLColor.darkTeal)
        }
        .padding(12)
        .background(VLColor.paperSurface.opacity(0.92))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(VLColor.burgundy.opacity(0.25), lineWidth: 1.2))
        .cornerRadius(12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rank \(rank), \(profile.displayName), \(profile.totalXP) XP")
    }

    private func leaderboardRow(rank: Int, entry: CloudLeaderboardEntry, highlight: Bool) -> some View {
        HStack {
            Text("#\(rank)")
                .font(.vlCaption())
                .foregroundStyle(VLColor.mutedGold)
                .frame(width: 34, alignment: .leading)
            Text(entry.displayName)
                .font(.vlBody(16))
                .foregroundStyle(VLColor.ink)
            if highlight {
                Text("You")
                    .font(.vlCaption(11))
                    .foregroundStyle(VLColor.darkTeal)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(VLColor.mutedGold.opacity(0.25))
                    .cornerRadius(8)
            }
            Spacer()
            Text("\(entry.totalXP) XP")
                .font(.vlCaption())
                .foregroundStyle(VLColor.darkTeal)
        }
        .padding(12)
        .background((highlight ? VLColor.mutedGold.opacity(0.12) : VLColor.paperSurface).opacity(0.92))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(VLColor.burgundy.opacity(highlight ? 0.45 : 0.25), lineWidth: 1.2))
        .cornerRadius(12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rank \(rank), \(entry.displayName), \(entry.totalXP) XP")
    }

    private func refresh() async {
        CloudSyncService.shared.bind(auth: auth)
        guard auth.supabaseClient != nil, auth.isSignedIn else { return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            switch scope {
            case .global:
                cloudRows = try await CloudSyncService.shared.fetchGlobalLeaderboard()
            case .friends:
                cloudRows = try await CloudSyncService.shared.fetchFriendsLeaderboard()
            }
        } catch is CancellationError {
            // Pull-to-refresh or a new `.task(id:)` run cancels the previous load; not a user-facing failure.
            return
        } catch {
            loadError = error.localizedDescription
            cloudRows = []
        }
        await CloudSyncService.shared.syncAfterSignIn(modelContext: modelContext, localProfile: profiles.first)
    }
}
