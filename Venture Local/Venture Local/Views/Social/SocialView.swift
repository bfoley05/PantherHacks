//
//  SocialView.swift
//  Venture Local
//

import SwiftData
import SwiftUI

struct SocialView: View {
    @EnvironmentObject private var theme: ThemeSettings
    @EnvironmentObject private var auth: AuthSessionController
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var tabRouter: MainShellTabRouter
    @Query private var profiles: [ExplorerProfile]

    @State private var recommendations: [CloudFriendPlaceRecommendation] = []
    @State private var cloudRows: [CloudLeaderboardEntry] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var hiddenRecommendationIds: Set<String> = HiddenFriendRecommendationsStore.loadAll()

    private var myUserId: UUID? {
        guard let s = auth.currentSupabaseUserId else { return nil }
        return UUID(uuidString: s)
    }

    private var visibleRecommendations: [CloudFriendPlaceRecommendation] {
        recommendations.filter { !hiddenRecommendationIds.contains($0.id.uuidString) }
    }

    var body: some View {
        let _ = theme.useDarkVintagePalette
        ZStack {
            PaperBackground()
            List {
                Section {
                    Text("Social")
                        .font(.vlTitle(24))
                        .foregroundStyle(VLColor.burgundy)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .textCase(nil)

                recommendationsSection

                leaderboardSection
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable { await refresh() }
        }
        .toolbar(.hidden, for: .navigationBar)
        .containerBackground(theme.paperBackdropColor, for: .navigation)
        .task { await refresh() }
        .onAppear {
            hiddenRecommendationIds = HiddenFriendRecommendationsStore.loadAll()
        }
    }

    @ViewBuilder
    private var recommendationsSection: some View {
        Section {
            if !auth.isSignedIn || auth.configurationMissing {
                Text("Sign in to see places your friends recommend from the map.")
                    .font(.vlCaption(13))
                    .foregroundStyle(VLColor.darkTeal)
                    .listRowBackground(VLColor.paperSurface.opacity(0.92))
            } else if isLoading && recommendations.isEmpty {
                ProgressView()
                    .tint(VLColor.burgundy)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                    .listRowBackground(VLColor.paperSurface.opacity(0.92))
            } else if recommendations.isEmpty {
                Text("When friends share a place from the map, it appears here. Tap a row to open it on the Map tab.")
                    .font(.vlCaption(13))
                    .foregroundStyle(VLColor.darkTeal)
                    .listRowBackground(VLColor.paperSurface.opacity(0.92))
            } else if visibleRecommendations.isEmpty {
                Text("You’ve removed these from your list. Pull to refresh when friends share something new.")
                    .font(.vlCaption(13))
                    .foregroundStyle(VLColor.darkTeal)
                    .listRowBackground(VLColor.paperSurface.opacity(0.92))
            } else {
                ForEach(visibleRecommendations) { rec in
                    Button {
                        tabRouter.focusPlaceOnMap(
                            MainShellTabRouter.PendingMapPlace(
                                osmId: rec.osmId,
                                cityKey: rec.cityKey,
                                name: rec.placeName,
                                latitude: rec.latitude,
                                longitude: rec.longitude
                            )
                        )
                    } label: {
                        recommendationRow(rec)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(VLColor.paperSurface.opacity(0.92))
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            hideRecommendation(rec.id)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
            }
        } header: {
            HStack(alignment: .center, spacing: 8) {
                Text("Recommended by friends")
                    .font(.vlTitle(20))
                    .foregroundStyle(VLColor.burgundy)
                Spacer(minLength: 8)
                if auth.isSignedIn, !auth.configurationMissing, !visibleRecommendations.isEmpty {
                    Button("Clear all") {
                        clearAllVisibleRecommendations()
                    }
                    .font(.vlCaption(12).weight(.semibold))
                    .foregroundStyle(VLColor.burgundy)
                }
            }
            .textCase(nil)
            .padding(.top, 4)
        }
        .textCase(nil)
    }

    @ViewBuilder
    private var leaderboardSection: some View {
        Section {
            if auth.configurationMissing {
                Text("Supabase isn’t configured; showing this device only.")
                    .font(.vlBody(14))
                    .foregroundStyle(VLColor.dustyBlue)
                    .listRowBackground(VLColor.paperSurface.opacity(0.92))
                localFallbackRows
            } else if !auth.isSignedIn {
                Text("Sign in to see friend recommendations and a friends-only leaderboard.")
                    .font(.vlBody(14))
                    .foregroundStyle(VLColor.dustyBlue)
                    .listRowBackground(VLColor.paperSurface.opacity(0.92))
                localFallbackRows
            } else {
                if let loadError {
                    Text(loadError)
                        .font(.vlCaption(13))
                        .foregroundStyle(VLColor.burgundy)
                        .listRowBackground(VLColor.paperSurface.opacity(0.92))
                }
                if isLoading && cloudRows.isEmpty && recommendations.isEmpty {
                    ProgressView()
                        .tint(VLColor.burgundy)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .listRowBackground(VLColor.paperSurface.opacity(0.92))
                } else if cloudRows.isEmpty {
                    Text("No friends yet — add explorers from Profile → Friends.")
                        .font(.vlBody(14))
                        .foregroundStyle(VLColor.darkTeal)
                        .listRowBackground(VLColor.paperSurface.opacity(0.92))
                } else {
                    ForEach(Array(cloudRows.enumerated()), id: \.element.id) { idx, row in
                        let highlight = row.id == myUserId
                        leaderboardRow(rank: idx + 1, entry: row, highlight: highlight)
                            .listRowBackground((highlight ? VLColor.mutedGold.opacity(0.12) : VLColor.paperSurface).opacity(0.92))
                    }
                }
            }
        } header: {
            Text("Friends leaderboard")
                .font(.vlTitle(20))
                .foregroundStyle(VLColor.burgundy)
                .textCase(nil)
                .padding(.top, 8)
        }
        .textCase(nil)
    }

    @ViewBuilder
    private var localFallbackRows: some View {
        if profiles.isEmpty {
            Text("No explorers yet.")
                .font(.vlBody())
                .foregroundStyle(VLColor.darkTeal)
                .listRowBackground(VLColor.paperSurface.opacity(0.92))
        } else {
            let sorted = profiles.sorted { $0.totalXP > $1.totalXP }
            ForEach(Array(sorted.enumerated()), id: \.element.persistentModelID) { idx, profile in
                localDeviceRow(rank: idx + 1, profile: profile)
                    .listRowBackground(VLColor.paperSurface.opacity(0.92))
            }
        }
    }

    private func recommendationRow(_ rec: CloudFriendPlaceRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(rec.placeName)
                .font(.vlBody(16).weight(.semibold))
                .foregroundStyle(VLColor.ink)
                .multilineTextAlignment(.leading)
            Text("From \(rec.fromDisplayName) · \(rec.recommendedAt.formatted(date: .abbreviated, time: .omitted))")
                .font(.vlCaption(12))
                .foregroundStyle(VLColor.darkTeal)
            Text("Open on map")
                .font(.vlCaption(11).weight(.medium))
                .foregroundStyle(VLColor.mutedGold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Switches to the map and opens this place.")
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
        .padding(.vertical, 4)
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
        .padding(.vertical, 4)
    }

    private func hideRecommendation(_ id: UUID) {
        HiddenFriendRecommendationsStore.hide(id: id)
        hiddenRecommendationIds = HiddenFriendRecommendationsStore.loadAll()
    }

    private func clearAllVisibleRecommendations() {
        HiddenFriendRecommendationsStore.hideAll(ids: visibleRecommendations.map(\.id))
        hiddenRecommendationIds = HiddenFriendRecommendationsStore.loadAll()
    }

    private func refresh() async {
        CloudSyncService.shared.bind(auth: auth)
        guard auth.supabaseClient != nil, auth.isSignedIn else {
            recommendations = []
            cloudRows = []
            return
        }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            recommendations = try await CloudSyncService.shared.fetchFriendPlaceRecommendations()
            cloudRows = try await CloudSyncService.shared.fetchFriendsLeaderboard()
        } catch is CancellationError {
            return
        } catch {
            loadError = error.localizedDescription
            recommendations = []
            cloudRows = []
        }
        await CloudSyncService.shared.syncAfterSignIn(modelContext: modelContext, localProfile: profiles.first)
    }
}
