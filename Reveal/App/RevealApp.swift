import SwiftUI
import UIKit

@main
struct RevealApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var auth = AuthStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(auth)
                .task {
                    await auth.bootstrap()
                    await PushNotificationManager.shared.bootstrap()
                }
                .onChange(of: auth.userEmail) { _, _ in
                    PushNotificationManager.shared.userDidChange()
                }
        }
    }
}

/// Minimal delegate that just forwards the APNs device token to our
/// PushNotificationManager. SwiftUI doesn't have a native hook for this.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            PushNotificationManager.shared.didReceiveDeviceToken(deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[Push] APNs registration failed: \(error.localizedDescription)")
    }
}
