//
//  AppState.swift
//  PTApp
//

import Combine
import Foundation
import SwiftUI

final class AppState: ObservableObject {
    @Published var userName: String = "Alex"
    @Published var strideStreakDays: Int = 12
    @Published var recoveryScore: Int = 86
    @Published var recoveryDeltaFromYesterday: Int = 4

    @Published var milestone: MilestoneProgress = .init(
        title: "Your next milestone",
        detail: "3 more days until you can ditch the brace",
        progress: 0.74
    )

    @Published var exercises: [PTExercise] = [
        PTExercise(name: "Supine Glute Bridge", sets: 3, reps: 12, lastFormScore: 92),
        PTExercise(name: "Clamshells", sets: 3, reps: 15, lastFormScore: 88),
        PTExercise(name: "Mini Squat to Box", sets: 2, reps: 10, lastFormScore: 90),
    ]

    @Published var todayPainEmoji: String?
    @Published var todaySwellingDots: Int = 0
    @Published var todayNote: String = ""

    @Published var bodyPainByRegion: [BodyRegion: PainLevel] = [:]

    @Published var selectedTimelineSession: UUID?

    @Published var ghostOpacity: Double = 0.75
    @Published var audioFeedbackEnabled: Bool = true
    @Published var privacyLocalOnly: Bool = true

    @Published var kneeSwelling: PainLevel = .none
    @Published var kneeExtensionDegrees: Double = -5
    @Published var kneeExtensionTarget: Double = 0
    @Published var sensationNote: String = ""

    func greetingPrefix(at date: Date = .now) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Good night"
        }
    }
}
