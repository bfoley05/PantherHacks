//
//  BodyMapView.swift
//  PTApp
//

import Charts
import SwiftUI

struct BodyMapView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appState: AppState
    @State private var selectedRegion: BodyRegion?
    @State private var sensationText: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    bodySilhouetteSection
                    if let region = selectedRegion {
                        painSparklineSection(for: region)
                        swellingRomSection
                        notesSection
                        triggerSection
                    }
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .background(StrideTheme.gradientBackground(for: colorScheme))
            .navigationTitle("Body map")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private var bodySilhouetteSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tap where it bothers you")
                .font(.headline)

            Text("Green is calm · red is sharp. You can log multiple areas.")
                .font(.caption)
                .foregroundStyle(.secondary)

            BodySilhouetteCanvas(
                painByRegion: appState.bodyPainByRegion,
                onSelect: { region in
                    selectedRegion = region
                    let current = appState.bodyPainByRegion[region] ?? .none
                    let next = PainLevel(rawValue: (current.rawValue + 1) % 4) ?? .none
                    appState.bodyPainByRegion[region] = next
                }
            )
            .frame(height: 420)
            .background(StrideTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 10, y: 3)
        }
    }

    private func painSparklineSection(for region: BodyRegion) -> some View {
        let series = (0..<7).map { i in
            Double(4 + (i % 3)) - Double(i) * 0.35
        }

        return VStack(alignment: .leading, spacing: 10) {
            Text("Pain for \(region.displayName)")
                .font(.title3.weight(.bold))

            Text("Your \(region.displayName.lowercased()) pain is trending ↓ 40%")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(StrideTheme.success)

            Chart(Array(series.enumerated()), id: \.offset) { item in
                LineMark(
                    x: .value("Day", item.offset),
                    y: .value("Pain", item.element)
                )
                .foregroundStyle(StrideTheme.accent)
                AreaMark(
                    x: .value("Day", item.offset),
                    y: .value("Pain", item.element)
                )
                .foregroundStyle(StrideTheme.accent.opacity(0.12))
            }
            .frame(height: 120)
            .chartYScale(domain: 0...10)
        }
        .padding(16)
        .background(StrideTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var swellingRomSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Swelling & ROM")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Swelling")
                    .font(.subheadline.weight(.semibold))
                Picker("Swelling", selection: $appState.kneeSwelling) {
                    ForEach(PainLevel.allCases) { level in
                        Text(level.label).tag(level)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Extension")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(Int(appState.kneeExtensionDegrees))° vs target \(Int(appState.kneeExtensionTarget))°")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: $appState.kneeExtensionDegrees, in: -15...5, step: 1)
                    .tint(StrideTheme.accent)
                Text(appState.kneeExtensionDegrees < 0 ? "Feels stiff" : "On target")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(StrideTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Describe the sensation")
                .font(.headline)
            TextField("Burning / sharp / dull / clicking", text: $sensationText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
        }
        .padding(16)
        .background(StrideTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var triggerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Insight")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text("We noticed your knee pain spikes about 2 hours after lunges. Try reducing depth by 2 inches.")
                .font(.body)
        }
        .padding(16)
        .background(StrideTheme.warning.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct BodySilhouetteCanvas: View {
    var painByRegion: [BodyRegion: PainLevel]
    var onSelect: (BodyRegion) -> Void

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(uiColor: .secondarySystemBackground))

                BodyOutline()
                    .stroke(Color.primary.opacity(0.35), lineWidth: 2)
                    .padding(24)

                ForEach(BodyRegion.allCases) { region in
                    let rect = region.rect(in: CGSize(width: w, height: h))
                    let pain = painByRegion[region] ?? .none
                    Button {
                        onSelect(region)
                    } label: {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(painColor(pain).opacity(pain == .none ? 0.12 : 0.55))
                            .overlay {
                                Text(shortLabel(region))
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.primary.opacity(0.85))
                            }
                    }
                    .buttonStyle(.plain)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                }
            }
        }
    }

    private func shortLabel(_ region: BodyRegion) -> String {
        switch region {
        case .kneeL, .kneeR: return "Knee"
        case .hipL, .hipR: return "Hip"
        case .shoulderL, .shoulderR: return "Shoulder"
        case .lowerBack: return "Low back"
        case .upperBack: return "Upper"
        case .neck: return "Neck"
        case .elbowL, .elbowR: return "Elbow"
        case .wristL, .wristR: return "Wrist"
        case .ankleL, .ankleR: return "Ankle"
        case .chest: return "Chest"
        case .head: return "Head"
        }
    }

    private func painColor(_ pain: PainLevel) -> Color {
        switch pain {
        case .none: return .green
        case .mild: return .yellow
        case .moderate: return .orange
        case .severe: return .red
        }
    }
}

