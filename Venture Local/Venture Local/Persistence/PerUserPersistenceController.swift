//
//  PerUserPersistenceController.swift
//  Venture Local
//
//  One SwiftData store per Supabase user so journal, passport, badges, XP, and map cache stay isolated.
//

import Combine
import Foundation
import SwiftData

private enum PerUserStoreDefaults {
    static let legacyMigratedKey = "VentureLocalLegacySwiftDataMigrated"
}

/// Disk layout: Application Support / VentureLocal / PerUserStores / <userId|unsigned> / explorer.store
enum UserLocalStore {
    static let unsignedKey = "unsigned"

    static func storeKey(supabaseUserIdString: String?) -> String {
        guard let s = supabaseUserIdString?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else {
            return unsignedKey
        }
        return s.lowercased()
    }

    static func perUserDirectoryURL(forStoreKey key: String) throws -> URL {
        let fm = FileManager.default
        let appSupport = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let root = appSupport.appendingPathComponent("VentureLocal/PerUserStores", isDirectory: true)
        return root.appendingPathComponent(key, isDirectory: true)
    }

    static func storeFileURL(forStoreKey key: String) throws -> URL {
        try perUserDirectoryURL(forStoreKey: key).appendingPathComponent("explorer.store")
    }

    static func storeExistsOnDisk(forStoreKey key: String) -> Bool {
        guard let url = try? storeFileURL(forStoreKey: key) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Remove all SwiftData files for this logical user (entire subdirectory).
    static func wipePerUserDirectory(key: String) {
        guard let dir = try? perUserDirectoryURL(forStoreKey: key) else { return }
        try? FileManager.default.removeItem(at: dir)
    }

    /// Copy explorer.store (+ wal/shm) from one user bucket to another if destination is missing.
    static func copyStoreIfDestinationMissing(from srcKey: String, to destKey: String) {
        guard let srcMain = try? storeFileURL(forStoreKey: srcKey),
              let destMain = try? storeFileURL(forStoreKey: destKey) else { return }
        guard FileManager.default.fileExists(atPath: srcMain.path),
              !FileManager.default.fileExists(atPath: destMain.path) else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: destMain.deletingLastPathComponent(), withIntermediateDirectories: true)
        copySQLiteBundle(from: srcMain, to: destMain)
    }

    /// One-time: move pre-per-user default.store into the appropriate first bucket, then mark complete.
    static func migrateLegacySharedStoreIfNeeded(targetStoreKey: String) {
        guard !UserDefaults.standard.bool(forKey: PerUserStoreDefaults.legacyMigratedKey) else { return }
        defer { UserDefaults.standard.set(true, forKey: PerUserStoreDefaults.legacyMigratedKey) }

        let fm = FileManager.default
        guard let appSupport = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
            return
        }
        guard let destMain = try? storeFileURL(forStoreKey: targetStoreKey) else { return }
        if fm.fileExists(atPath: destMain.path) { return }

        let candidates = [
            appSupport.appendingPathComponent("default.store"),
            appSupport.appendingPathComponent("Default.store"),
        ]
        for oldMain in candidates where fm.fileExists(atPath: oldMain.path) {
            try? fm.createDirectory(at: destMain.deletingLastPathComponent(), withIntermediateDirectories: true)
            copySQLiteBundle(from: oldMain, to: destMain)
            removeSQLiteBundle(at: oldMain)
            return
        }
    }

    private static func copySQLiteBundle(from oldMain: URL, to newMain: URL) {
        let fm = FileManager.default
        for suffix in ["", "-shm", "-wal"] {
            let oldURL = URL(fileURLWithPath: oldMain.path + suffix)
            let newURL = URL(fileURLWithPath: newMain.path + suffix)
            guard fm.fileExists(atPath: oldURL.path) else { continue }
            if fm.fileExists(atPath: newURL.path) { try? fm.removeItem(at: newURL) }
            try? fm.copyItem(at: oldURL, to: newURL)
        }
    }

    private static func removeSQLiteBundle(at main: URL) {
        let fm = FileManager.default
        for suffix in ["", "-shm", "-wal"] {
            let u = URL(fileURLWithPath: main.path + suffix)
            if fm.fileExists(atPath: u.path) { try? fm.removeItem(at: u) }
        }
    }

    static var modelSchema: Schema {
        Schema([
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
            CityLocalsBaseline.self,
        ])
    }

    /// `NSCocoaErrorDomain` 134110 = persistent store migration failed (e.g. new non-optional field on existing rows).
    private static let migrationFailedCocoaCode = 134110

    static func makeContainer(storeKey: String) throws -> ModelContainer {
        let url = try storeFileURL(forStoreKey: storeKey)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let config = ModelConfiguration(url: url)
        func open() throws -> ModelContainer {
            try ModelContainer(for: modelSchema, configurations: [config])
        }
        do {
            return try open()
        } catch {
            let ns = error as NSError
            if ns.domain == NSCocoaErrorDomain, ns.code == migrationFailedCocoaCode {
                wipePerUserDirectory(key: storeKey)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                return try open()
            }
            throw error
        }
    }

    static func makePreviewContainer() -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: modelSchema, configurations: [config])
        } catch {
            fatalError("Preview ModelContainer failed: \(error)")
        }
    }
}

