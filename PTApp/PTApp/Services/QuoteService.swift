//
//  QuoteService.swift
//  PTApp
//

import Foundation

struct QuoteEntry: Hashable {
    let author: String
    let text: String
}

enum QuoteService {
    private static var cached: [QuoteEntry]?

    static func loadQuotes() -> [QuoteEntry] {
        if let cached { return cached }

        guard let url = Bundle.main.url(forResource: "quotes", withExtension: "csv", subdirectory: "Resources")
                ?? Bundle.main.url(forResource: "quotes", withExtension: "csv")
        else {
            return [QuoteEntry(author: "Stride", text: "Small steps add up to big recovery.")]
        }

        guard let data = try? String(contentsOf: url, encoding: .utf8) else {
            return [QuoteEntry(author: "Stride", text: "Consistency beats intensity.")]
        }

        var rows: [QuoteEntry] = []
        let lines = data.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard lines.count > 1 else {
            cached = rows
            return rows
        }

        for line in lines.dropFirst() {
            let parsed = parseCSVLine(line)
            guard parsed.count >= 2 else { continue }
            let author = parsed[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let quote = parsed[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if !quote.isEmpty {
                rows.append(QuoteEntry(author: author, text: quote))
            }
        }

        cached = rows
        return rows
    }

    static func randomQuote() -> QuoteEntry {
        let all = loadQuotes()
        guard !all.isEmpty else {
            return QuoteEntry(author: "Stride", text: "You've got this.")
        }
        return all.randomElement()!
    }

    private static let qotdDayKey = "stride_qotd_startOfDay"
    private static let qotdAuthorKey = "stride_qotd_author"
    private static let qotdTextKey = "stride_qotd_text"

    /// One quote per calendar day (local midnight). Persists until the next day.
    static func quoteForToday() -> QuoteEntry {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: Date())
        let defaults = UserDefaults.standard
        if let storedDay = defaults.object(forKey: qotdDayKey) as? TimeInterval,
           cal.isDate(Date(timeIntervalSince1970: storedDay), inSameDayAs: startOfToday),
           let author = defaults.string(forKey: qotdAuthorKey),
           let text = defaults.string(forKey: qotdTextKey),
           !text.isEmpty {
            return QuoteEntry(author: author, text: text)
        }

        let q = randomQuote()
        defaults.set(startOfToday.timeIntervalSince1970, forKey: qotdDayKey)
        defaults.set(q.author, forKey: qotdAuthorKey)
        defaults.set(q.text, forKey: qotdTextKey)
        return q
    }

    /// Minimal CSV parser for "Author","Quote" lines with quoted fields.
    private static func parseCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                result.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        result.append(current)
        return result
    }
}
