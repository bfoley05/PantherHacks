//
//  Venture_LocalApp.swift
//  Venture Local
//
//  Created by Brandon Foley on 4/3/26.
//

import SwiftData
import SwiftUI

@main
struct Venture_LocalApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(ModelContainerProvider.shared)
    }
}
