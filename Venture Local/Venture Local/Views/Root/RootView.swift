//
//  RootView.swift
//  Venture Local
//

import Combine
import SwiftData
import SwiftUI
import UIKit

private struct ExplorationCoordinatorKey: EnvironmentKey {
    static let defaultValue: ExplorationCoordinator? = nil
}

extension EnvironmentValues {
    var explorationCoordinator: ExplorationCoordinator? {
        get { self[ExplorationCoordinatorKey.self] }
        set { self[ExplorationCoordinatorKey.self] = newValue }
    }
}

/// Top level stays free of `@Query` so when signed out no `ExplorerProfile` observation is tied to the previous user’s store
/// (avoids SwiftData fatal errors when `ModelContainer` swaps after sign-out).
struct RootView: View {
    @EnvironmentObject private var auth: AuthSessionController
    @EnvironmentObject private var persistence: PerUserPersistenceController
    @ObservedObject private var theme = ThemeSettings.shared

    var body: some View {
        let _ = theme.useDarkVintagePalette
        return Group {
            if auth.isBootstrapping {
                ZStack {
                    PaperBackground()
                    ProgressView("Loading…")
                        .tint(VLColor.burgundy)
                }
            } else if !auth.isSignedIn {
                AuthLoginView()
            } else if !persistence.isStoreAligned(with: auth) {
                ZStack {
                    PaperBackground()
                    ProgressView("Opening your journal…")
                        .tint(VLColor.burgundy)
                }
            } else {
                RootSignedInContent()
            }
        }
        .preferredColorScheme(theme.useDarkVintagePalette ? .dark : .light)
        .environmentObject(theme)
    }
}

// MARK: - Signed-in subtree (SwiftData queries only exist while session is active)

private struct RootSignedInContent: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var auth: AuthSessionController
    @Query private var profiles: [ExplorerProfile]
    @State private var exploration: ExplorationCoordinator?
    @ObservedObject private var theme = ThemeSettings.shared

    private var needsOnboarding: Bool {
        guard let p = profiles.first else { return true }
        return !p.onboardingComplete
    }

    var body: some View {
        let _ = theme.useDarkVintagePalette
        return Group {
            if let exploration {
                if needsOnboarding {
                    OnboardingView(exploration: exploration)
                } else {
                    MainShellView(exploration: exploration)
                }
            } else {
                ZStack {
                    PaperBackground()
                    ProgressView("Preparing your grimoire…")
                        .tint(VLColor.burgundy)
                }
            }
        }
        .onAppear {
            if exploration == nil {
                exploration = ExplorationCoordinator(modelContext: modelContext)
            }
            try? exploration?.fetchOrCreateProfile()
            syncSupabaseUserToProfile()
            CloudSyncService.shared.bind(auth: auth)
            Task { await CloudSyncService.shared.syncAfterSignIn(modelContext: modelContext, localProfile: profiles.first) }
        }
        .onChange(of: auth.isSignedIn) { _, signedIn in
            CloudSyncService.shared.bind(auth: auth)
            if signedIn {
                syncSupabaseUserToProfile()
                Task { await CloudSyncService.shared.syncAfterSignIn(modelContext: modelContext, localProfile: profiles.first) }
            }
        }
    }

    private func syncSupabaseUserToProfile() {
        guard auth.isSignedIn, let uid = auth.currentSupabaseUserId, let p = profiles.first else { return }
        if p.supabaseUserId != uid {
            p.supabaseUserId = uid
            try? modelContext.save()
        }
    }
}

struct MainShellView: View {
    @Bindable var exploration: ExplorationCoordinator
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var auth: AuthSessionController
    @EnvironmentObject private var theme: ThemeSettings
    @Query private var profiles: [ExplorerProfile]

    @StateObject private var tabRouter = MainShellTabRouter()
    @StateObject private var toastController = InAppToastController()

