//
//  BadgeRuleHelpers.swift
//  Venture Local
//

import Foundation

enum BadgeRuleHelpers {
    /// End-exclusive hour: before 9:00 AM local.
    static func isBefore9AM(_ date: Date, calendar: Calendar = .current) -> Bool {
        calendar.component(.hour, from: date) < 9
    }

    /// At or after 8:00 PM local.
    static func isAtOrAfter8PM(_ date: Date, calendar: Calendar = .current) -> Bool {
        calendar.component(.hour, from: date) >= 20
    }

    /// US-style calendar: Saturday and Sunday.
    static func isWeekend(_ date: Date, calendar: Calendar = .current) -> Bool {
        let wd = calendar.component(.weekday, from: date)
        return wd == 1 || wd == 7
    }

    /// Start of the Saturday that anchors the weekend period containing `date` (Sat–Sun pair).
    static func weekendSaturdayStart(containing date: Date, calendar: Calendar = .current) -> Date {
        let day = calendar.startOfDay(for: date)
        let wd = calendar.component(.weekday, from: day)
        let daysBack: Int = switch wd {
        case 7: 0
        case 1: 1
        default: wd
        }
        return calendar.date(byAdding: .day, value: -daysBack, to: day) ?? day
    }

    /// Clusters event timestamps into outings: new cluster when gap exceeds `gapSeconds` (default 2h).
    static func outingIntervals(
        sortedDates: [Date],
        gapSeconds: TimeInterval = 2 * 60 * 60
    ) -> [(start: Date, end: Date)] {
        guard !sortedDates.isEmpty else { return [] }
        var intervals: [(Date, Date)] = []
        var clusterStart = sortedDates[0]
        var clusterEnd = sortedDates[0]
        for i in 1..<sortedDates.count {
            let t = sortedDates[i]
            if t.timeIntervalSince(clusterEnd) > gapSeconds {
                intervals.append((clusterStart, clusterEnd))
                clusterStart = t
                clusterEnd = t
            } else {
                clusterEnd = t
            }
        }
        intervals.append((clusterStart, clusterEnd))
        return intervals
    }
}
