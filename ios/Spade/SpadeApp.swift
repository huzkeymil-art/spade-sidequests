import SwiftUI

// Spade for iPhone.
//
// The app is three layers:
//   Core   the rules of the game (shared, tested, no UI)
//   Scene  the 3D world, drawn with SceneKit
//   UI     the screens, drawn with SwiftUI

@main
struct SpadeApp: App {
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
