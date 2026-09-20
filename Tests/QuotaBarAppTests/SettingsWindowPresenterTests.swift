import AppKit
import Testing
@testable import QuotaBar

/// The captain clicked Preferences and nothing appeared. These drive the exact
/// object the Preferences button drives, including the repeat opens and the
/// reopen-after-close that a silently-failing settings scene gets wrong.
@MainActor
struct SettingsWindowPresenterTests {
    private func makePresenter(
        onActivate: @escaping @MainActor () -> Void = {}) -> SettingsWindowPresenter
    {
        SettingsWindowPresenter(hooks: SettingsWindowPresenter.Hooks(
            activate: onActivate,
            makeWindow: {
                let window = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
                    styleMask: [.titled, .closable],
                    backing: .buffered,
                    defer: false)
                window.isReleasedWhenClosed = false
                return window
            }))
    }

    @Test
    func showingActivatesTheAppAndOrdersTheWindowFront() {
        var activations = 0
        let presenter = makePresenter(onActivate: { activations += 1 })

        presenter.show()

        // An accessory app must activate, or the window opens behind everything.
        #expect(activations == 1)
        #expect(presenter.windowsCreated == 1)
        #expect(presenter.isWindowVisible)
    }

    @Test
    func openingAgainReusesTheWindowAndStillBringsItForward() {
        var activations = 0
        let presenter = makePresenter(onActivate: { activations += 1 })

        presenter.show()
        presenter.show()
        presenter.show()

        #expect(presenter.showCount == 3)
        #expect(presenter.windowsCreated == 1, "a second open must not spawn a second window")
        #expect(activations == 3, "every open must re-activate, not just the first")
        #expect(presenter.isWindowVisible)
    }

    @Test
    func theWindowOpensAgainAfterItHasBeenClosed() {
        let presenter = makePresenter()

        presenter.show()
        let first = try! #require(presenter.window)
        first.close()

        #expect(presenter.window == nil, "a closed window must be let go of")
        #expect(!presenter.isWindowVisible)

        presenter.show()

        #expect(presenter.windowsCreated == 2)
        #expect(presenter.isWindowVisible, "the third open is the one that used to fail")
        #expect(presenter.window !== first)
    }

    @Test
    func closingSomeOtherWindowDoesNotDiscardThePreferencesWindow() {
        let presenter = makePresenter()
        presenter.show()
        let owned = presenter.window

        let unrelated = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
            styleMask: [.titled], backing: .buffered, defer: false)
        presenter.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: unrelated))

        #expect(presenter.window === owned)
    }
}
