import Foundation
import BackgroundTasks
import UserNotifications
import ClearOutsideCore

/// Periodically re-checks the forecast in the background and fires a local notification
/// the first time the upcoming Friday/Saturday/Sunday night looks good for stargazing.
/// Runs entirely locally (BGAppRefreshTask + UNUserNotificationCenter) - no APNs/paid
/// developer account required.
enum BackgroundRefreshManager {
    static let taskIdentifier = "com.mariuste.Clear-Outside-Widget.refresh"
    private static let lastGoodStateKey = "com.mariuste.ClearOutsideWidget.lastWeekendWasGood"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            // swiftlint:disable:next force_cast
            handle(task: task as! BGAppRefreshTask)
        }
    }

    static func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 2 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private static func handle(task: BGAppRefreshTask) {
        scheduleNextRefresh()

        let work = Task {
            await checkWeekendAndNotifyIfNeeded()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            work.cancel()
        }
    }

    @discardableResult
    static func checkWeekendAndNotifyIfNeeded() async -> Bool {
        let repository = ForecastRepository()
        guard let cache = try? await repository.refresh() else { return false }
        return evaluateAndNotify(using: cache)
    }

    /// Fires a notification only on the "not good" -> "good" transition, never on repeated
    /// "still good" checks - persisted locally since there is no App Group to share it in.
    @discardableResult
    static func evaluateAndNotify(using cache: ForecastCache) -> Bool {
        let isGoodNow = WeekendQualityEvaluator.isWeekendGood(in: cache)
        let wasGoodBefore = UserDefaults.standard.bool(forKey: lastGoodStateKey)
        UserDefaults.standard.set(isGoodNow, forKey: lastGoodStateKey)

        guard isGoodNow, !wasGoodBefore else { return false }

        let content = UNMutableNotificationContent()
        content.title = "Gutes Wochenend-Wetter für Sternengucker"
        content.body = "Die Vorhersage fürs Wochenende hat sich verbessert - gute Bedingungen zum Sternegucken."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "weekend-quality-improved", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
        return true
    }
}
