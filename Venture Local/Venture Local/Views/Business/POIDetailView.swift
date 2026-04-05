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
    @EnvironmentObject private var auth: AuthSessionController

    let poi: CachedPOI
    @Bindable var exploration: ExplorationCoordinator

    @Query private var discoveries: [DiscoveredPlace]
    @Query private var favorites: [FavoritePlace]
    @State private var note: String = ""
    @State private var showOpenInMapsChoice = false
    @State private var recommendBusy = false
    @State private var recommendSucceeded = false
    @State private var recommendMessage: String?
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

    /// `darkTeal` is a dark fill in light mode and a light mint in dark vintage — pick label color for contrast on both.
    private var sharedWithFriendsSuccessForeground: Color {
        theme.useDarkVintagePalette
            ? Color(red: 0x09 / 255, green: 0x0E / 255, blue: 0x0B / 255)
            : VLColor.cream
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

                    VStack(alignment: .leading, spacing: 6) {
                        if recommendSucceeded {
                            HStack(spacing: 10) {
                                Image(systemName: DiscoveryCategory(rawValue: poi.categoryRaw)?.symbol ?? "mappin.circle.fill")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(sharedWithFriendsSuccessForeground)
                                Label("Shared", systemImage: "checkmark.circle.fill")
                                    .font(.vlBody(14).weight(.semibold))
                                    .foregroundStyle(sharedWithFriendsSuccessForeground)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .padding(.horizontal, 12)
                            .background(VLColor.darkTeal, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(VLColor.mutedGold.opacity(theme.useDarkVintagePalette ? 0.7 : 0.45), lineWidth: 1.5)
                            )
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Shared with friends")
                        } else {
                            Button {
                                Task { await recommendToFriends() }
                            } label: {
                                if recommendBusy {
                                    ProgressView()
                                        .tint(theme.useDarkVintagePalette ? VLColor.mutedGold : VLColor.burgundy)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 4)
                                } else {
                                    Label("Share with friends", systemImage: "person.2.wave.2.fill")
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(VLColor.darkTeal)
                            .font(.vlBody(14))
                            .disabled(recommendBusy || !auth.isSignedIn || auth.configurationMissing)
                        }

                        if !auth.isSignedIn {
                            Text("Sign in to recommend this place to friends on the Social tab.")
                                .font(.vlCaption(11))
                                .foregroundStyle(VLColor.dustyBlue)
                        } else if let recommendMessage {
                            Text(recommendMessage)
                                .font(.vlCaption(12))
                                .foregroundStyle(VLColor.burgundy)
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

                    if poi.isPartner, let offer = poi.partnerOffer, !offer.isEmpty {
                        Text(offer)
                            .font(.vlBody(14))
                            .foregroundStyle(VLColor.burgundy)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
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
                }
                .padding(20)
            }
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

    private func saveNote() {
        guard let discovered else { return }
        discovered.explorerNote = note
        try? modelContext.save()
    }

    private func recommendToFriends() async {
        recommendMessage = nil
        recommendSucceeded = false
        guard auth.isSignedIn, !auth.configurationMissing else { return }
        recommendBusy = true
        defer { recommendBusy = false }
        CloudSyncService.shared.bind(auth: auth)
        let city = poi.cityKey
        do {
            try await CloudSyncService.shared.upsertFriendPlaceRecommendation(
                osmId: poi.osmId,
                cityKey: city,
                placeName: poi.name,
                categoryRaw: poi.categoryRaw,
                latitude: poi.latitude,
                longitude: poi.longitude
            )
            recommendSucceeded = true
        } catch {
            recommendMessage = "Couldn’t share: \(error.localizedDescription)"
        }
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
