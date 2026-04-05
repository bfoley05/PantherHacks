//
//  MapVoiceAssistantSheet.swift
//  Venture Local
//

import CoreLocation
import SwiftData
import SwiftUI

struct MapVoiceAssistantSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var transcriber: MapSpeechTranscriptionController

    let cityKey: String
    let exploration: ExplorationCoordinator
    let cachedPOIs: [CachedPOI]
    let referenceLocation: CLLocation?
    let distanceUsesMiles: Bool
    /// When true (map “Explore” toggle), voice results exclude ``discoveredOsmIds``.
    let exploreOnlyUnvisited: Bool
    let discoveredOsmIds: Set<String>
    let onSelectPlace: (CachedPOI) -> Void

    @State private var phase: Phase = .listening
    @State private var ranked: [MapVoiceRankedPlace] = []
    @State private var isEnrichingResults = false
    @FocusState private var queryFieldFocused: Bool

    private enum Phase {
        case listening
        case results
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .listening:
                    listeningContent
                case .results:
                    resultsContent
                }
            }
            .navigationTitle("Search places")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        transcriber.stopListening()
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                queryFieldFocused = true
            }
        }
        .onDisappear {
            transcriber.stopListening()
        }
    }

    private var listeningContent: some View {
        VStack(spacing: 20) {
            if isEnrichingResults {
                ProgressView()
                    .scaleEffect(1.2)
                Text("Looking up place details…")
                    .font(.vlCaption(14))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(VLColor.darkTeal)
            } else if transcriber.isListening {
                ProgressView()
                    .scaleEffect(1.2)
                Text("Listening… speak your request, or stop the mic to edit.")
                    .font(.vlCaption(14))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(VLColor.darkTeal)
            } else if let err = transcriber.errorMessage {
                Text(err)
                    .font(.vlCaption(13))
                    .foregroundStyle(VLColor.burgundy)
                    .multilineTextAlignment(.center)
            } else {
                Text("Type a request or tap the mic to dictate.")
                    .font(.vlCaption(13))
                    .foregroundStyle(VLColor.subtleInk)
                    .multilineTextAlignment(.center)
            }

            HStack(alignment: .top, spacing: 10) {
                TextField("Coffee, playground, bookstore…", text: $transcriber.transcript, axis: .vertical)
                    .font(.vlBody(15))
                    .textFieldStyle(.plain)
                    .lineLimit(3...8)
                    .padding(12)
                    .background(VLColor.mapOverlayBar)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .focused($queryFieldFocused)
                    .disabled(transcriber.isListening)
                    .submitLabel(.search)
                    .onSubmit {
                        if !transcriber.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            runSearchWithEnrichment()
                        }
                    }

                Button {
                    Task {
                        if transcriber.isListening {
                            transcriber.stopListening()
                            queryFieldFocused = true
                        } else {
                            queryFieldFocused = false
                            await transcriber.startListening()
                        }
                    }
                } label: {
                    Image(systemName: transcriber.isListening ? "mic.fill" : "mic")
                        .font(.title3)
                        .foregroundStyle(VLColor.cream)
                        .frame(width: 48, height: 48)
                        .background(transcriber.isListening ? VLColor.darkTeal : VLColor.burgundy)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(VLColor.mutedGold, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .disabled(isEnrichingResults)
                .accessibilityLabel(transcriber.isListening ? "Stop dictation" : "Dictate with voice")
            }

            Button {
                runSearchWithEnrichment()
            } label: {
                Text("Search places")
                    .font(.vlCaption(14).weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(VLColor.burgundy)
            .disabled(
                isEnrichingResults
                    || transcriber.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )

            Text(
                exploreOnlyUnvisited
                    ? "Explore mode: only places you haven’t visited yet. Uses OSM + MapKit; within 40 mi."
                    : "Uses OSM tags on cached places, then MapKit for top picks. Results stay within 40 mi and match your words."
            )
                .font(.vlCaption(11))
                .foregroundStyle(VLColor.subtleInk)
                .multilineTextAlignment(.center)
        }
        .padding(20)
    }

    private var resultsContent: some View {
        List {
            if ranked.isEmpty {
                Text(
                    exploreOnlyUnvisited
                        ? "No unvisited matches in this city. Turn off Explore mode to include places you’ve already been, or try different words."
                        : "No strong matches in this city. Try different words or sync more map data."
                )
                    .font(.vlCaption(13))
                    .foregroundStyle(VLColor.subtleInk)
            } else {
                ForEach(ranked.prefix(10)) { row in
                    Button {
                        onSelectPlace(row.poi)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.poi.name)
                                .font(.vlCaption(15).weight(.semibold))
                                .foregroundStyle(VLColor.darkTeal)
                            HStack {
                                if let cat = DiscoveryCategory(rawValue: row.poi.categoryRaw) {
                                    let chips = PlaceExploreFlavorTags.displayChips(for: row.poi)
                                    Text(chips.isEmpty ? cat.displayName : "\(cat.displayName) · \(chips.joined(separator: " · "))")
                                        .font(.vlCaption(11))
                                        .foregroundStyle(VLColor.subtleInk)
                                        .lineLimit(2)
                                }
                                Spacer()
                                if row.distanceMeters.isFinite {
                                    Text(formatDistance(row.distanceMeters))
                                        .font(.vlCaption(11).weight(.medium))
                                        .foregroundStyle(VLColor.burgundy)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .listStyle(.plain)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Again") {
                    phase = .listening
                    ranked = []
                    transcriber.resetTranscript()
                    transcriber.stopListening()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        queryFieldFocused = true
                    }
                }
            }
        }
    }

    private func runSearchWithEnrichment() {
        transcriber.stopListening()
        let pool = cachedPOIs.filter { poi in
            poi.cityKey == cityKey
                && !POISyncService.isUnwantedPOIName(poi.name)
                && !exploration.shouldHideChainFromDiscoveryMap(poi)
                && (!exploreOnlyUnvisited || !discoveredOsmIds.contains(poi.osmId))
        }
        let transcript = transcriber.transcript
        let ref = referenceLocation
        isEnrichingResults = true
        Task { @MainActor in
            let initial = MapVoicePlaceRanker.ranked(
                candidates: pool,
                query: transcript,
                referenceLocation: ref
            )
            await VoicePlaceEnrichmentService.enrichTopPlacesForVoiceSearch(
                rows: initial,
                modelContext: modelContext,
                maxPlaces: 5
            )
            ranked = MapVoicePlaceRanker.resortWithPostEnrichment(initial, query: transcript)
            phase = .results
            isEnrichingResults = false
        }
    }

    private func formatDistance(_ meters: Double) -> String {
        if distanceUsesMiles {
            let mi = meters / 1609.34
            if mi < 0.1 { return String(format: "%.0f ft", meters * 3.28084) }
            return String(format: "%.1f mi", mi)
        }
        if meters < 1000 { return String(format: "%.0f m", meters) }
        return String(format: "%.1f km", meters / 1000)
    }
}
