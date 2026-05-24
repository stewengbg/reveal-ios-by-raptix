import Foundation
import UIKit
import UserNotifications

/// Owns the APNs device token lifecycle:
///   1. Asks the user for notification permission (once).
///   2. Registers with APNs to obtain a device token.
///   3. POSTs the token to our `register-push-token` edge function so
///      Supabase can target this device for queue-alert pushes.
///
/// Called from `RevealApp` on launch and re-called every time a user
/// signs in (so the token gets associated with the right user_id).
@MainActor
final class PushNotificationManager: NSObject, ObservableObject {
    static let shared = PushNotificationManager()

    /// Latest device token in hex, populated by AppDelegate when APNs
    /// hands it to us. We re-send to the backend whenever this OR the
    /// signed-in user changes.
    @Published private(set) var deviceTokenHex: String?

    private var lastRegisteredKey: String?  // "userId|tokenHex" — skip resend if unchanged
    private let storageKey = "reveal.push.lastRegisteredKey"

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        lastRegisteredKey = UserDefaults.standard.string(forKey: storageKey)
    }

    /// Request notification permission and register for remote notifications
    /// in one shot. Safe to call multiple times — iOS no-ops after the
    /// first decision; we just don't re-prompt.
    func bootstrap() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            guard granted else {
                print("[Push] user denied notification permission")
                return
            }
            UIApplication.shared.registerForRemoteNotifications()
        } catch {
            print("[Push] permission request failed: \(error.localizedDescription)")
        }
    }

    /// Called from the AppDelegate when APNs delivers our token.
    func didReceiveDeviceToken(_ tokenData: Data) {
        let hex = tokenData.map { String(format: "%02x", $0) }.joined()
        deviceTokenHex = hex
        Task { await maybeRegisterWithBackend() }
    }

    /// Called when a user signs in (or out). For sign-out we don't remove
    /// the token — keeping it lets cron-driven pushes still reach the
    /// device. The new sign-in re-associates the token with the new user.
    func userDidChange() {
        Task { await maybeRegisterWithBackend() }
    }

    private func maybeRegisterWithBackend() async {
        guard let token = deviceTokenHex else { return }
        do {
            let session = try await SupabaseService.client.auth.session
            let key = "\(session.user.id.uuidString.lowercased())|\(token)"
            if key == lastRegisteredKey {
                return  // unchanged, no need to spam the backend
            }
            try await PushTokenRepository.register(token: token)
            lastRegisteredKey = key
            UserDefaults.standard.set(key, forKey: storageKey)
            print("[Push] registered token for \(session.user.email ?? "?")")
        } catch {
            print("[Push] backend register failed: \(error.localizedDescription)")
        }
    }
}

// MARK: – Foreground display behaviour

extension PushNotificationManager: UNUserNotificationCenterDelegate {
    /// Show the notification banner even when the app is in the foreground —
    /// the queue-alert banner is exactly the thing the user needs to see
    /// even if they happen to have the app open.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }
}
