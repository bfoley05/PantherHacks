//
//  HiddenFriendRecommendationsStore.swift
//  Venture Local
//
//  Locally hides friend recommendations on the Social tab (RLS only lets authors delete server rows).
//

import Foundation

enum HiddenFriendRecommendationsStore {
    private static let key = "VentureLocalHiddenFriendRecommendationIds"

    static func loadAll() -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: key),
              let arr = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(arr)
    }

    private static func save(_ set: Set<String>) {
        let arr = Array(set)
        guard let data = try? JSONEncoder().encode(arr) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func hide(id: UUID) {
        var s = loadAll()
        s.insert(id.uuidString)
        save(s)
    }

    static func hideAll(ids: [UUID]) {
        var s = loadAll()
        for id in ids { s.insert(id.uuidString) }
        save(s)
    }
}
