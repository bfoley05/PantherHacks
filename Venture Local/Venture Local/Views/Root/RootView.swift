//
//  RootView.swift
//  Venture Local
//

import SwiftData
import SwiftUI

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

    var body: some View {
        TabView {
            ExplorationMapView(exploration: exploration)
                .tabItem { Label("Map", systemImage: "map") }

            NavigationStack {
                ProgressJournalView(exploration: exploration)
            }
            .tabItem { Label("Journal", systemImage: "book.closed") }

            NavigationStack {
                PassportView()
            }
            .tabItem { Label("Passport", systemImage: "text.book.closed") }
        }
        .tint(VLColor.burgundy)
    }
}
