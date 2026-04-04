//
//  POIDetailView.swift
//  Venture Local
//

import CoreLocation
import SwiftData
import SwiftUI

struct POIDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let poi: CachedPOI
    @Bindable var exploration: ExplorationCoordinator

    @Query private var discoveries: [DiscoveredPlace]
    @State private var note: String = ""
    @State private var stampMessage: String?

    private var discovered: DiscoveredPlace? {
        discoveries.first { $0.osmId == poi.osmId }
    }

    private var distanceMeters: Double? {
        guard let loc = exploration.lastUserLocation else { return nil }
        let there = CLLocationCoordinate2D(latitude: poi.latitude, longitude: poi.longitude)
        return GeoMath.distanceMeters(loc.coordinate, there)
    }

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Spacer()
                        Button("Close") { dismiss() }
                            .foregroundStyle(VLColor.darkTeal)
                    }

                    Text(poi.name)
                        .font(.vlTitle(22))
                        .foregroundStyle(VLColor.burgundy)

                    if let cat = DiscoveryCategory(rawValue: poi.categoryRaw) {
                        Label(cat.displayName, systemImage: cat.symbol)
                            .font(.vlBody())
                            .foregroundStyle(VLColor.darkTeal)
                    }

                    if let d = distanceMeters {
                        Text(String(format: "You are about %.0f m away", d))
                            .font(.vlCaption())
                            .foregroundStyle(VLColor.dustyBlue)
                    } else {
                        Text("Move with location on to see distance.")
                            .font(.vlCaption())
                            .foregroundStyle(VLColor.dustyBlue)
                    }

                    Group {
                        if let discovered {
                            Text("Discovered \(discovered.discoveredAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.vlBody(14))
                                .foregroundStyle(VLColor.darkTeal)
                        } else {
                            Text("Undiscovered — open the Journal tab within \(Int(ExplorationCoordinator.poiProximityRadiusMeters))m and tap Claim visit.")
                                .font(.vlBody(14))
                                .foregroundStyle(VLColor.dustyBlue)
                        }
                    }

                    if poi.isChain {
                        Text("Traveler’s note: \(poi.chainLabel ?? "Chain") — counts for exploration XP, not city completion.")
                            .font(.vlBody(13))
                            .foregroundStyle(VLColor.dustyBlue)
                            .padding(10)
                            .background(VLColor.dustyBlue.opacity(0.12))
                            .cornerRadius(10)
                    }

                    if poi.isPartner {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Stamp collector", systemImage: "seal.fill")
                                .foregroundStyle(VLColor.mutedGold)
                            if let offer = poi.partnerOffer, !offer.isEmpty {
                                Text(offer)
                                    .font(.vlBody(14))
                                    .foregroundStyle(VLColor.burgundy)
                            }
                            Button("Collect stamp (within \(Int(ExplorationCoordinator.poiProximityRadiusMeters))m)") {
                                collectStamp()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(VLColor.burgundy)
                        }
                        .padding(12)
                        .background(VLColor.cream)
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(VLColor.mutedGold, lineWidth: 1))
                    }

                    if let addr = poi.addressSummary, !addr.isEmpty {
                        Text(addr)
                            .font(.vlCaption())
                            .foregroundStyle(VLColor.darkTeal)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Explorer notes (local)")
                            .font(.vlCaption())
                            .foregroundStyle(VLColor.dustyBlue)
                        TextField("Private note", text: $note, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .disabled(discovered == nil)
                            .onAppear {
                                note = discovered?.explorerNote ?? ""
                            }
                        if discovered == nil {
                            Text("Notes unlock after you claim this place from the Journal (within \(Int(ExplorationCoordinator.poiProximityRadiusMeters))m).")
                                .font(.vlCaption(11))
                                .foregroundStyle(VLColor.dustyBlue)
                        }
                        Button("Save note") {
                            saveNote()
                        }
                        .foregroundStyle(VLColor.darkTeal)
                        .disabled(discovered == nil)
                    }
                }
                .padding(20)
            }
        }
        .alert("Stamp", isPresented: Binding(get: { stampMessage != nil }, set: { if !$0 { stampMessage = nil } })) {
            Button("OK", role: .cancel) { stampMessage = nil }
        } message: {
            Text(stampMessage ?? "")
        }
    }

    private func collectStamp() {
        guard let loc = exploration.lastUserLocation else {
            stampMessage = "Location unknown."
            return
        }
        do {
            let ok = try exploration.collectStamp(for: poi, user: loc)
            stampMessage = ok ? "Stamp added to your passport." : "You must be within \(Int(ExplorationCoordinator.poiProximityRadiusMeters))m to stamp."
        } catch {
            stampMessage = error.localizedDescription
        }
    }

    private func saveNote() {
        guard let discovered else { return }
        discovered.explorerNote = note
        try? modelContext.save()
    }
}