    var body: some View {
        let _ = theme.useDarkVintagePalette
        return ZStack(alignment: .topLeading) {
            TabView(selection: $tabRouter.selectedTab) {
            NavigationStack {
                BadgesView(exploration: exploration)
            }
            .tabItem { Label("Badges", systemImage: "rosette") }
            .tag(MainShellTabRouter.Tab.badges)

            ExplorationMapView(exploration: exploration)
                .environmentObject(tabRouter)
                .tabItem { Label("Map", systemImage: "map") }
                .tag(MainShellTabRouter.Tab.map)

            NavigationStack {
                ProgressJournalView(
                    exploration: exploration,
                    onSelectBadgesTab: { tabRouter.selectedTab = .badges },
                    onSelectJournalTab: { tabRouter.selectedTab = .journal }
                )
            }
            .tabItem { Label("Journal", systemImage: "book.closed") }
            .tag(MainShellTabRouter.Tab.journal)

            NavigationStack {
                PassportView(exploration: exploration)
            }
            .tabItem { Label("Passport", systemImage: "text.book.closed") }
            .tag(MainShellTabRouter.Tab.passport)

            NavigationStack {
                SocialView(tabRouter: tabRouter)
            }
            .tabItem { Label("Social", systemImage: "person.2.fill") }
            .tag(MainShellTabRouter.Tab.social)
            }
            // Bind tint + bar chrome to `theme` so toggling palette updates immediately (not only `VLColor`’s static reader).
            .tint(theme.tabBarSelectedAccent)
            .toolbarBackground(.visible, for: .tabBar)
            .toolbarBackground(theme.paperBackdropColor, for: .tabBar)
            .toolbarColorScheme(theme.useDarkVintagePalette ? .dark : .light, for: .tabBar)
            .id(theme.useDarkVintagePalette)
            .onAppear {
                configureTabBarAppearance()
                CloudSyncService.shared.bind(auth: auth)
                exploration.startTracking()
                try? exploration.loadPersistedPolylinesIntoMap()
                Task { await CloudSyncService.shared.syncAfterSignIn(modelContext: modelContext, localProfile: profiles.first) }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    exploration.startTracking()
                }
            }
            .onChange(of: tabRouter.selectedTab) { _, tab in
                if tab == .journal {
                    exploration.refreshNearbyClaimablePOIs()
                }
            }
            .onChange(of: theme.useDarkVintagePalette) { _, _ in
                configureTabBarAppearance()
            }
            .environment(\.explorationCoordinator, exploration)
            .environmentObject(tabRouter)

            if let toast = toastController.active {
                InAppToastBannerView(toast: toast)
                    .padding(.leading, 12)
                    .safeAreaPadding(.top, 6)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        )
                    )
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: toastController.active?.id)
        .onReceive(NotificationCenter.default.publisher(for: .ventureLocalInAppToast)) { note in
            toastController.consume(userInfo: note.userInfo)
        }
        .task {
            await FriendRequestLedgerSync.sync(modelContext: modelContext, auth: auth)
        }
        .onChange(of: auth.currentSupabaseUserId) { _, _ in
            Task { await FriendRequestLedgerSync.sync(modelContext: modelContext, auth: auth) }
        }
    }

    private func configureTabBarAppearance() {
        let isDark = theme.useDarkVintagePalette
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = isDark
            ? UIColor(red: 0x09 / 255, green: 0x0E / 255, blue: 0x0B / 255, alpha: 1)
            : UIColor(red: 245 / 255, green: 233 / 255, blue: 211 / 255, alpha: 1)
        let normalColor = isDark
            ? UIColor(red: 0xA5 / 255, green: 0xB5 / 255, blue: 0xA3 / 255, alpha: 1)
            : UIColor(red: 0x2E / 255, green: 0x5E / 255, blue: 0x5A / 255, alpha: 1)
        let selectedColor = isDark
            ? UIColor(red: 0x3A / 255, green: 0xB8 / 255, blue: 0x58 / 255, alpha: 1)
            : UIColor(red: 0x7B / 255, green: 0x2D / 255, blue: 0x26 / 255, alpha: 1)

        func style(_ item: UITabBarItemAppearance) {
            item.normal.iconColor = normalColor
            item.normal.titleTextAttributes = [.foregroundColor: normalColor]
            item.selected.iconColor = selectedColor
            item.selected.titleTextAttributes = [.foregroundColor: selectedColor]
        }
        style(appearance.stackedLayoutAppearance)
        style(appearance.inlineLayoutAppearance)
        if #available(iOS 18.0, *) {
            style(appearance.compactInlineLayoutAppearance)
        }

        let tabBar = UITabBar.appearance()
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
        tabBar.tintColor = selectedColor
        tabBar.unselectedItemTintColor = normalColor
    }
}
