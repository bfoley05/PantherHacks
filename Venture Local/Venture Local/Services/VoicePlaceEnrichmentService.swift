//
//  VoicePlaceEnrichmentService.swift
//  Venture Local
//
//  Refines top voice-search hits with MapKit local search (cached on ``CachedPOI``).
//  MapKit requests run in parallel (small batches) so latency stays low; only `Sendable` payloads cross tasks.
//

import CoreLocation
import Foundation
import MapKit
import SwiftData

enum VoicePlaceEnrichmentService {
    private static let mapKitRefreshInterval: TimeInterval = 10 * 24 * 3600
    private static let parallelBatchSize = 3

    private enum MapKitFetchOutcome: Sendable {
        case skippedFresh
        case noMatch
        case matched(String)
    }

    /// Network-only: resolve MapKit POI category string near coordinate (no SwiftData access).
    private static func fetchMapKitCategoryDescription(
        name: String,
        latitude: Double,
        longitude: Double,
        existingJSON: String?
    ) async -> MapKitFetchOutcome {
        if let meta = POIExtendedMetadataCodec.decode(existingJSON),
           let mk = meta.mapKit,
           Date().timeIntervalSince(mk.refinedAt) < mapKitRefreshInterval {
            return .skippedFresh
        }
        let coord = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        guard CLLocationCoordinate2DIsValid(coord) else { return .noMatch }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return .noMatch }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmedName
        request.region = MKCoordinateRegion(
            center: coord,
            span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
        )

        guard let response = try? await MKLocalSearch(request: request).start(),
              let item = response.mapItems.first else { return .noMatch }

        let ic = item.placemark.coordinate
        guard CLLocationCoordinate2DIsValid(ic) else { return .noMatch }
        let d = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            .distance(from: CLLocation(latitude: ic.latitude, longitude: ic.longitude))
        guard d < 140 else { return .noMatch }

        let desc = item.pointOfInterestCategory.map { String(describing: $0) } ?? "matched"
        return .matched(desc)
    }

    /// Updates ``CachedPOI.extendedMetadataJSON`` for the first `maxPlaces` rows.
    static func enrichTopPlacesForVoiceSearch(
        rows: [MapVoiceRankedPlace],
        modelContext: ModelContext,
        maxPlaces: Int = 5
    ) async {
        let slice = Array(rows.prefix(maxPlaces))
        guard !slice.isEmpty else { return }

        struct Payload: Sendable {
            let index: Int
            let name: String
            let latitude: Double
            let longitude: Double
            let existingJSON: String?
        }

        let payloads: [Payload] = slice.enumerated().map { i, row in
            Payload(
                index: i,
                name: row.poi.name,
                latitude: row.poi.latitude,
                longitude: row.poi.longitude,
                existingJSON: row.poi.extendedMetadataJSON
            )
        }

        var outcomes: [Int: MapKitFetchOutcome] = [:]
        outcomes.reserveCapacity(payloads.count)

        var batchStart = 0
        while batchStart < payloads.count {
            let batchEnd = min(batchStart + parallelBatchSize, payloads.count)
            let batch = Array(payloads[batchStart..<batchEnd])
            await withTaskGroup(of: (Int, MapKitFetchOutcome).self) { group in
                for p in batch {
                    group.addTask {
                        let o = await fetchMapKitCategoryDescription(
                            name: p.name,
                            latitude: p.latitude,
                            longitude: p.longitude,
                            existingJSON: p.existingJSON
                        )
                        return (p.index, o)
                    }
                }
                for await (idx, o) in group {
                    outcomes[idx] = o
                }
            }
            batchStart = batchEnd
        }

        for p in payloads {
            guard case .matched(let desc) = outcomes[p.index] else { continue }
            let poi = slice[p.index].poi
            poi.extendedMetadataJSON = POIExtendedMetadataCodec.mergeMapKit(
                into: poi.extendedMetadataJSON,
                categoryDescription: desc
            )
        }

        try? modelContext.save()
    }
}
