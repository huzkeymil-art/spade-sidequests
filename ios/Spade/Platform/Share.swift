import UIKit

// The iPhone's share sheet, opened from code so that Spade learns whether
// something was actually sent. (SwiftUI's ShareLink can't say.) That way a
// cancelled share doesn't count as "sent".

@MainActor
enum Share {
    /// Opens the share sheet with these items: text, file URLs (photos), and so on.
    /// `sent` runs only if the person really sent or copied them.
    static func present(_ items: [Any], sent: @escaping @MainActor () -> Void) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard let window = scene?.windows.first(where: { $0.isKeyWindow }) ?? scene?.windows.first,
              var top = window.rootViewController
        else { return }
        // Present over whatever is showing, including sheets.
        while let next = top.presentedViewController { top = next }
        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        sheet.completionWithItemsHandler = { _, completed, _, _ in
            guard completed else { return }
            Task { @MainActor in sent() }
        }
        sheet.popoverPresentationController?.sourceView = top.view
        top.present(sheet, animated: true)
    }
}
