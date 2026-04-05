//
//  PassportView.swift
//  Venture Local
//

import SwiftData
import SwiftUI
import UIKit

struct PassportView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var theme: ThemeSettings
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
                partner: resolvedPartnerEntry(osmId: osmId)
            )
        }
        .sorted { displayName(for: $0).localizedCaseInsensitiveCompare(displayName(for: $1)) == .orderedAscending }
    }

    private func resolvedPartnerEntry(osmId: String) -> PartnerCatalog.Entry? {
        if let e = partners.match(osmId: osmId) { return e }
        let fd = FetchDescriptor<CachedPOI>(predicate: #Predicate { $0.osmId == osmId })
        guard let poi = try? modelContext.fetch(fd).first else { return nil }
        return partners.matchPartnerPOI(name: poi.name, osmId: osmId)
    }

    var body: some View {
        let _ = theme.useDarkVintagePalette
        return ZStack {
            PaperBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Spacer(minLength: 0)
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

                    Text("Partner businesses from our directory show on the map. A banner may appear when you’re within \(ExplorationCoordinator.poiProximityRadiusCopy)—tap it or use Scan QR. The scan succeeds when you’re within about \(ExplorationCoordinator.partnerQRProximityRadiusCopy) of the partner. Use the QR that encodes the business’s stamp image link. One scan per place per day.")
                        .font(.vlBody(13))
                        .foregroundStyle(VLColor.dustyBlue)
                        .fixedSize(horizontal: false, vertical: true)

                    DisclosureGroup {
                        Text("Visit ranks at each partner: 1 bronze · 3 silver · 5 gold · 10 platinum · 15 diamond · 20 or more emerald. Higher tiers add a stronger frame on your stamp.")
                            .font(.vlBody(12))
                            .foregroundStyle(VLColor.dustyBlue)
                            .padding(.top, 4)
                            .fixedSize(horizontal: false, vertical: true)
                    } label: {
                        Text("How ranks work")
                            .font(.vlCaption(12).weight(.semibold))
                            .foregroundStyle(VLColor.darkTeal)
                    }

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
            .scrollContentBackground(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        .containerBackground(theme.paperBackdropColor, for: .navigation)
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
            PartnerOfferThumb(stampImageName: offer.stampImageName, imageURL: offer.partnerImageURL, size: 44, corner: 8)
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
                        imageURL: summary.partner?.imageURLString,
                        tier: StampTier.tier(forTotalScans: summary.totalScans),
                        scanCount: summary.totalScans
                    )
                }
            }
        }
        .padding()
        .background(VLColor.passportCityPanel)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(VLColor.mutedGold.opacity(0.5), lineWidth: 2))
        .cornerRadius(16)
    }

    private func displayName(for summary: PassportPartnerSummary) -> String {
        if let p = summary.partner, let n = p.listingName, !n.isEmpty { return n }
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

private struct PartnerOfferThumb: View {
    var stampImageName: String?
    var imageURL: String?
    var size: CGFloat
    var corner: CGFloat

    var body: some View {
        Group {
            if let name = stampImageName, !name.isEmpty, UIImage(named: name) != nil {
                Image(name)
                    .resizable()
                    .scaledToFit()
            } else if let s = imageURL, let url = URL(string: s) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFit()
                    case .failure:
                        thumbFallback
                    case .empty:
                        ProgressView().scaleEffect(0.75)
                    @unknown default:
                        thumbFallback
                    }
                }
            } else {
                thumbFallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner))
    }

    private var thumbFallback: some View {
        Image(systemName: "qrcode")
            .font(.title2)
            .foregroundStyle(VLColor.mutedGold)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PartnerTileArt: View {
    var assetName: String?
    var imageURL: String?

    var body: some View {
        Group {
            if let name = assetName, !name.isEmpty, UIImage(named: name) != nil {
                Image(name)
                    .resizable()
                    .scaledToFit()
                    .padding(10)
            } else if let s = imageURL, let url = URL(string: s) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFit().padding(10)
                    case .failure:
                        tilePlaceholder
                    case .empty:
                        ProgressView()
                    @unknown default:
                        tilePlaceholder
                    }
                }
            } else {
                tilePlaceholder
            }
        }
    }

    private var tilePlaceholder: some View {
        Image(systemName: "building.2.crop.circle.fill")
            .font(.system(size: 52))
            .foregroundStyle(VLColor.burgundy.opacity(0.75))
    }
}

