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
            return "That QR isn’t recognized. Scan the code that contains the partner’s image link from partners.json (or a legacy stamp token)."
        case .unknownPartner:
            return "That link doesn’t match any partner image URL in our list."
        case .noAnchorCoordinate:
            return "We can’t verify this place’s location. Open the map near the business to sync places, or ask the partner to update their listing with the team."
        case .tooFar:
            return "Move closer (within about \(Int(ExplorationCoordinator.poiProximityRadiusMeters))m) to scan."
        case .alreadyScannedToday:
            return "You already collected this stamp today. Come back tomorrow."
        case .locationUnavailable:
            return "Turn on location so we can confirm you’re at the partner."
        }
    }
}
