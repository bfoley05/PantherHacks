//
//  CloudSyncService.swift
//  Venture Local
//
//  Supabase sync: profile, visits backup, friendships, friend recommendations + dismissals, friends leaderboard.
//

import Foundation
import Supabase
import SwiftData

struct CloudLeaderboardEntry: Identifiable, Equatable {
    let id: UUID
    let displayName: String
    let totalXP: Int
    let avatarKindRaw: String?
}

struct CloudFriendshipItem: Identifiable, Equatable {
    let id: UUID
    let otherUserId: UUID
    let otherDisplayName: String
    let status: String
    let isIncoming: Bool
}

struct CloudFriendPlaceRecommendation: Identifiable, Equatable {
    let id: UUID
    let fromUserId: UUID
    let fromDisplayName: String
    let osmId: String
    let cityKey: String
    let placeName: String
    /// Matches ``DiscoveryCategory/rawValue`` from the sharer’s place; empty for older rows.
    let categoryRaw: String
    let latitude: Double
    let longitude: Double
    let recommendedAt: Date
}

struct FriendRecommendationsFetchResult: Equatable {
    let visible: [CloudFriendPlaceRecommendation]
    let totalFromOthersBeforeDismissals: Int
}

@MainActor
final class CloudSyncService {
    static let shared = CloudSyncService()

    private static let legacyHiddenFriendRecommendationIdsKey = "VentureLocalHiddenFriendRecommendationIds"

    private var client: SupabaseClient?
    private var userId: UUID?

    private init() {}

    func bind(auth: AuthSessionController) {
        client = auth.supabaseClient
        userId = auth.session?.user.id
    }

    /// Pull cloud visits + merge higher XP from server, then push local profile.
    func syncAfterSignIn(modelContext: ModelContext, localProfile: ExplorerProfile?) async {
        guard let client, let uid = userId, let profile = localProfile else { return }
        do {
            try await pullVisitsMerge(client: client, userId: uid, modelContext: modelContext)
            try await pullProfileMergeMaxXP(client: client, userId: uid, localProfile: profile, modelContext: modelContext)
            try await pushProfile(client: client, userId: uid, profile: profile)
        } catch {
            // Non-fatal; local app remains usable if schema or network fails.
        }
    }

    func pushProfileIfPossible(profile: ExplorerProfile) async {
        guard let client, let uid = userId else { return }
        do {
            try await pushProfile(client: client, userId: uid, profile: profile)
        } catch {}
    }

    func pushVisitIfPossible(osmId: String, cityKey: String, discoveredAt: Date, explorerNote: String?) async {
        guard let client, let uid = userId else { return }
        do {
            try await upsertVisit(
                client: client,
                userId: uid,
                osmId: osmId,
                cityKey: cityKey,
                discoveredAt: discoveredAt,
                explorerNote: explorerNote
            )
        } catch {}
    }

    func fetchFriendsLeaderboard(limit: Int = 100) async throws -> [CloudLeaderboardEntry] {
        guard let client, let uid = userId else { throw CloudSyncError.notConfigured }
        var ids = try await acceptedFriendUserIds(client: client, userId: uid)
        ids.append(uid)
        let unique = Array(Set(ids))
        guard !unique.isEmpty else { return [] }
        let rows: [ProfileListRow] = try await client.from("profiles")
            .select("id,display_name,avatar_kind_raw,total_xp")
            .in("id", values: unique)
            .order("total_xp", ascending: false)
            .limit(limit)
            .execute()
            .value
        return rows.map(\.asEntry)
    }

    /// Friend recommendations for the Social tab: others’ shares minus rows you dismissed in Supabase.
    func fetchFriendPlaceRecommendations(limit: Int = 80) async throws -> FriendRecommendationsFetchResult {
        guard let client, let uid = userId else { throw CloudSyncError.notConfigured }
        let rows: [FriendPlaceRecRow] = try await client.from("friend_place_recommendations")
            .select()
            .order("recommended_at", ascending: false)
            .limit(limit)
            .execute()
            .value
        let others = rows.filter { $0.fromUserId != uid }
        let friendIds = Array(Set(others.map(\.fromUserId)))
        var names: [UUID: String] = [:]
        if !friendIds.isEmpty {
            let profiles: [ProfileListRow] = try await client.from("profiles")
                .select("id,display_name,avatar_kind_raw,total_xp")
                .in("id", values: friendIds)
                .execute()
                .value
            for p in profiles { names[p.id] = p.displayName }
        }
        let mapped = others.compactMap { row -> CloudFriendPlaceRecommendation? in
            guard let at = Self.parseSupabaseDate(row.recommendedAtRaw) else { return nil }
            return CloudFriendPlaceRecommendation(
                id: row.id,
                fromUserId: row.fromUserId,
                fromDisplayName: names[row.fromUserId] ?? "Friend",
                osmId: row.osmId,
                cityKey: row.cityKey,
                placeName: row.placeName,
                categoryRaw: row.categoryRaw ?? "",
                latitude: row.latitude,
                longitude: row.longitude,
                recommendedAt: at
            )
        }
        let dismissed = try await fetchDismissedFriendRecommendationIds(client: client, userId: uid)
        let visible = mapped.filter { !dismissed.contains($0.id) }
        return FriendRecommendationsFetchResult(visible: visible, totalFromOthersBeforeDismissals: mapped.count)
    }

