//
//  RootView.swift
//  Venture Local
//

import SwiftData
import SwiftUI
import UIKit

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [ExplorerProfile]
    @State private var exploration: ExplorationCoordinator?

    private var needsOnboarding: Bool {
        guard let p = profiles.first else { return true }
        return !p.onboardingComplete
    }

    var body: some View {
        Group {
            if let exploration {
                if needsOnboarding {
                    OnboardingView(exploration: exploration)
                } else {
                    MainShellView(exploration: exploration)
                }
            } else {
                ProgressView("Preparing your grimoire…")
                    .tint(VLColor.burgundy)
            }
        }
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

    private enum MainTab: Int, Hashable {
        case map = 0
        case journal = 1
        case passport = 2
    }

    @State private var selectedTab: MainTab = .journal

    var body: some View {
        TabView(selection: $selectedTab) {
            ExplorationMapView(exploration: exploration)
                .tabItem { Label("Map", systemImage: "map") }
                .tag(MainTab.map)

            NavigationStack {
                ProgressJournalView(exploration: exploration)
            }
            .tabItem { Label("Journal", systemImage: "book.closed") }
            .tag(MainTab.journal)

            NavigationStack {
                PassportView(exploration: exploration)
            }
            .tabItem { Label("Passport", systemImage: "text.book.closed") }
            .tag(MainTab.passport)
        }
        .tint(VLColor.burgundy)
        .onAppear {
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor(red: 245 / 255, green: 233 / 255, blue: 211 / 255, alpha: 1)
            appearance.stackedLayoutAppearance.normal.iconColor = UIColor(red: 0x2E / 255, green: 0x5E / 255, blue: 0x5A / 255, alpha: 1)
            appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor(red: 0x2E / 255, green: 0x5E / 255, blue: 0x5A / 255, alpha: 1)]
            appearance.stackedLayoutAppearance.selected.iconColor = UIColor(red: 0x7B / 255, green: 0x2D / 255, blue: 0x26 / 255, alpha: 1)
            appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor(red: 0x7B / 255, green: 0x2D / 255, blue: 0x26 / 255, alpha: 1)]
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    }
}
