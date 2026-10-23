import AppKit
import UserNotifications

/// Posts "memory freed" notifications. Accessory apps count as foreground to macOS, so the
/// delegate asks for banners even while the app is "active".
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    /// Asks for permission the first time. Returns whether notifications can be shown.
    func requestAuthorization() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert])) ?? false
        default:
            return false
        }
    }

    /// True when the user turned notifications off for this app in System Settings.
    func isDenied() async -> Bool {
        await center.notificationSettings().authorizationStatus == .denied
    }

    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(Bundle.main.bundleIdentifier ?? "")")!
        NSWorkspace.shared.open(url)
    }

    func post(_ report: CleanReport) async {
        guard await requestAuthorization() else {
            Log.app.info("Notification not shown: notifications are turned off for this app")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = report.freed > 0 ? "Freed \(ByteFormat.string(report.freed))" : "Memory cleaned"
        var lines = [report.trigger.title]
        lines.append("\(ByteFormat.string(report.after.used)) used · Swap \(ByteFormat.string(report.after.swapUsed))")
        if report.needsSetup { lines.append("Deep clean needs one-time setup in Settings.") }
        content.body = lines.joined(separator: "\n")
        let request = UNNotificationRequest(identifier: "clean-\(report.finished.timeIntervalSince1970)", content: content, trigger: nil)
        do {
            try await center.add(request)
        } catch {
            Log.app.error("Notification failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
