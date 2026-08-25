import Foundation
import UIKit
import UserNotifications

@MainActor
final class PushManager {
    static let shared = PushManager()
    private(set) var token: String? = UserDefaults.standard.string(forKey: "apnsToken")

    func requestAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            if granted { UIApplication.shared.registerForRemoteNotifications() }
            DebugLogger.shared.log("Notification authorization: \(granted)")
        } catch { DebugLogger.shared.log("Notification authorization failed: \(error)") }
    }

    func receivedToken(_ data: Data) {
        let value = data.map { String(format: "%02x", $0) }.joined()
        token = value
        UserDefaults.standard.set(value, forKey: "apnsToken")
        NotificationCenter.default.post(name: .apnsTokenAvailable, object: value)
        DebugLogger.shared.log("APNs device token available")
    }

    func registerIfPossible() async {
        guard let token, APIClient.shared.baseURL != nil else { return }
        let info = Bundle.main.infoDictionary
        let appVersion = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        do {
            _ = try await APIClient.shared.registerPush(
                token: token,
                label: UIDevice.current.name,
                model: UIDevice.current.model,
                systemVersion: UIDevice.current.systemVersion,
                appVersion: appVersion
            )
            DebugLogger.shared.log("APNs token registered with server")
        } catch { DebugLogger.shared.log("APNs server registration failed: \(error.localizedDescription)") }
    }

    func scheduleLocal(event: AlertEvent) async {
        let content = UNMutableNotificationContent()
        content.title = event.title ?? "Tracker-Ereignis"
        content.body = event.body ?? "Es gibt eine neue Meldung."
        content.sound = .default
        content.userInfo = ["event_id": event.id, "tracker_ref": event.trackerRef ?? ""]
        let request = UNNotificationRequest(identifier: "local-\(event.id)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
