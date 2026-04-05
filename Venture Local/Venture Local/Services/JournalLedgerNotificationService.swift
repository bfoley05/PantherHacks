//
//  JournalLedgerNotificationService.swift
//  Venture Local
//
//  Persists journal notifications and schedules low-interruption local alerts for badge and level-up events.
//

import Foundation
import SwiftData
import UserNotifications

enum JournalLedgerNotificationService {
    static func requestAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
        }
    }

    /// Call after `BadgeCatalog.evaluateAndAward` when `xpBefore` was captured before that call.
    static func recordAfterBadgeEvaluation(
        context: ModelContext,
        newUnlocks: [BadgeUnlock],
        xpBefore: Int,
        xpAfter: Int
    ) throws {
        let levelBefore = LevelFormula.level(for: xpBefore)
        let levelAfter = LevelFormula.level(for: xpAfter)

        for u in newUnlocks {
            let body = "\(u.title) · +\(u.xpAwarded) XP"
            let row = LedgerNotification(
                kind: .badgeUnlocked,
                title: "Badge unlocked",
                body: body,
                badgeCode: u.code
            )
            context.insert(row)
            scheduleLocalPush(
                title: row.title,
                body: body,
                userInfo: ["kind": LedgerNotificationKind.badgeUnlocked.rawValue, "code": u.code]
            )
            InAppToastNotification.post(kind: .badge, title: row.title, subtitle: body)
        }

        if levelAfter > levelBefore {
            let body = "You reached explorer level \(levelAfter)."
            let row = LedgerNotification(
                kind: .levelUp,
                title: "Level up",
                body: body,
                levelReached: levelAfter
            )
            context.insert(row)
            scheduleLocalPush(
                title: row.title,
                body: body,
                userInfo: ["kind": LedgerNotificationKind.levelUp.rawValue, "level": "\(levelAfter)"]
            )
            InAppToastNotification.post(kind: .levelUp, title: "Level \(levelAfter)", subtitle: body)
        }

        if !newUnlocks.isEmpty || levelAfter > levelBefore {
            try context.save()
        }
    }

    /// Road XP (+1) and other direct XP edits that skip badge evaluation.
    static func recordLevelUpFromXPChange(context: ModelContext, xpBefore: Int, xpAfter: Int) throws {
        let lb = LevelFormula.level(for: xpBefore)
        let la = LevelFormula.level(for: xpAfter)
        guard la > lb else { return }
        let body = "You reached explorer level \(la)."
        let row = LedgerNotification(
            kind: .levelUp,
            title: "Level up",
            body: body,
            levelReached: la
        )
        context.insert(row)
        try context.save()
        scheduleLocalPush(
            title: row.title,
            body: body,
            userInfo: ["kind": LedgerNotificationKind.levelUp.rawValue, "level": "\(la)"]
        )
        InAppToastNotification.post(kind: .levelUp, title: "Level \(la)", subtitle: body)
    }

    private static func scheduleLocalPush(title: String, body: String, userInfo: [String: String]) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.userInfo = userInfo
        content.sound = nil
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .passive
        }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req)
    }
}
