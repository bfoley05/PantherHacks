//
//  OverpassModels.swift
//  Venture Local
//

import Foundation

struct OverpassResponse: Decodable {
    let elements: [OverpassElement]
}

struct OverpassElement: Decodable {
    let type: String
    let id: Int64
    let lat: Double?
    let lon: Double?
    let center: OverpassCenter?
    let tags: [String: String]?
    let geometry: [OverpassLonLat]?
}

struct OverpassCenter: Decodable {
    let lat: Double
    let lon: Double
}

struct OverpassLonLat: Decodable {
    let lat: Double
    let lon: Double
}
