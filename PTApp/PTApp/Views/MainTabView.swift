//
//  MainTabView.swift
//  PTApp
//

import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem {
                    Label("Today", systemImage: "sun.max.fill")
                }

            MoveView()
                .tabItem {
                    Label("Move", systemImage: "camera.viewfinder")
                }

            RecoveryTimelineView()
                .tabItem {
                    Label("Timeline", systemImage: "chart.line.uptrend.xyaxis")
                }

            BodyMapView()
                .tabItem {
                    Label("Body", systemImage: "figure.stand")
                }

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle")
                }
        }
        .tint(StrideTheme.accent)
    }
}