@MainActor
final class PerUserPersistenceController: ObservableObject {
    @Published private(set) var container: ModelContainer
    @Published private(set) var storeKey: String

    /// Latest requested sync; older scheduled tasks no-op so rapid auth changes don’t stack conflicting swaps.
    private var syncRequestID = 0

    init(initialStoreKey: String) {
        UserLocalStore.migrateLegacySharedStoreIfNeeded(targetStoreKey: initialStoreKey)
        storeKey = initialStoreKey
        do {
            container = try UserLocalStore.makeContainer(storeKey: initialStoreKey)
        } catch {
            fatalError("SwiftData per-user container failed: \(error)")
        }
    }

    func expectedStoreKey(for auth: AuthSessionController) -> String {
        UserLocalStore.storeKey(supabaseUserIdString: auth.currentSupabaseUserId)
    }

    /// `true` when the open SwiftData store matches the current auth session.
    func isStoreAligned(with auth: AuthSessionController) -> Bool {
        if auth.isBootstrapping { return false }
        return storeKey == expectedStoreKey(for: auth)
    }

    /// Schedules aligning the on-disk store with the current auth session (never runs heavy work synchronously from `onChange` / `onAppear`).
    func syncStoreKey(with auth: AuthSessionController) {
        syncRequestID += 1
        let requestID = syncRequestID
        Task { @MainActor in
            await Task.yield()
            guard requestID == self.syncRequestID else { return }
            self.applySyncStoreKeyIfNeeded(with: auth, requestID: requestID)
        }
    }

    private func applySyncStoreKeyIfNeeded(with auth: AuthSessionController, requestID: Int) {
        guard requestID == syncRequestID else { return }
        if auth.isBootstrapping { return }
        let newKey = UserLocalStore.storeKey(supabaseUserIdString: auth.currentSupabaseUserId)
        guard newKey != storeKey else { return }

        let oldKey = storeKey

        // Leaving a signed-in account for the login screen: never keep the previous user’s data in `unsigned`.
        if newKey == UserLocalStore.unsignedKey, oldKey != UserLocalStore.unsignedKey {
            UserLocalStore.wipePerUserDirectory(key: UserLocalStore.unsignedKey)
        }

        // First time this Supabase id gets a local store: adopt any data that only lived under `unsigned`
        // (e.g. right after legacy migration or onboarding before the session id was stable).
        if oldKey == UserLocalStore.unsignedKey, newKey != UserLocalStore.unsignedKey,
           !UserLocalStore.storeExistsOnDisk(forStoreKey: newKey)
        {
            UserLocalStore.copyStoreIfDestinationMissing(from: UserLocalStore.unsignedKey, to: newKey)
            UserLocalStore.wipePerUserDirectory(key: UserLocalStore.unsignedKey)
        }

        guard requestID == syncRequestID else { return }

        do {
            let newContainer = try UserLocalStore.makeContainer(storeKey: newKey)
            guard requestID == syncRequestID else { return }
            container = newContainer
            storeKey = newKey
        } catch {
            // Keep previous container; next auth change will retry.
        }
    }
}
