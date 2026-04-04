//
//  PTAppApp.swift
//  PTApp
//
//  Created by Brandon Foley on 4/3/26.
//

import SwiftUI

@main
struct PTAppApp: App {
    @StateObject private var appState = AppState()
    @AppStorage("stride_appearance") private var appearance = "dark"

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(appState)
                .preferredColorScheme(appearance == "light" ? .light : .dark)
        }
    }
}
