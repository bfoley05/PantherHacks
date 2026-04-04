//
//  StrideModels.swift
//  PTApp
//

import Foundation

struct PTExercise: Identifiable, Hashable {
    let id: UUID
    var name: String
    var sets: Int
    var reps: Int
    var lastFormScore: Int?
    var isDone: Bool

    init(
        id: UUID = UUID(),
        name: String,
        sets: Int,
        reps: Int,
        lastFormScore: Int? = nil,
        isDone: Bool = false
    ) {
        self.id = id
        self.name = name
        self.sets = sets
        self.reps = reps
        self.lastFormScore = lastFormScore
        self.isDone = isDone
    }
}

struct MilestoneProgress {
    var title: String
    var detail: String
    var progress: Double
}

struct TimelinePoint: Identifiable {
    let id = UUID()
    var date: Date
    var painLevel: Double
    var functionLevel: Double
}

struct SessionHistoryItem: Identifiable {
    let id: UUID
    var date: Date
    var exercises: [String]
    var formScore: Int
    var painBefore: Int
    var painAfter: Int
    var note: String
    var hasVideoHighlight: Bool

    init(
        id: UUID = UUID(),
        date: Date,
        exercises: [String],
        formScore: Int,
        painBefore: Int,
        painAfter: Int,
        note: String,
        hasVideoHighlight: Bool = true
    ) {
        self.id = id
        self.date = date
        self.exercises = exercises
        self.formScore = formScore
        self.painBefore = painBefore
        self.painAfter = painAfter
        self.note = note
        self.hasVideoHighlight = hasVideoHighlight
    }
}

struct MilestoneBadge: Identifiable {
    var id: String { title }
    var title: String
    var icon: String
    var date: Date
}

enum BodyRegion: String, CaseIterable, Identifiable {
    case head, neck, shoulderL, shoulderR, elbowL, elbowR
    case wristL, wristR, chest, upperBack, lowerBack
    case hipL, hipR, kneeL, kneeR, ankleL, ankleR

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .head: return "Head"
        case .neck: return "Neck"
        case .shoulderL: return "Left shoulder"
        case .shoulderR: return "Right shoulder"
        case .elbowL: return "Left elbow"
        case .elbowR: return "Right elbow"
        case .wristL: return "Left wrist"
        case .wristR: return "Right wrist"
        case .chest: return "Chest"
        case .upperBack: return "Upper back"
        case .lowerBack: return "Lower back"
        case .hipL: return "Left hip"
        case .hipR: return "Right hip"
        case .kneeL: return "Left knee"
        case .kneeR: return "Right knee"
        case .ankleL: return "Left ankle"
        case .ankleR: return "Right ankle"
        }
    }
}

enum PainLevel: Int, CaseIterable, Identifiable {
    case none = 0
    case mild = 1
    case moderate = 2
    case severe = 3

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .none: return "None"
        case .mild: return "Mild"
        case .moderate: return "Moderate"
        case .severe: return "Severe"
        }
    }

    var colorName: String {
        switch self {
        case .none: return "green"
        case .mild: return "yellow"
        case .moderate: return "orange"
        case .severe: return "red"
        }
    }
}