    /// Records that the current user dismissed friend recommendations (persists across devices).
    func dismissFriendPlaceRecommendations(ids: [UUID]) async throws {
        guard let client, let uid = userId else { throw CloudSyncError.notConfigured }
        let unique = Array(Set(ids))
        guard !unique.isEmpty else { return }
        let existing = try await fetchDismissedFriendRecommendationIds(client: client, userId: uid)
        let newIds = unique.filter { !existing.contains($0) }
        guard !newIds.isEmpty else { return }
        let rows = newIds.map { FriendRecDismissalInsert(userId: uid, recommendationId: $0) }
        try await client.from("friend_recommendation_dismissals").insert(rows).execute()
    }

    /// One-time: push locally hidden recommendation IDs (pre–Supabase dismissals) to the server.
    func migrateLegacyHiddenFriendRecommendationsIfPossible() async {
        guard client != nil, userId != nil else { return }
        guard let data = UserDefaults.standard.data(forKey: Self.legacyHiddenFriendRecommendationIdsKey),
              let arr = try? JSONDecoder().decode([String].self, from: data),
              !arr.isEmpty else { return }
        let uuids = arr.compactMap(UUID.init)
        guard !uuids.isEmpty else {
            UserDefaults.standard.removeObject(forKey: Self.legacyHiddenFriendRecommendationIdsKey)
            return
        }
        do {
            try await dismissFriendPlaceRecommendations(ids: uuids)
            UserDefaults.standard.removeObject(forKey: Self.legacyHiddenFriendRecommendationIdsKey)
        } catch {
            // Keep the legacy key so a later refresh can retry.
        }
    }

    func upsertFriendPlaceRecommendation(
        osmId: String,
        cityKey: String,
        placeName: String,
        categoryRaw: String,
        latitude: Double,
        longitude: Double
    ) async throws {
        guard let client, let uid = userId else { throw CloudSyncError.notConfigured }
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let at = fmt.string(from: Date())
        let row = FriendPlaceRecUpsert(
            fromUserId: uid,
            osmId: osmId,
            cityKey: cityKey,
            placeName: placeName,
            categoryRaw: categoryRaw,
            latitude: latitude,
            longitude: longitude,
            recommendedAt: at
        )
        do {
            try await client.from("friend_place_recommendations").upsert(row, onConflict: "from_user_id,osm_id").execute()
        } catch {
            // Older Supabase projects without `category_raw` (PostgREST schema cache error).
            guard Self.isMissingFriendRecCategoryRawColumnError(error) else { throw error }
            let legacy = FriendPlaceRecUpsertWithoutCategory(
                fromUserId: uid,
                osmId: osmId,
                cityKey: cityKey,
                placeName: placeName,
                latitude: latitude,
                longitude: longitude,
                recommendedAt: at
            )
            try await client.from("friend_place_recommendations").upsert(legacy, onConflict: "from_user_id,osm_id").execute()
        }
    }

    private static func isMissingFriendRecCategoryRawColumnError(_ error: Error) -> Bool {
        let s = error.localizedDescription.lowercased()
        if s.contains("category_raw") || s.contains("category raw") { return true }
        if s.contains("schema cache"), s.contains("friend_place_recommendations") { return true }
        return false
    }

    func loadFriendships() async throws -> [CloudFriendshipItem] {
        guard let client, let uid = userId else { throw CloudSyncError.notConfigured }
        let links: [FriendshipRow] = try await client.from("friendships")
            .select()
            .execute()
            .value
        var otherIds: [UUID] = []
        for row in links {
            let other = row.otherUserId(relativeTo: uid)
            otherIds.append(other)
        }
        let uniqueOthers = Array(Set(otherIds))
        var names: [UUID: String] = [:]
        if !uniqueOthers.isEmpty {
            let profiles: [ProfileListRow] = try await client.from("profiles")
                .select("id,display_name,avatar_kind_raw,total_xp")
                .in("id", values: uniqueOthers)
                .execute()
                .value
            for p in profiles {
                names[p.id] = p.displayName
            }
        }
        return links.map { row in
            let other = row.otherUserId(relativeTo: uid)
            let incoming = row.addresseeId == uid && row.status == "pending"
            return CloudFriendshipItem(
                id: row.id,
                otherUserId: other,
                otherDisplayName: names[other] ?? "Explorer",
                status: row.status,
                isIncoming: incoming
            )
        }
    }

