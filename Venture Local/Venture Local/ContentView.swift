//
//  ContentView.swift
//  Venture Local
//
//  Created by Brandon Foley on 4/3/26.
//

import SwiftData
import SwiftUI

struct ContentView: View {
    var body: some View {
        RootView()
    }
}

#Preview {
    let auth = AuthSessionController(client: nil)
    return ContentView()
        .environmentObject(auth)
        .environmentObject(PerUserPersistenceController(initialStoreKey: UserLocalStore.unsignedKey))
        .modelContainer(UserLocalStore.makePreviewContainer())
}
