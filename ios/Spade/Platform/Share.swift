import UIKit

// The iPhone's share sheet, opened from code so that Spade learns whether
// something was actually sent. (SwiftUI's ShareLink can't say.)

@MainActor
enum Share {
    /// Whatever is on top of the screen right now, including sheets: the thing to present over.
    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard let window = scene?.windows.first(where: { $0.isKeyWindow }) ?? scene?.windows.first,
              var top = window.rootViewController
        else { return nil }
        while let next = top.presentedViewController { top = next }
        return top
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
