import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        return .landscape
    }
}

@main
struct JulpixStatsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var connectionManager = PcConnectionManager()
    @StateObject private var backgroundManager = BackgroundManager()

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environmentObject(connectionManager)
                .environmentObject(backgroundManager)
                .preferredColorScheme(.dark)
                .statusBarHidden(true)
        }
    }
}
