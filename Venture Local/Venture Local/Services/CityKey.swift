//
//  CityKey.swift
//  Venture Local
//
//  Stable key for grouping progress to a locality (MVP: geocoded components).
//

import Foundation

enum CityKey {
    static func make(locality: String?, administrativeArea: String?, country: String?) -> String {
        let l = (locality ?? "unknown").replacingOccurrences(of: " ", with: "_")
        let a = (administrativeArea ?? "").replacingOccurrences(of: " ", with: "_")
        let c = (country ?? "").replacingOccurrences(of: " ", with: "_")
        return [l, a, c].filter { !$0.isEmpty }.joined(separator: "__")
    }
}
