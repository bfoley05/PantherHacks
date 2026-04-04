//
//  PassportView.swift
//  Venture Local
//

import SwiftData
import SwiftUI
import UIKit

struct PassportView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var exploration: ExplorationCoordinator

    @Query(sort: \StampRecord.stampedAt, order: .reverse) private var stamps: [StampRecord]

    private let partners = PartnerCatalog.load(from: .main)

    @State private var showScanner = false
    @State private var scannerFooterText: String?
    @State private var scanMessage: String?
    @State private var scanIsError = false

    private var partnerSummaries: [PassportPartnerSummary] {
        let grouped = Dictionary(grouping: stamps, by: \.osmId)
        return grouped.map { osmId, rows in
            PassportPartnerSummary(
                osmId: osmId,
                cityKey: rows.first?.cityKey ?? "",
                totalScans: rows.count,
                partner: partners.match(osmId: osmId)
            )
        }
        .sorted { displayName(for: $0).localizedCaseInsensitiveCompare(displayName(for: $1)) == .orderedAscending }
    }

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
                        Button {
                            scannerFooterText = nil
                            showScanner = true
                        } label: {
                            Label("Scan QR", systemImage: "qrcode.viewfinder")
                                .font(.vlCaption(13))
                                .foregroundStyle(VLColor.cream)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(VLColor.burgundy)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(VLColor.mutedGold.opacity(0.6), lineWidth: 1.5))
                        }
                    }

                    nearbyPartnersBanner

                    Text("Partner stamps use the business logo. Scan their QR within range — once per day per place. Ranks: 1 bronze · 3 silver · 5 gold · 10 platinum · 15 diamond · 20+ emerald.")
                        .font(.vlBody(13))
                        .foregroundStyle(VLColor.dustyBlue)

                    if partnerSummaries.isEmpty {
                        Text("No stamps yet. Tap Scan QR when you’re at a partner.")
                            .font(.vlBody())
                            .foregroundStyle(VLColor.darkTeal)
                    } else {
                        let byCity = Dictionary(grouping: partnerSummaries, by: \.cityKey)
                        ForEach(byCity.keys.sorted(), id: \.self) { city in
                            citySection(cityKey: city, rows: byCity[city] ?? [])
                        }
                    }
                }
                .padding(20)
            }
        }
        .onAppear {
            exploration.refreshNearbyPartnersForPassport()
        }
        .onChange(of: stamps.count) { _, _ in
            exploration.refreshNearbyPartnersForPassport()
        }
        .onChange(of: exploration.currentCityKey ?? "") { _, _ in
            exploration.refreshNearbyPartnersForPassport()
        }
        .fullScreenCover(isPresented: $showScanner) {
            NavigationStack {
                ZStack {
                    QRCodeScannerView { payload in
                        handleScanPayload(payload)
                    }
                    .ignoresSafeArea()

                    VStack {
                        HStack {
                            Spacer()
                            Button("Close") {
                                showScanner = false
                            }
                            .font(.vlBody(16))
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(.black.opacity(0.45))
                            .clipShape(Capsule())
                            .padding()
                        }
                        Spacer()
                        Text(scannerFooterText ?? "Point at the partner’s QR code")
                            .font(.vlCaption(12))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.black.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .padding(.bottom, 36)
                    }
                }
                .toolbar(.hidden, for: .navigationBar)
            }
        }
        .alert(scanIsError ? "Couldn’t add stamp" : "Passport", isPresented: Binding(
            get: { scanMessage != nil },
            set: { if !$0 { scanMessage = nil } }
        )) {
            Button("OK", role: .cancel) { scanMessage = nil }
        } message: {
            Text(scanMessage ?? "")
        }
    }

    @ViewBuilder
    private var nearbyPartnersBanner: some View {
        if !exploration.nearbyPartnerStampOffers.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("You’re near a supported partner")
                    .font(.vlCaption())
                    .foregroundStyle(VLColor.dustyBlue)
                ForEach(exploration.nearbyPartnerStampOffers) { offer in
                    if offer.canScanPartnerQRToday {
                        Button {
                            scannerFooterText = "Point at \(offer.displayName)’s QR code"
                            showScanner = true
                        } label: {
                            nearbyPartnerBannerLabel(offer: offer, statusCaption: "Within range · tap to scan their QR")
                        }
                        .buttonStyle(.plain)
                    } else {
                        nearbyPartnerBannerLabel(offer: offer, statusCaption: "Stamped today — come back tomorrow for another scan")
                            .opacity(0.92)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func nearbyPartnerBannerLabel(offer: ExplorationCoordinator.NearbyPartnerStampOffer, statusCaption: String) -> some View {
        HStack(spacing: 12) {
            Group {
                if let name = offer.stampImageName, !name.isEmpty, UIImage(named: name) != nil {
                    Image(name)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: "qrcode")
                        .font(.title2)
                        .foregroundStyle(VLColor.mutedGold)
                        .frame(width: 44, height: 44)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(statusCaption)
                    .font(.vlCaption(11))
                    .foregroundStyle(VLColor.mutedGold)
                Text(offer.displayName)
                    .font(.vlBody(16))
                    .foregroundStyle(VLColor.cream)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 8)
            if offer.canScanPartnerQRToday {
                Image(systemName: "qrcode.viewfinder")
                    .font(.title2)
                    .foregroundStyle(VLColor.mutedGold)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(VLColor.mutedGold.opacity(0.85))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VLColor.burgundy)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(VLColor.mutedGold.opacity(0.5), lineWidth: 2))
    }

    private func citySection(cityKey: String, rows: [PassportPartnerSummary]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(cityKey.replacingOccurrences(of: "__", with: ", "))
                .font(.vlTitle(18))
                .foregroundStyle(VLColor.darkTeal)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 148), spacing: 14)], spacing: 14) {
                ForEach(rows) { summary in
                    PartnerStampTile(
                        title: displayName(for: summary),
                        assetName: summary.partner.map(\.stampImageName).flatMap { $0.isEmpty ? nil : $0 },
                        tier: StampTier.tier(forTotalScans: summary.totalScans),
                        scanCount: summary.totalScans
                    )
                }
            }
        }
        .padding()
        .background(VLColor.cream.opacity(0.65))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(VLColor.mutedGold.opacity(0.5), lineWidth: 2))
        .cornerRadius(16)
    }

    private func displayName(for summary: PassportPartnerSummary) -> String {
        let id = summary.osmId
        let fd = FetchDescriptor<CachedPOI>(predicate: #Predicate { $0.osmId == id })
        if let n = try? modelContext.fetch(fd).first?.name, !n.isEmpty { return n }
        if let p = summary.partner {
            let offer = p.offer.trimmingCharacters(in: .whitespacesAndNewlines)
            if let r = offer.range(of: " — ") {
                return String(offer[..<r.lowerBound])
            }
            if let r = offer.range(of: " - ") {
                return String(offer[..<r.lowerBound])
            }
            if !offer.isEmpty { return offer }
            let img = p.stampImageName
            return img.isEmpty ? id : img
        }
        return id
    }

    private func handleScanPayload(_ payload: String) {
        do {
            try exploration.recordPartnerQRScan(rawPayload: payload)
            scanIsError = false
            scanMessage = "Stamp added to your passport."
            showScanner = false
        } catch {
            scanIsError = true
            scanMessage = error.localizedDescription
        }
    }
}

