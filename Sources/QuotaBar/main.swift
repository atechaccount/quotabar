import AppKit

/// QuotaBar is an AppKit application that happens to draw its content with
/// SwiftUI, not a SwiftUI `App` with a `MenuBarExtra`.
///
/// That is deliberate. The menu bar item is an `NSStatusItem` whose button gets a
/// real `NSImage` and a title; the `MenuBarExtra` label bridge dropped the custom
/// shape QuotaBar used to pass it, leaving a percentage with no provider mark.
MainActor.assumeIsolated {
    let application = NSApplication.shared
    // Held by the application for its whole lifetime; `NSApplication.delegate`
    // is a weak reference, so it needs an owner that outlives this scope.
    application.delegate = AppDelegate.shared
    application.setActivationPolicy(.accessory)
    application.run()
}
