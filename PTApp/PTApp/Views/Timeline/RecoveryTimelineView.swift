//
//  RecoveryTimelineView.swift
//  PTApp
//

import Charts
import SwiftUI

struct RecoveryTimelineView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var expandedSession: UUID?

    private var chartPoints: [(Date, Double, String)] {
        let cal = Calendar.current
        let today = Date.now
        var pts: [(Date, Double, String)] = []
        for i in -14...14 {
            let d = cal.date(byAdding: .day, value: i, to: cal.startOfDay(for: today)) ?? today
            let base = 6.0 - Double(i + 14) * 0.08
            let noise = sin(Double(i) * 0.4) * 0.6
            let pain = min(10, max(0, base + noise))
            let kind = i == -3 ? "flare" : (i == 2 ? "streak" : "normal")
            pts.append((d, pain, kind))
        }
        return pts
    }

    private var predictionPoints: [(Date, Double)] {
        chartPoints.map { ($0.0, max(0, $0.1 - 0.4)) }
    }

    private var sessions: [SessionHistoryItem] {
        let cal = Calendar.current
        return [
            SessionHistoryItem(
                date: cal.date(byAdding: .day, value: -1, to: .now) ?? .now,
                exercises: ["Glute Bridge", "Clamshells"],
                formScore: 92,
                painBefore: 4,
                painAfter: 3,
                note: "Felt stronger on the left."
            ),
            SessionHistoryItem(
                date: cal.date(byAdding: .day, value: -3, to: .now) ?? .now,
                exercises: ["Mini Squat to Box"],
                formScore: 88,
                painBefore: 5,
                painAfter: 4,
                note: "Knee a little stiff."
            ),
        ]
    }

    private var badges: [MilestoneBadge] {
        let cal = Calendar.current
        return [
            MilestoneBadge(title: "First pain-free squat", icon: "🏅", date: cal.date(byAdding: .day, value: -10, to: .now) ?? .now),
            MilestoneBadge(title: "7-day streak", icon: "🔥", date: cal.date(byAdding: .day, value: -2, to: .now) ?? .now),
            MilestoneBadge(title: "No compensations for 50 reps", icon: "💪", date: cal.date(byAdding: .day, value: -5, to: .now) ?? .now),
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    chartSection
                    sessionSection
                    badgesSection
                    forecastSection
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .background(StrideTheme.gradientBackground(for: colorScheme))
            .navigationTitle("Timeline")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recovery prediction")
                .font(.title3.weight(.bold))

            Text("Past 2 weeks → today → next 2 weeks")
                .font(.caption)
                .foregroundStyle(.secondary)

            Chart {
                ForEach(Array(chartPoints.enumerated()), id: \.offset) { _, row in
                    LineMark(
                        x: .value("Day", row.0),
                        y: .value("Pain", row.1)
                    )
                    .foregroundStyle(StrideTheme.accent)
                    .interpolationMethod(.catmullRom)

                    if row.2 == "flare" {
                        PointMark(
                            x: .value("Day", row.0),
                            y: .value("Pain", row.1)
                        )
                        .annotation(position: .top) {
                            Text("Flare-up")
                                .font(.caption2)
                                .padding(4)
                                .background(.thinMaterial, in: Capsule())
                        }
                    }
                    if row.2 == "streak" {
                        PointMark(
                            x: .value("Day", row.0),
                            y: .value("Pain", row.1)
                        )
                        .annotation(position: .bottom) {
                            Text("3 perfect days")
                                .font(.caption2)
                                .padding(4)
                                .background(.thinMaterial, in: Capsule())
                        }
                    }
                }

                ForEach(Array(predictionPoints.enumerated()), id: \.offset) { _, row in
                    LineMark(
                        x: .value("Day", row.0),
                        y: .value("Forecast", row.1)
                    )
                    .foregroundStyle(Color.gray.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .interpolationMethod(.catmullRom)
                }
            }
            .frame(height: 220)
            .chartYScale(domain: 0...10)
            .chartXAxis {
                AxisMarks(values: .automatic) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month().day())
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("\(Int(v))")
                        }
                    }
                }
            }

            HStack(spacing: 16) {
                Label("Your recovery", systemImage: "circle.fill")
                    .font(.caption)
                    .foregroundStyle(StrideTheme.accent)
                Label("AI forecast", systemImage: "line.diagonal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(StrideTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 10, y: 3)
    }

    private var sessionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Session history")
                .font(.title3.weight(.bold))

            ForEach(sessions) { session in
                SessionCard(
                    session: session,
                    isExpanded: expandedSession == session.id,
                    onToggle: {
                        expandedSession = expandedSession == session.id ? nil : session.id
                    }
                )
            }
        }
    }

    private var badgesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Milestones")
                .font(.title3.weight(.bold))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(badges) { badge in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(badge.icon).font(.title)
                            Text(badge.title)
                                .font(.subheadline.weight(.semibold))
                                .fixedSize(horizontal: false, vertical: true)
                            Text(badge.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .frame(width: 200, alignment: .leading)
                        .background(StrideTheme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
            }
        }
    }

    private var forecastSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What's next")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text("Based on your progress, you'll likely advance to single-leg bridges in 4 days.")
                .font(.body.weight(.medium))

            Button {
                // Preview exercise — placeholder
            } label: {
                Label("View new exercise preview", systemImage: "play.rectangle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(StrideTheme.accent)
        }
        .padding(16)
        .background(StrideTheme.accent.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct SessionCard: View {
    let session: SessionHistoryItem
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onToggle) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.headline)
                        Text("\(session.exercises.joined(separator: " · "))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text("\(session.formScore)%")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(StrideTheme.accent)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                detailRow("Pain before", value: "\(session.painBefore)/10")
                detailRow("Pain after", value: "\(session.painAfter)/10")
                detailRow("Notes", value: session.note)

                if session.hasVideoHighlight {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemFill))
                        .frame(height: 120)
                        .overlay {
                            Label("Best rep replay", systemImage: "play.circle.fill")
                                .foregroundStyle(StrideTheme.accent)
                        }
                }
            }
        }
        .padding(14)
        .background(StrideTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }

    private func detailRow(_ title: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.caption.weight(.medium))
        }
    }
}
