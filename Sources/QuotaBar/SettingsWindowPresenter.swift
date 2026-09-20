import AppKit
import SwiftUI

/// Presents the preferences window.
///
/// SwiftUI's `Settings` scene is unreliable in an `LSUIElement` app driven from a
/// `MenuBarExtra`: `showSettingsWindow:` is dispatched to a responder chain that an
/// accessory app has not activated, so the click silently does nothing. This owns a
/// plain `NSWindow` instead and always performs the three steps that actually make a
/// window appear for an accessory app: activate the app, order the window front, and
/// make it key. It also survives the window being closed, by rebuilding on demand.
@MainActor
final class SettingsWindowPresenter: NSObject, NSWindowDelegate {
    struct Hooks {
        var activate: @MainActor () -> Void
        var makeWindow: @MainActor () -> NSWindow

        @MainActor
        static func live(content: @escaping @MainActor () -> AnyView) -> Hooks {
            Hooks(
                activate: { NSApp.activate(ignoringOtherApps: true) },
                makeWindow: {
                    let window = NSWindow(
                        contentRect: NSRect(x: 0, y: 0, width: 460, height: 520),
                        styleMask: [.titled, .closable, .miniaturizable],
                        backing: .buffered,
                        defer: false)
                    window.title = "QuotaBar Preferences"
                    window.contentView = NSHostingView(rootView: content())
                    window.isReleasedWhenClosed = false
                    window.center()
                    return window
                })
        }
    }

    private let hooks: Hooks
    private(set) var window: NSWindow?

    /// Counters exist so a test - and the in-app verification hook - can prove the
    /// full show path ran, including on repeat opens and after a close.
    private(set) var showCount = 0
    private(set) var windowsCreated = 0
    private(set) var activationCount = 0

    init(hooks: Hooks) {
        self.hooks = hooks
    }

    func show() {
        showCount += 1

        let target: NSWindow
        if let existing = window {
            target = existing
        } else {
            target = hooks.makeWindow()
            windowsCreated += 1
            target.delegate = self
            window = target
        }

        // An accessory app owns no active window, so ordering front without
        // activating first leaves the window behind whatever app has focus.
        hooks.activate()
        activationCount += 1
        target.makeKeyAndOrderFront(nil)
    }

    /// Dropping the closed window is what makes the second and third open work:
    /// a released or zombie window would otherwise be reused and never appear.
    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, closing === window else { return }
        window = nil
    }

    var isWindowVisible: Bool {
        window?.isVisible ?? false
    }
}
