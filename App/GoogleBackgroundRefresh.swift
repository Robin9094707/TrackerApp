import Foundation
import BackgroundTasks
import SpotIntegration

@MainActor enum GoogleBackgroundRefresh {
    static let identifier = "eu.rjuhas.rjtracker.google-history"
    static func scheduleIfNeeded() {
        let google = GoogleTrackerStore.shared
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        guard google.hasCredentials, google.backgroundHistoryEnabled, google.refreshInterval > 0,
              google.trackers.contains(where: \.historyEnabled) else { return }
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do { try BGTaskScheduler.shared.submit(request) }
        catch { DebugLogger.shared.log("Google background request not scheduled: \(error.localizedDescription)") }
    }
    static func run() async {
        defer { scheduleIfNeeded() }
        let google = GoogleTrackerStore.shared
        guard google.hasCredentials, google.backgroundHistoryEnabled, google.refreshInterval > 0,
              google.trackers.contains(where: \.historyEnabled), !Task.isCancelled else { return }
        await google.refresh()
        // Keep the OS-granted task alive briefly for asynchronous Google push reports.
        // SwiftUI cancels this sleep when the OS expires the background task.
        if !Task.isCancelled { try? await Task.sleep(for: .seconds(20)) }
    }
}