private struct BodyOutline: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let cx = rect.midX

        path.addEllipse(in: CGRect(x: cx - w * 0.12, y: h * 0.02, width: w * 0.24, height: h * 0.12))
        path.addRoundedRect(
            in: CGRect(x: cx - w * 0.18, y: h * 0.12, width: w * 0.36, height: h * 0.12),
            cornerSize: CGSize(width: 10, height: 10)
        )
        path.addRoundedRect(
            in: CGRect(x: cx - w * 0.22, y: h * 0.22, width: w * 0.44, height: h * 0.22),
            cornerSize: CGSize(width: 14, height: 14)
        )
        path.addRoundedRect(
            in: CGRect(x: cx - w * 0.10, y: h * 0.44, width: w * 0.20, height: h * 0.18),
            cornerSize: CGSize(width: 12, height: 12)
        )

        path.addRoundedRect(
            in: CGRect(x: cx - w * 0.28, y: h * 0.26, width: w * 0.10, height: h * 0.30),
            cornerSize: CGSize(width: 10, height: 10)
        )
        path.addRoundedRect(
            in: CGRect(x: cx + w * 0.18, y: h * 0.26, width: w * 0.10, height: h * 0.30),
            cornerSize: CGSize(width: 10, height: 10)
        )

        path.addRoundedRect(
            in: CGRect(x: cx - w * 0.14, y: h * 0.62, width: w * 0.12, height: h * 0.30),
            cornerSize: CGSize(width: 12, height: 12)
        )
        path.addRoundedRect(
            in: CGRect(x: cx + w * 0.02, y: h * 0.62, width: w * 0.12, height: h * 0.30),
            cornerSize: CGSize(width: 12, height: 12)
        )

        return path
    }
}

private extension BodyRegion {
    func rect(in size: CGSize) -> CGRect {
        let w = size.width
        let h = size.height
        let cx = w * 0.5
        switch self {
        case .head:
            return CGRect(x: cx - w * 0.10, y: h * 0.05, width: w * 0.20, height: h * 0.10)
        case .neck:
            return CGRect(x: cx - w * 0.09, y: h * 0.14, width: w * 0.18, height: h * 0.06)
        case .shoulderL:
            return CGRect(x: cx - w * 0.30, y: h * 0.20, width: w * 0.14, height: h * 0.08)
        case .shoulderR:
            return CGRect(x: cx + w * 0.16, y: h * 0.20, width: w * 0.14, height: h * 0.08)
        case .elbowL:
            return CGRect(x: cx - w * 0.32, y: h * 0.30, width: w * 0.12, height: h * 0.08)
        case .elbowR:
            return CGRect(x: cx + w * 0.20, y: h * 0.30, width: w * 0.12, height: h * 0.08)
        case .wristL:
            return CGRect(x: cx - w * 0.33, y: h * 0.38, width: w * 0.10, height: h * 0.06)
        case .wristR:
            return CGRect(x: cx + w * 0.23, y: h * 0.38, width: w * 0.10, height: h * 0.06)
        case .chest:
            return CGRect(x: cx - w * 0.14, y: h * 0.22, width: w * 0.28, height: h * 0.10)
        case .upperBack:
            return CGRect(x: cx - w * 0.16, y: h * 0.24, width: w * 0.32, height: h * 0.08)
        case .lowerBack:
            return CGRect(x: cx - w * 0.12, y: h * 0.34, width: w * 0.24, height: h * 0.10)
        case .hipL:
            return CGRect(x: cx - w * 0.20, y: h * 0.44, width: w * 0.14, height: h * 0.08)
        case .hipR:
            return CGRect(x: cx + w * 0.06, y: h * 0.44, width: w * 0.14, height: h * 0.08)
        case .kneeL:
            return CGRect(x: cx - w * 0.16, y: h * 0.64, width: w * 0.12, height: h * 0.10)
        case .kneeR:
            return CGRect(x: cx + w * 0.04, y: h * 0.64, width: w * 0.12, height: h * 0.10)
        case .ankleL:
            return CGRect(x: cx - w * 0.14, y: h * 0.82, width: w * 0.10, height: h * 0.08)
        case .ankleR:
            return CGRect(x: cx + w * 0.04, y: h * 0.82, width: w * 0.10, height: h * 0.08)
        }
    }
}
