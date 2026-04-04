//
//  StampQRScanError.swift
//  Venture Local
//

import Foundation

enum StampQRScanError: LocalizedError {
    case invalidQR
    case unknownPartner
    case noAnchorCoordinate
    case tooFar
    case alreadyScannedToday
    case locationUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidQR:
            return "That QR code isn’t a Venture Local partner stamp."
        case .unknownPartner:
            return "This partner isn’t in our list yet."
        case .noAnchorCoordinate:
            return "We can’t verify this place’s location — sync the map near the business or ask the partner to add coordinates to partners.json."
        case .tooFar:
            return "Move closer (within about \(Int(ExplorationCoordinator.poiProximityRadiusMeters))m) to scan."
        case .alreadyScannedToday:
            return "You already collected this stamp today. Come back tomorrow."
        case .locationUnavailable:
            return "Turn on location so we can confirm you’re at the partner."
        }
    }
}
