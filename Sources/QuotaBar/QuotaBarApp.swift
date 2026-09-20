import AppKit
import SwiftUI

@main
struct QuotaBarApp: App {
    @StateObject private var model = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            QuotaMenuView(model: model)
        } label: {
            MenuBarLabel(model: model)
                .task { await runSelfTestIfRequested() }
        }
        .menuBarExtraStyle(.window)
    }

    private func runSelfTestIfRequested() async {
        guard ProcessInfo.processInfo.environment["QUOTABAR_SELFTEST"] == "1" else { return }
        await SelfTest.run(model: model)
        NSApp.terminate(nil)
    }
}

/// Owns the preferences window and the self-check that proves it opens.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["QUOTABAR_VERIFY"] == "1" else { return }
        Task { @MainActor in
            await PreferencesVerification.run()
            NSApp.terminate(nil)
        }
    }
}
