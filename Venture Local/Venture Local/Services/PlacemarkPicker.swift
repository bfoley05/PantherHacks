//
//  PlacemarkPicker.swift
//  Venture Local
//
//  Apple’s `reverseGeocodeLocation` can return multiple placemarks; `marks.first` is not always the
//  best match for the requested coordinate (suburbs, county seats, stale ordering). Prefer the
//  placemark whose `location` is closest to the GPS fix.
//

import CoreLocation
import Foundation

enum PlacemarkPicker {
    static func best(for requestedLocation: CLLocation, marks: [CLPlacemark]) -> CLPlacemark {
        guard !marks.isEmpty else {
            preconditionFailure("PlacemarkPicker.best requires at least one placemark")
        }
        let scored = marks.compactMap { m -> (CLPlacemark, CLLocation)? in
            guard let loc = m.location else { return nil }
            return (m, loc)
        }
        if !scored.isEmpty {
            return scored.min(by: { requestedLocation.distance(from: $0.1) < requestedLocation.distance(from: $1.1) })!.0
        }
        if let withLocality = marks.first(where: { ($0.locality?.isEmpty == false) }) {
            return withLocality
        }
        return marks[0]
    }
}
