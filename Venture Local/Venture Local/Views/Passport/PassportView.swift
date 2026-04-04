//
//  PassportView.swift
//  Venture Local
//

import SwiftData
import SwiftUI

struct PassportView: View {
    @Query(sort: \StampRecord.stampedAt, order: .reverse) private var stamps: [StampRecord]

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Passport")
                            .font(.vlTitle(24))
                            .foregroundStyle(VLColor.burgundy)
                        Spacer()
                    }

                    Text("Partner stamps you collect appear here. Add partner OSM ids in Resources/partners.json.")
                        .font(.vlBody(14))
                        .foregroundStyle(VLColor.dustyBlue)

                    let grouped = Dictionary(grouping: stamps, by: \.cityKey)
                    if grouped.isEmpty {
                        Text("No stamps yet.")
                            .font(.vlBody())
                            .foregroundStyle(VLColor.darkTeal)
                    } else {
                        ForEach(grouped.keys.sorted(), id: \.self) { key in
                            cityPage(cityKey: key, rows: grouped[key] ?? [])
                        }
                    }
                }
                .padding(20)
            }
        }
    }

    private func cityPage(cityKey: String, rows: [StampRecord]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(cityKey.replacingOccurrences(of: "__", with: ", "))
                .font(.vlTitle(18))
                .foregroundStyle(VLColor.darkTeal)
            Text("\(rows.count) stamps")
                .font(.vlCaption())
                .foregroundStyle(VLColor.dustyBlue)

            let columns = [GridItem(.adaptive(minimum: 64), spacing: 10)]
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(rows, id: \.id) { s in
                    VStack(spacing: 4) {
                        Image(systemName: "seal.fill")
                            .font(.title2)
                            .foregroundStyle(VLColor.mutedGold)
                        Text(s.stampedAt.formatted(date: .numeric, time: .omitted))
                            .font(.vlCaption(9))
                            .foregroundStyle(VLColor.dustyBlue)
                            .lineLimit(1)
                    }
                    .frame(height: 72)
                    .frame(maxWidth: .infinity)
                    .background(VLColor.cream)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(VLColor.burgundy.opacity(0.25), lineWidth: 1))
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(VLColor.cream.opacity(0.65))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(VLColor.mutedGold.opacity(0.5), lineWidth: 2))
        .cornerRadius(16)
    }
}