private struct PartnerStampTile: View {
    var title: String
    var assetName: String?
    var imageURL: String?
    var tier: StampTier?
    var scanCount: Int

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(VLColor.stampMatte)

                PartnerTileArt(assetName: assetName, imageURL: imageURL)
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
        .background(VLColor.stampTileOuter)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(VLColor.burgundy.opacity(0.15), lineWidth: 1))
        .cornerRadius(14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(title), \(scanCount) visit\(scanCount == 1 ? "" : "s")"
                + (tier.map { ", \($0.title) rank" } ?? "")
        )
    }
}

private struct StampTierOutline: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let tier: StampTier

    private static let diamondSparkleOffsets: [(x: CGFloat, y: CGFloat)] = [
        (-34, -30), (32, -28), (-30, 32), (34, 32),
    ]

    var body: some View {
        let colors = tier.outlineColors
        let border = RoundedRectangle(cornerRadius: 12)
            .strokeBorder(
                colors.count > 1
                    ? LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                    : LinearGradient(colors: [colors[0], colors[0]], startPoint: .top, endPoint: .bottom),
                lineWidth: tier.lineWidth
            )
            .padding(2)
            .allowsHitTesting(false)

        Group {
            if reduceMotion {
                border
            } else if tier.usesPlatinumEffects {
                TimelineView(.animation(minimumInterval: 0.12, paused: false)) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    let pulse = 0.55 + 0.45 * sin(t * 2.4)
                    border
                        .shadow(color: Color.white.opacity(0.42 * pulse), radius: 3 + CGFloat(pulse) * 2, y: 0)
                        .shadow(color: Color(red: 0.45, green: 0.72, blue: 0.95).opacity(0.32 * (1 - pulse * 0.45)), radius: 5 + CGFloat(pulse) * 2, y: 1)
                }
            } else if tier.usesDiamondEffects {
                TimelineView(.animation(minimumInterval: 0.12, paused: false)) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    let tw = abs(sin(t * 3.2))
                    ZStack {
                        border
                            .shadow(color: Color.white.opacity(0.22 + 0.18 * tw), radius: 2 + 3 * CGFloat(tw), y: 0)
                            .shadow(color: Color(red: 0.55, green: 0.82, blue: 0.98).opacity(0.38), radius: 5, y: 0)
                        ForEach(Array(Self.diamondSparkleOffsets.enumerated()), id: \.offset) { i, o in
                            let blink = 0.28 + 0.72 * pow(0.5 + 0.5 * sin(t * 4.1 + Double(i) * 1.6), 2)
                            Image(systemName: "sparkle")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.white.opacity(blink))
                                .offset(x: o.x, y: o.y)
                        }
                    }
                }
            } else if tier.usesEmeraldAura {
                TimelineView(.animation(minimumInterval: 0.08, paused: false)) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    let w = 0.5 + 0.5 * sin(t * 2.2)
                    let w2 = 0.5 + 0.5 * sin(t * 3.7 + 1)
                    border
                        .shadow(color: Color(red: 0.55, green: 0.08, blue: 0.82).opacity(0.58 * w2), radius: 8 + 8 * w2, y: 0)
                        .shadow(color: Color(red: 0.02, green: 0.78, blue: 0.48).opacity(0.68 * w), radius: 12 + 12 * w, y: 1)
                        .shadow(color: Color(red: 0.35, green: 0.55, blue: 1.0).opacity(0.48 * (1 - w * 0.25)), radius: 18 + 8 * w, y: 0)
                        .shadow(color: Color(red: 0.2, green: 0.95, blue: 0.65).opacity(0.4 * w2), radius: 24, y: 0)
                        .shadow(color: Color(red: 0.75, green: 0.15, blue: 0.95).opacity(0.28 * w), radius: 28, y: -1)
                }
            } else {
                border
            }
        }
    }
}
