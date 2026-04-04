//
//  LevelFormula.swift
//  Venture Local
//
//  Spec: level = floor(100 * sqrt(totalXP / 10000))
//

import Foundation

enum LevelFormula {
    static func level(for totalXP: Int) -> Int {
        guard totalXP > 0 else { return 0 }
        let x = Double(totalXP) / 10_000
        return Int(floor(100 * sqrt(x)))
    }

    /// XP threshold where `level(for:)` first reaches `targetLevel + 1`.
    static func minimumXP(forLevel targetLevel: Int) -> Int {
        guard targetLevel >= 0 else { return 0 }
        let need = pow(Double(targetLevel + 1) / 100, 2) * 10_000
        return Int(ceil(need))
    }

    static func xpIntoCurrentLevel(totalXP: Int) -> (into: Int, needed: Int) {
        let lv = level(for: totalXP)
        let start = minimumXP(forLevel: lv - 1)
        let next = minimumXP(forLevel: lv)
        let span = max(next - start, 1)
        let into = max(0, totalXP - start)
        return (min(into, span), span)
    }
}
