//
//  LeaderboardView.swift
//  Venture Local
//

import SwiftData
import SwiftUI

struct LeaderboardView: View {
    @EnvironmentObject private var theme: ThemeSettings
    @Query(sort: \ExplorerProfile.totalXP, order: .reverse) private var profiles: [ExplorerProfile]

    var body: some View {
        let _ = theme.useDarkVintagePalette
        return ZStack {
            PaperBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Leaderboard")
                        .font(.vlTitle(24))
                        .foregroundStyle(VLColor.burgundy)
                    Text("Local device ranking for now. Cloud/community rankings can plug in here next.")
                        .font(.vlBody(14))
                        .foregroundStyle(VLColor.dustyBlue)

                    if profiles.isEmpty {
                        Text("No explorers yet.")
                            .font(.vlBody())
                            .foregroundStyle(VLColor.darkTeal)
                    } else {
                        ForEach(Array(profiles.enumerated()), id: \.element.persistentModelID) { idx, profile in
                            HStack {
                                Text("#\(idx + 1)")
                                    .font(.vlCaption())
                                    .foregroundStyle(VLColor.mutedGold)
                                    .frame(width: 34, alignment: .leading)
                                Text(profile.displayName)
                                    .font(.vlBody(16))
                                    .foregroundStyle(VLColor.ink)
                                Spacer()
                                Text("\(profile.totalXP) XP")
                                    .font(.vlCaption())
                                    .foregroundStyle(VLColor.darkTeal)
                            }
                            .padding(12)
                            .background(VLColor.paperSurface.opacity(0.92))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(VLColor.burgundy.opacity(0.25), lineWidth: 1.2))
                            .cornerRadius(12)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Rank \(idx + 1), \(profile.displayName), \(profile.totalXP) XP")
                        }
                    }
                }
                .padding(16)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Leaderboard")
        .vintageNavigationChrome()
    }
}
