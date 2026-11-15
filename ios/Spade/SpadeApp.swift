import CloudKit
import SwiftUI
import UIKit

// Spade for iPhone.
//
// The app is three layers:
//   Core   the rules of the game (shared, tested, no UI)
//   Scene  the 3D world, drawn with SceneKit
//   UI     the screens, drawn with SwiftUI

@main
struct SpadeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = DemoMode.makeStore()
    @StateObject private var stage = StageController()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(stage)
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Things the system hands to the app

/// Where things from the system wait for the store: family invites that were
/// opened, and nudges from iCloud that a page has changed.
@MainActor
enum CloudDoor {
    private static var waiting: [CKShare.Metadata] = []

    /// What to do with an invite. Invites that arrived before anyone was listening are handed over at once.
    static var onInvite: (@MainActor (CKShare.Metadata) -> Void)? {
        didSet {
            guard let onInvite else { return }
            let queued = waiting
            waiting = []
            for metadata in queued { onInvite(metadata) }
        }
    }

    /// What to do when iCloud says something changed.
    static var onNudge: (@MainActor () async -> Void)?

    static func invite(_ metadata: CKShare.Metadata) {
        if let onInvite {
            onInvite(metadata)
        } else {
            waiting.append(metadata)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // iCloud nudges the app when a family page changes. The nudges are silent:
        // no permission is asked for, and nothing is shown.
        if DemoMode.requested == nil { application.registerForRemoteNotifications() }
        return true
    }

    /// Gives each window a delegate of ours as well, which is where iOS delivers family invites.
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task { @MainActor in
            await CloudDoor.onNudge?()
            completionHandler(.newData)
        }
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    /// Spade wasn't running, and was opened by tapping an invite.
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            CloudDoor.invite(metadata)
        }
    }

    /// Spade was already running when an invite was tapped.
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        CloudDoor.invite(cloudKitShareMetadata)
    }
}
