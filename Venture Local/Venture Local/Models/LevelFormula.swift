//
//  LevelFormula.swift
//  Venture Local
//
//  Level 0 at 0 XP. Each step to the next level costs more: step(n) = base + n * growth
//  (n = current level). First step (0→1) = 25 XP by default.
//

import Foundation

enum LevelFormula {
    /// XP to go from level `n` → `n + 1` is `firstLevelXPRequirement + n * xpIncreasePerLevel`.
    private static let firstLevelXPRequirement = 25
    private static let xpIncreasePerLevel = 10

    /// Cumulative XP required to **reach** `level` (level 0 → 0 XP).
    static func xpToReach(level: Int) -> Int {
        guard level > 0 else { return 0 }
        var sum = 0
        for n in 0..<level {
            sum += firstLevelXPRequirement + n * xpIncreasePerLevel
        }
        return sum
    }

    /// Highest level achieved at `totalXP` (0 while below first threshold).
    static func level(for totalXP: Int) -> Int {
        guard totalXP > 0 else { return 0 }
        var l = 0
        while l < 10_000, xpToReach(level: l + 1) <= totalXP {
            l += 1
        }
        return l
    }

    /// Cumulative XP at which `level` is first reached (alias for `xpToReach`).
    static func minimumXP(forLevel targetLevel: Int) -> Int {
        xpToReach(level: max(0, targetLevel))
    }

    /// Progress within the current level: XP into this band and XP needed for the full band.
    static func xpIntoCurrentLevel(totalXP: Int) -> (into: Int, needed: Int) {
        let lv = level(for: totalXP)
        let start = xpToReach(level: lv)
        let next = xpToReach(level: lv + 1)
        let span = max(next - start, 1)
        let into = max(0, totalXP - start)
        return (min(into, span), span)
    }
}
