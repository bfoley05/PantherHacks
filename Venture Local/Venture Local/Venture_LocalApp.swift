//
//  Venture_LocalApp.swift
//  Venture Local
//
//  Created by Brandon Foley on 4/3/26.
//

import SwiftData
import SwiftUI
import Supabase

@main
struct Venture_LocalApp: App {
    @StateObject private var authController: AuthSessionController
    @StateObject private var persistence: PerUserPersistenceController

    init() {
        JournalLedgerNotificationService.requestAuthorizationIfNeeded()
        let client = SupabaseConfiguration.makeClient()
        _authController = StateObject(wrappedValue: AuthSessionController(client: client))
        let initialKey = UserLocalStore.storeKey(
            supabaseUserIdString: client?.auth.currentSession?.user.id.uuidString
        )
        _persistence = StateObject(wrappedValue: PerUserPersistenceController(initialStoreKey: initialKey))
    }

    var body: some Scene {
        WindowGroup {
            PerUserStoreRootView()
                .environmentObject(authController)
                .environmentObject(persistence)
        }
    }
}

/// Binds SwiftData to the active Supabase account; `.id` forces a fresh view tree when the store swaps.
private struct PerUserStoreRootView: View {
    @EnvironmentObject private var auth: AuthSessionController
    @EnvironmentObject private var persistence: PerUserPersistenceController

    var body: some View {
        ContentView()
            .modelContainer(persistence.container)
            .id(persistence.storeKey)
            .onAppear { persistence.syncStoreKey(with: auth) }
            .onChange(of: auth.isBootstrapping) { _, bootstrapping in
                if !bootstrapping { persistence.syncStoreKey(with: auth) }
            }
            .onChange(of: auth.currentSupabaseUserId) { _, _ in
                persistence.syncStoreKey(with: auth)
            }
    }
}
