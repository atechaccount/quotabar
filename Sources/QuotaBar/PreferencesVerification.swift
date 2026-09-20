import AppKit
import SwiftUI

/// In-app verification hook for the preferences window.
///
/// Runs the real `SettingsWindowPresenter` against a real `NSWindow` in the built
/// app, opening it three times with a close in between, and prints what actually
/// happened. Launch the bundle with `QUOTABAR_VERIFY=1` to see it; the app exits
/// immediately afterwards and never touches the menu bar or any system dialog.
@MainActor
enum PreferencesVerification {
    static func run() async {
        let model = AppModel()
        let presenter = SettingsWindowPresenter(
            hooks: .live(content: { AnyView(PreferencesView(model: model)) }))

        // Activation and key-window status are granted by the window server
        // asynchronously, so yield to the run loop before reporting focus.
        func settle() async {
            try? await Task.sleep(nanoseconds: 600_000_000)
        }

        func report(_ step: String) async {
            await settle()
            let window = presenter.window
            print("""
                QuotaBar verify step=\(step) \
                visible=\(presenter.isWindowVisible) \
                key=\(window?.isKeyWindow ?? false) \
                onscreen=\(window?.isOnActiveSpace ?? false) \
                canBecomeKey=\(window?.canBecomeKey ?? false) \
                appActive=\(NSApp.isActive) \
                title=\(window?.title ?? "<none>") \
                shows=\(presenter.showCount) created=\(presenter.windowsCreated) \
                activations=\(presenter.activationCount)
                """)
        }

        await settle()

        presenter.show()
        await report("first-open")

        presenter.show()
        await report("second-open-reuses-window")

        presenter.window?.performClose(nil)
        presenter.window?.close()
        print("QuotaBar verify step=closed windowReleased=\(presenter.window == nil)")

        presenter.show()
        await report("reopen-after-close")
    }
}
