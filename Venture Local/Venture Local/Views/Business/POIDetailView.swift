//
//  POIDetailView.swift
//  Venture Local
//

import CoreLocation
import SwiftData
import SwiftUI
import UIKit

// MARK: - External maps (shared query building)
private enum ExternalMapsLinks {
    /// Text Google/Apple can search on; falls back to coordinates if the name is empty.
    static func placeSearchQuery(name: String, addressSummary: String?, latitude: Double, longitude: Double) -> String {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let a = addressSummary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !n.isEmpty, !a.isEmpty { return "\(n), \(a)" }
        if !n.isEmpty { return n }
        return "\(latitude),\(longitude)"
    }
}

struct POIDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var theme: ThemeSettings

    let poi: CachedPOI
    @Bindable var exploration: ExplorationCoordinator

    @Query private var discoveries: [DiscoveredPlace]
    @Query private var favorites: [FavoritePlace]
    @State private var note: String = ""
    @State private var stampMessage: String?
    @State private var showOpenInMapsChoice = false
    @AppStorage("mapDistanceUsesMiles") private var mapDistanceUsesMiles = Locale.current.measurementSystem == .us

    private var discovered: DiscoveredPlace? {
        discoveries.first { $0.osmId == poi.osmId }
    }

    private var isFavorite: Bool { favorites.contains { $0.osmId == poi.osmId } }

    private var distanceMeters: Double? {
        guard let loc = exploration.lastUserLocation else { return nil }
        let there = CLLocationCoordinate2D(latitude: poi.latitude, longitude: poi.longitude)
        return GeoMath.distanceMeters(loc.coordinate, there)
    }

    var body: some View {
        let _ = theme.useDarkVintagePalette
        let flavorChips = PlaceExploreFlavorTags.displayChips(for: poi)
        return ZStack {
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

                    if !flavorChips.isEmpty {
                        Text("Badge hints: \(flavorChips.joined(separator: " · "))")
                            .font(.vlCaption(12))
                            .foregroundStyle(VLColor.subtleInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let d = distanceMeters {
                        Text("You’re about \(GeoMath.formatApproximateMapDistance(meters: d, useMiles: mapDistanceUsesMiles)) away")
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
                            Text("Undiscovered — open the Journal tab within \(ExplorationCoordinator.poiProximityRadiusCopy) and tap Claim visit.")
                                .font(.vlBody(14))
                                .foregroundStyle(VLColor.dustyBlue)
                        }
                    }

                    Button(isFavorite ? "Favorited" : "Favorite") {
                        toggleFavorite()
                    }
                    .buttonStyle(.bordered)
                    .tint(isFavorite ? VLColor.burgundy : VLColor.darkTeal)
                    .font(.vlBody(14))

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
                            Button("Collect stamp (within \(ExplorationCoordinator.poiProximityRadiusCopy))") {
                                collectStamp()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(VLColor.burgundy)
                        }
                        .padding(12)
                        .background(VLColor.cardBackground)
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(VLColor.mutedGold, lineWidth: 1))
                    }

                    mapsAddressSection

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
                            Text("Notes unlock after you claim this place from the Journal (within \(ExplorationCoordinator.poiProximityRadiusCopy)).")
                                .font(.vlCaption(11))
                                .foregroundStyle(VLColor.dustyBlue)
                        }
                        Button("Save note") {
                            saveNote()
                        }
                        .foregroundStyle(VLColor.darkTeal)
                        .disabled(discovered == nil)
                    }

                    if discovered != nil {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Photo moment (local)")
                                .font(.vlCaption())
                                .foregroundStyle(VLColor.dustyBlue)
                            Text("Tap to log that you captured this place — counts toward the Photo Finish badge.")
                                .font(.vlCaption(11))
                                .foregroundStyle(VLColor.subtleInk)
                            Button {
                                logPhotoMoment()
                            } label: {
                                Label("Log photo moment", systemImage: "camera.fill")
                                    .font(.vlBody(14).weight(.medium))
                                    .foregroundStyle(VLColor.cream)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(VLColor.burgundy)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
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
        .confirmationDialog("Open in Maps", isPresented: $showOpenInMapsChoice, titleVisibility: .visible) {
            Button("Apple Maps") { openInAppleMaps() }
            Button("Google Maps") { openInGoogleMaps() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Get directions or view this pin in another app.")
        }
    }

    @ViewBuilder
    private var mapsAddressSection: some View {
        let addr = poi.addressSummary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !addr.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Address")
                    .font(.vlCaption())
                    .foregroundStyle(VLColor.dustyBlue)
                Button {
                    showOpenInMapsChoice = true
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.body)
                            .foregroundStyle(VLColor.burgundy)
                        Text(addr)
                            .font(.vlBody(14))
                            .foregroundStyle(VLColor.darkTeal)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(VLColor.mutedGold)
                    }
                    .padding(12)
                    .background(VLColor.cardBackground)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(VLColor.burgundy.opacity(0.22), lineWidth: 1))
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens a choice of Apple Maps or Google Maps.")
            }
        } else {
            Button {
                showOpenInMapsChoice = true
            } label: {
                Label("Open pin in Maps", systemImage: "map")
                    .font(.vlBody(14).weight(.medium))
                    .foregroundStyle(VLColor.darkTeal)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(VLColor.cardBackground)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(VLColor.burgundy.opacity(0.22), lineWidth: 1))
                    .cornerRadius(12)
            }
            .buttonStyle(.plain)
        }
    }

    private func openInAppleMaps() {
        let lat = poi.latitude
        let lon = poi.longitude
        let qRaw = ExternalMapsLinks.placeSearchQuery(
            name: poi.name,
            addressSummary: poi.addressSummary,
            latitude: lat,
            longitude: lon
        )
        let q = qRaw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Place"
        guard let url = URL(string: "https://maps.apple.com/?ll=\(lat),\(lon)&q=\(q)") else { return }
        UIApplication.shared.open(url)
    }

    private func openInGoogleMaps() {
        let lat = poi.latitude
        let lon = poi.longitude
        let query = ExternalMapsLinks.placeSearchQuery(
            name: poi.name,
            addressSummary: poi.addressSummary,
            latitude: lat,
            longitude: lon
        )

        var app = URLComponents()
        app.scheme = "comgooglemaps"
        app.host = ""
        app.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "center", value: "\(lat),\(lon)"),
            URLQueryItem(name: "zoom", value: "16"),
        ]
        if let appUrl = app.url, UIApplication.shared.canOpenURL(appUrl) {
            UIApplication.shared.open(appUrl)
            return
        }

        var web = URLComponents(string: "https://www.google.com/maps/search/")
        web?.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "query", value: query),
        ]
        if let webUrl = web?.url {
            UIApplication.shared.open(webUrl)
        }
    }

    private func collectStamp() {
        guard let loc = exploration.lastUserLocation else {
            stampMessage = "Location unknown."
            return
        }
        do {
            let ok = try exploration.collectStamp(for: poi, user: loc)
            stampMessage = ok ? "Stamp added to your passport." : "You must be within \(ExplorationCoordinator.poiProximityRadiusCopy) to stamp."
        } catch {
            stampMessage = error.localizedDescription
        }
    }

    private func saveNote() {
        guard let discovered else { return }
        discovered.explorerNote = note
        try? modelContext.save()
    }

    private func logPhotoMoment() {
        guard discovered != nil else { return }
        let oid = poi.osmId
        let pred = #Predicate<PlacePhotoCheckIn> { $0.osmId == oid }
        if let existing = try? modelContext.fetch(FetchDescriptor<PlacePhotoCheckIn>(predicate: pred)).first {
            existing.createdAt = .now
        } else {
            modelContext.insert(PlacePhotoCheckIn(osmId: poi.osmId, cityKey: poi.cityKey))
        }
        try? modelContext.save()
        exploration.evaluateBadgesAndLedgerNotifications()
    }

    private func toggleFavorite() {
        let key = exploration.currentCityKey ?? poi.cityKey
        if let row = favorites.first(where: { $0.osmId == poi.osmId }) {
            modelContext.delete(row)
            ExplorerEventLog.recordUnfavorite(context: modelContext, poi: poi, cityKey: key)
        } else {
            modelContext.insert(FavoritePlace(osmId: poi.osmId, cityKey: key))
            ExplorerEventLog.recordFavorite(context: modelContext, poi: poi, cityKey: key)
        }
        try? modelContext.save()
    }
}
