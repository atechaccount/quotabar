import AppKit

/// Owns the model, the menu bar item, and the two evidence hooks.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let shared = AppDelegate()

    private var model: AppModel?
    private(set) var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let environment = ProcessInfo.processInfo.environment

        // The preferences-window check builds its own model and never touches the
        // menu bar, so it runs before anything else is created.
        if environment["QUOTABAR_VERIFY"] == "1" {
            Task { @MainActor in
                await PreferencesVerification.run()
                NSApp.terminate(nil)
            }
            return
        }

        if let directory = environment["QUOTABAR_RENDER"], !directory.isEmpty {
            Task { @MainActor in
                await RenderCheck.run(into: directory)
                NSApp.terminate(nil)
            }
            return
        }

        if environment["QUOTABAR_COMPARE_QUOTA"] == "1" {
            Task { @MainActor in
                await QuotaCompare.run()
                NSApp.terminate(nil)
            }
            return
        }

        let model = AppModel()
        self.model = model
        let statusItem = StatusItemController(model: model)
        self.statusItem = statusItem
        model.statusItemAppeared()

        if environment["QUOTABAR_SELFTEST"] == "1" {
            Task { @MainActor in
                await SelfTest.run(model: model, statusItem: statusItem)
                NSApp.terminate(nil)
            }
        }
    }
}