    func sendFriendRequest(toAddresseeId: UUID) async throws {
        guard let client, let uid = userId else { throw CloudSyncError.notConfigured }
        guard toAddresseeId != uid else { throw CloudSyncError.invalidFriendId }
        let row = FriendshipInsert(requesterId: uid, addresseeId: toAddresseeId, status: "pending")
        try await client.from("friendships").insert(row).execute()
    }

    func acceptFriendship(friendshipId: UUID) async throws {
        guard let client else { throw CloudSyncError.notConfigured }
        try await client.from("friendships")
            .update(FriendshipStatusUpdate(status: "accepted"))
            .eq("id", value: friendshipId)
            .execute()
    }

    func deleteFriendship(friendshipId: UUID) async throws {
        guard let client else { throw CloudSyncError.notConfigured }
        try await client.from("friendships")
            .delete()
            .eq("id", value: friendshipId)
            .execute()
    }

    // MARK: - Private

    private func fetchDismissedFriendRecommendationIds(client: SupabaseClient, userId: UUID) async throws -> Set<UUID> {
        let rows: [FriendRecDismissalRow] = try await client.from("friend_recommendation_dismissals")
            .select("recommendation_id")
            .eq("user_id", value: userId)
            .execute()
            .value
        return Set(rows.map(\.recommendationId))
    }

    private func acceptedFriendUserIds(client: SupabaseClient, userId: UUID) async throws -> [UUID] {
        let rows: [FriendshipRow] = try await client.from("friendships")
            .select()
            .eq("status", value: "accepted")
            .execute()
            .value
        return rows.map { $0.otherUserId(relativeTo: userId) }
    }

    private func pullVisitsMerge(client: SupabaseClient, userId: UUID, modelContext: ModelContext) async throws {
        let rows: [VisitRow] = try await client.from("visits")
            .select()
            .eq("user_id", value: userId)
            .execute()
            .value
        for row in rows {
            guard let at = Self.parseSupabaseDate(row.discoveredAtRaw) else { continue }
            let id = row.osmId
            let fetch = FetchDescriptor<DiscoveredPlace>(predicate: #Predicate { $0.osmId == id })
            if let existing = try modelContext.fetch(fetch).first {
                if at < existing.discoveredAt {
                    existing.discoveredAt = at
                }
                if existing.explorerNote == nil, let n = row.explorerNote, !n.isEmpty {
                    existing.explorerNote = n
                }
            } else {
                modelContext.insert(
                    DiscoveredPlace(osmId: row.osmId, discoveredAt: at, cityKey: row.cityKey, explorerNote: row.explorerNote)
                )
            }
        }
        try modelContext.save()
    }

    private func pullProfileMergeMaxXP(
        client: SupabaseClient,
        userId: UUID,
        localProfile: ExplorerProfile,
        modelContext: ModelContext
    ) async throws {
        let rows: [ProfileListRow] = try await client.from("profiles")
            .select("id,display_name,avatar_kind_raw,total_xp")
            .eq("id", value: userId)
            .limit(1)
            .execute()
            .value
        guard let remote = rows.first else { return }
        if remote.totalXP > localProfile.totalXP {
            localProfile.totalXP = remote.totalXP
        }
        try modelContext.save()
    }

    private func pushProfile(client: SupabaseClient, userId: UUID, profile: ExplorerProfile) async throws {
        let row = ProfileUpsert(
            id: userId,
            displayName: profile.displayName,
            avatarKindRaw: profile.avatarKindRaw,
            totalXP: profile.totalXP,
            homeCityKey: profile.homeCityKey,
            homeCityDisplayName: profile.homeCityDisplayName,
            selectedCityKey: profile.selectedCityKey,
            pinnedExplorationCityKey: profile.pinnedExplorationCityKey
        )
        try await client.from("profiles").upsert(row, onConflict: "id").execute()
    }

    private func upsertVisit(
        client: SupabaseClient,
        userId: UUID,
        osmId: String,
        cityKey: String,
        discoveredAt: Date,
        explorerNote: String?
    ) async throws {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let at = fmt.string(from: discoveredAt)
        let row = VisitUpsert(
            userId: userId,
            osmId: osmId,
            cityKey: cityKey,
            discoveredAt: at,
            explorerNote: explorerNote
        )
        try await client.from("visits").upsert(row, onConflict: "user_id,osm_id").execute()
    }

    private static func parseSupabaseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

enum CloudSyncError: LocalizedError {
    case notConfigured
    case invalidFriendId

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Cloud is not available (sign in or check Supabase configuration)."
        case .invalidFriendId: return "You can’t add yourself as a friend."
        }
    }
}

