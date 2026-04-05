//
//  RootView.swift
//  Venture Local
//

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

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
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
        .preferredColorScheme(theme.useDarkVintagePalette ? .dark : .light)
        .environmentObject(theme)
        .onAppear {
            if exploration == nil {
                exploration = ExplorationCoordinator(modelContext: modelContext)
            }
            try? exploration?.fetchOrCreateProfile()
        }
    }
}

struct MainShellView: View {
    @Bindable var exploration: ExplorationCoordinator
    @EnvironmentObject private var theme: ThemeSettings

    private enum MainTab: Int, Hashable {
        case badges = 0
        case map = 1
        case journal = 2
        case passport = 3
        case leaderboard = 4
    }

    @State private var selectedTab: MainTab = .journal

    var body: some View {
        let _ = theme.useDarkVintagePalette
        return TabView(selection: $selectedTab) {
            NavigationStack {
                BadgesView(exploration: exploration)
            }
            .tabItem { Label("Badges", systemImage: "rosette") }
            .tag(MainTab.badges)

            ExplorationMapView(exploration: exploration)
                .tabItem { Label("Map", systemImage: "map") }
                .tag(MainTab.map)

            NavigationStack {
                ProgressJournalView(
                    exploration: exploration,
                    onSelectBadgesTab: { selectedTab = .badges },
                    onSelectJournalTab: { selectedTab = .journal }
                )
            }
            .tabItem { Label("Journal", systemImage: "book.closed") }
            .tag(MainTab.journal)

            NavigationStack {
                PassportView(exploration: exploration)
            }
            .tabItem { Label("Passport", systemImage: "text.book.closed") }
            .tag(MainTab.passport)

            NavigationStack {
                LeaderboardView()
            }
            .tabItem { Label("Leaderboard", systemImage: "list.number") }
            .tag(MainTab.leaderboard)
        }
        .tint(VLColor.burgundy)
        .onAppear { configureTabBarAppearance() }
        .onChange(of: theme.useDarkVintagePalette) { _, _ in configureTabBarAppearance() }
        .environment(\.explorationCoordinator, exploration)
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
        appearance.stackedLayoutAppearance.normal.iconColor = normalColor
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: normalColor]
        appearance.stackedLayoutAppearance.selected.iconColor = selectedColor
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: selectedColor]
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}
