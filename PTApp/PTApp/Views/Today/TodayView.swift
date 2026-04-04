//
//  TodayView.swift
//  PTApp
//

import SwiftUI
import UIKit

struct TodayView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var appState: AppState
    @State private var quote: QuoteEntry = QuoteService.quoteForToday()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    todayHeaderSection
                    milestoneSection
                    todaysRxSection
                    quickLogSection
                    quoteFooter
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .background(StrideTheme.gradientBackground(for: colorScheme))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    StrideLogoView(height: 44)
                }
            }
            .onAppear {
                quote = QuoteService.quoteForToday()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    quote = QuoteService.quoteForToday()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                quote = QuoteService.quoteForToday()
            }
        }
    }

    private var todayHeaderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today")
                .font(.largeTitle.weight(.bold))

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(appState.greetingPrefix()), \(appState.userName)")
                            .font(.title2.weight(.semibold))
                        HStack(spacing: 6) {
                            Text("🔥")
                            Text("\(appState.strideStreakDays) days of perfect form")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }

                HStack {
                    Label {
                        Text("Recovery Score: \(appState.recoveryScore)%")
                            .font(.subheadline.weight(.semibold))
                    } icon: {
                        Image(systemName: "heart.text.square.fill")
                            .foregroundStyle(StrideTheme.accent)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.bold))
                        Text("\(appState.recoveryDeltaFromYesterday)% from yesterday")
                            .font(.caption.weight(.medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(StrideTheme.accent.opacity(0.12))
                    .clipShape(Capsule())
                }
            }
        }
        .padding(.top, 4)
    }

    private var milestoneSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(appState.milestone.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(appState.milestone.detail)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            ZStack {
                StrideProgressRing(progress: appState.milestone.progress, lineWidth: 16)
                    .frame(width: 120, height: 120)
                VStack(spacing: 2) {
                    Text("\(Int(appState.milestone.progress * 100))%")
                        .font(.title.weight(.bold))
                    Text("complete")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(20)
        .background(StrideTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
    }

    private var todaysRxSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today's Rx")
                .font(.title3.weight(.bold))

            ForEach($appState.exercises) { $exercise in
                ExercisePlaylistRow(exercise: $exercise)
            }
        }
    }

    private var quickLogSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick log")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    QuickLogPainCard(selection: $appState.todayPainEmoji)
                    QuickLogSwellingCard(dots: $appState.todaySwellingDots)
                    QuickLogNoteCard(note: $appState.todayNote)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var quoteFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("“\(quote.text)”")
                .font(.body.italic())
                .foregroundStyle(.secondary)
            Text("— \(quote.author)")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StrideTheme.card.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct ExercisePlaylistRow: View {
    @Binding var exercise: PTExercise

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(StrideTheme.accent.opacity(0.15))
                .frame(width: 48, height: 48)
                .overlay {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .foregroundStyle(StrideTheme.accent)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name)
                    .font(.headline)
                Text("\(exercise.sets) × \(exercise.reps)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let score = exercise.lastFormScore {
                    Text("Form score last time: \(score)%")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(uiColor: .tertiarySystemFill))
                        .clipShape(Capsule())
                }
            }

            Spacer(minLength: 8)

            Button {
                exercise.isDone.toggle()
            } label: {
                if exercise.isDone {
                    Label("Done", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                } else {
                    Label("Start", systemImage: "play.fill")
                        .font(.subheadline.weight(.semibold))
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(exercise.isDone ? StrideTheme.success : StrideTheme.accent)
        }
        .padding(14)
        .background(StrideTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }
}

private struct QuickLogPainCard: View {
    @Binding var selection: String?

    private let faces = ["😊", "😐", "😖"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pain")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ForEach(faces, id: \.self) { face in
                    Button {
                        selection = face
                    } label: {
                        Text(face)
                            .font(.title2)
                            .padding(8)
                            .background(
                                selection == face
                                    ? StrideTheme.accent.opacity(0.2)
                                    : Color(uiColor: .tertiarySystemFill)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .frame(width: 200, alignment: .leading)
        .background(StrideTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct QuickLogSwellingCard: View {
    @Binding var dots: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Swelling")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(1...3, id: \.self) { n in
                    Button {
                        dots = n
                    } label: {
                        HStack(spacing: 4) {
                            ForEach(0..<n, id: \.self) { _ in
                                Circle()
                                    .fill(n == dots ? StrideTheme.accent : Color.gray.opacity(0.35))
                                    .frame(width: 8, height: 8)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            n == dots ? StrideTheme.accent.opacity(0.15) : Color(uiColor: .tertiarySystemFill)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .frame(width: 200, alignment: .leading)
        .background(StrideTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct QuickLogNoteCard: View {
    @Binding var note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Note")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("Knee felt clicky", text: $note)
                .textFieldStyle(.roundedBorder)
        }
        .padding(12)
        .frame(width: 240, alignment: .leading)
        .background(StrideTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