// MARK: - DTOs

private struct ProfileUpsert: Encodable {
    let id: UUID
    let displayName: String
    let avatarKindRaw: String
    let totalXP: Int
    let homeCityKey: String?
    let homeCityDisplayName: String?
    let selectedCityKey: String?
    let pinnedExplorationCityKey: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case avatarKindRaw = "avatar_kind_raw"
        case totalXP = "total_xp"
        case homeCityKey = "home_city_key"
        case homeCityDisplayName = "home_city_display_name"
        case selectedCityKey = "selected_city_key"
        case pinnedExplorationCityKey = "pinned_exploration_city_key"
    }
}

private struct VisitUpsert: Encodable {
    let userId: UUID
    let osmId: String
    let cityKey: String
    let discoveredAt: String
    let explorerNote: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case osmId = "osm_id"
        case cityKey = "city_key"
        case discoveredAt = "discovered_at"
        case explorerNote = "explorer_note"
    }
}

private struct ProfileListRow: Decodable {
    let id: UUID
    let displayName: String
    let totalXP: Int
    let avatarKindRaw: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case totalXP = "total_xp"
        case avatarKindRaw = "avatar_kind_raw"
    }

    var asEntry: CloudLeaderboardEntry {
        CloudLeaderboardEntry(id: id, displayName: displayName, totalXP: totalXP, avatarKindRaw: avatarKindRaw)
    }
}

private struct VisitRow: Decodable {
    let osmId: String
    let cityKey: String
    let discoveredAtRaw: String
    let explorerNote: String?

    enum CodingKeys: String, CodingKey {
        case osmId = "osm_id"
        case cityKey = "city_key"
        case discoveredAtRaw = "discovered_at"
        case explorerNote = "explorer_note"
    }
}

private struct FriendshipRow: Decodable {
    let id: UUID
    let requesterId: UUID
    let addresseeId: UUID
    let status: String

    enum CodingKeys: String, CodingKey {
        case id
        case requesterId = "requester_id"
        case addresseeId = "addressee_id"
        case status
    }

    func otherUserId(relativeTo me: UUID) -> UUID {
        requesterId == me ? addresseeId : requesterId
    }
}

private struct FriendshipInsert: Encodable {
    let requesterId: UUID
    let addresseeId: UUID
    let status: String

    enum CodingKeys: String, CodingKey {
        case requesterId = "requester_id"
        case addresseeId = "addressee_id"
        case status
    }
}

private struct FriendshipStatusUpdate: Encodable {
    let status: String
}

private struct FriendPlaceRecRow: Decodable {
    let id: UUID
    let fromUserId: UUID
    let osmId: String
    let cityKey: String
    let placeName: String
    let categoryRaw: String?
    let latitude: Double
    let longitude: Double
    let recommendedAtRaw: String

    enum CodingKeys: String, CodingKey {
        case id
        case fromUserId = "from_user_id"
        case osmId = "osm_id"
        case cityKey = "city_key"
        case placeName = "place_name"
        case categoryRaw = "category_raw"
        case latitude, longitude
        case recommendedAtRaw = "recommended_at"
    }
}

private struct FriendPlaceRecUpsert: Encodable {
    let fromUserId: UUID
    let osmId: String
    let cityKey: String
    let placeName: String
    let categoryRaw: String
    let latitude: Double
    let longitude: Double
    let recommendedAt: String

    enum CodingKeys: String, CodingKey {
        case fromUserId = "from_user_id"
        case osmId = "osm_id"
        case cityKey = "city_key"
        case placeName = "place_name"
        case categoryRaw = "category_raw"
        case latitude, longitude
        case recommendedAt = "recommended_at"
    }
}

/// Same as ``FriendPlaceRecUpsert`` for databases that have not run `category_raw` migration yet.
private struct FriendPlaceRecUpsertWithoutCategory: Encodable {
    let fromUserId: UUID
    let osmId: String
    let cityKey: String
    let placeName: String
    let latitude: Double
    let longitude: Double
    let recommendedAt: String

    enum CodingKeys: String, CodingKey {
        case fromUserId = "from_user_id"
        case osmId = "osm_id"
        case cityKey = "city_key"
        case placeName = "place_name"
        case latitude, longitude
        case recommendedAt = "recommended_at"
    }
}

private struct FriendRecDismissalInsert: Encodable {
    let userId: UUID
    let recommendationId: UUID

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case recommendationId = "recommendation_id"
    }
}

private struct FriendRecDismissalRow: Decodable {
    let recommendationId: UUID

    enum CodingKeys: String, CodingKey {
        case recommendationId = "recommendation_id"
    }
}