private struct PassportPartnerSummary: Identifiable {
    var id: String { osmId }
    var osmId: String
    var cityKey: String
    var totalScans: Int
    var partner: PartnerCatalog.Entry?
}

private struct PartnerStampTile: View {
    var title: String
    var assetName: String?
    var tier: StampTier?
    var scanCount: Int

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(VLColor.cream)

                Group {
                    if let name = assetName, !name.isEmpty, UIImage(named: name) != nil {
                        Image(name)
                            .resizable()
                            .scaledToFit()
                            .padding(10)
                    } else {
                        Image(systemName: "building.2.crop.circle.fill")
                            .font(.system(size: 52))
                            .foregroundStyle(VLColor.burgundy.opacity(0.75))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                if let tier {
                    StampTierOutline(tier: tier)
                }
            }
            .aspectRatio(1, contentMode: .fit)

            Text(title)
                .font(.vlCaption(11))
                .foregroundStyle(VLColor.burgundy)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Text("\(scanCount) visit\(scanCount == 1 ? "" : "s")")
                .font(.vlCaption(9))
                .foregroundStyle(VLColor.dustyBlue)

            if let tier {
                Text(tier.title)
                    .font(.vlCaption(10))
                    .foregroundStyle(VLColor.darkTeal)
            }
        }
        .padding(8)
        .background(VLColor.cream.opacity(0.9))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(VLColor.burgundy.opacity(0.15), lineWidth: 1))
        .cornerRadius(14)
    }
}

private struct StampTierOutline: View {
    let tier: StampTier

    var body: some View {
        let colors = tier.outlineColors
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(
                colors.count > 1
                    ? LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                    : LinearGradient(colors: [colors[0], colors[0]], startPoint: .top, endPoint: .bottom),
                lineWidth: tier.lineWidth
            )
            .padding(2)
            .allowsHitTesting(false)
            .modifier(StampEmeraldGlowModifier(enabled: tier.usesGlow))
    }
}

private struct StampEmeraldGlowModifier: ViewModifier {
    var enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content
                .shadow(color: Color(red: 0.5, green: 0.1, blue: 0.75).opacity(0.85), radius: 10, y: 0)
                .shadow(color: Color(red: 0.05, green: 0.75, blue: 0.45).opacity(0.75), radius: 14, y: 2)
                .shadow(color: Color(red: 0.35, green: 0.2, blue: 0.9).opacity(0.5), radius: 20, y: 0)
        } else {
            content
        }
    }
}
