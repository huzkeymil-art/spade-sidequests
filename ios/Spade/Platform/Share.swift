import UIKit

// The iPhone's share sheet, opened from code so that Spade learns whether
// something was actually sent. (SwiftUI's ShareLink can't say.)

@MainActor
enum Share {
    /// The app's window, at the bottom of everything on screen.
    private static func rootViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        let window = scene?.windows.first(where: { $0.isKeyWindow }) ?? scene?.windows.first
        return window?.rootViewController
    }

    /// Whatever is on top of the screen right now, including sheets: the thing to present over.
    static func topViewController() -> UIViewController? {
        guard var top = rootViewController() else { return nil }
        while let next = top.presentedViewController { top = next }
        return top
    }

    /// True while a sheet, an alert or the share sheet is open over the app.
    static var isShowingSomething: Bool {
        guard let root = rootViewController() else { return true }
        return root.presentedViewController != nil
    }

    /// Opens the share sheet with these items: text, file URLs (photos), and so on.
    /// `sent` runs only if the person really sent or copied them.
    static func present(_ items: [Any], sent: @escaping @MainActor () -> Void = {}) {
        guard let top = topViewController() else { return }
        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        sheet.completionWithItemsHandler = { _, completed, _, _ in
            guard completed else { return }
            Task { @MainActor in sent() }
        }
        sheet.popoverPresentationController?.sourceView = top.view
        top.present(sheet, animated: true)
    }
}
