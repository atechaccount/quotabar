import Foundation
import QuotaBarCore

@MainActor
final class AppPreferences: ObservableObject {
    static let refreshIntervals: [(label: String, seconds: TimeInterval)] = [
        ("30 seconds", 30),
        ("1 minute", 60),
        ("2 minutes", 120),
        ("5 minutes", 300),
        ("15 minutes", 900),
        ("30 minutes", 1_800),
    ]

    private enum Key {
        static let refreshInterval = "refreshInterval"
        static let focusMode = "menuBarFocusMode"
        static let focusedProvider = "focusedProvider"
        static let didSeedFocus = "didSeedFocusedProvider"
        static let readOnly = "readOnlyRefresh"
        static let hiddenProviders = "hiddenProviders"
    }

    private let defaults: UserDefaults

    @Published var refreshInterval: TimeInterval {
        didSet { defaults.set(refreshInterval, forKey: Key.refreshInterval) }
    }

    @Published var focusMode: MenuBarFocusMode {
        didSet { defaults.set(focusMode.rawValue, forKey: Key.focusMode) }
    }

    @Published var focusedProvider: String {
        didSet { defaults.set(focusedProvider, forKey: Key.focusedProvider) }
    }

    @Published var readOnlyRefresh: Bool {
        didSet { defaults.set(readOnlyRefresh, forKey: Key.readOnly) }
    }

    @Published private(set) var hiddenProviders: Set<String> {
        didSet { defaults.set(Array(hiddenProviders).sorted(), forKey: Key.hiddenProviders) }
    }

    private var didSeedFocus: Bool {
        didSet { defaults.set(didSeedFocus, forKey: Key.didSeedFocus) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        refreshInterval = defaults.object(forKey: Key.refreshInterval) == nil
            ? 120
            : max(1, defaults.double(forKey: Key.refreshInterval))
        focusMode = MenuBarFocusMode(
            rawValue: defaults.string(forKey: Key.focusMode) ?? "") ?? .focusedProvider
        focusedProvider = defaults.string(forKey: Key.focusedProvider) ?? ""
        readOnlyRefresh = defaults.object(forKey: Key.readOnly) as? Bool ?? false
        hiddenProviders = Set(defaults.stringArray(forKey: Key.hiddenProviders) ?? [])
        didSeedFocus = defaults.bool(forKey: Key.didSeedFocus)
    }

    /// Picks the initial focus from the first real snapshot, once. After that the
    /// captain's own choice always wins, even if he focuses a signed-out provider.
    func seedFocusIfNeeded(from snapshot: QuotaSnapshot?) {
        guard !didSeedFocus else { return }
        guard focusedProvider.isEmpty else {
            didSeedFocus = true
            return
        }
        guard let seed = MenuBarReadoutResolver.defaultFocus(in: snapshot) else { return }
        focusedProvider = seed
        didSeedFocus = true
    }

    func focus(on provider: String) {
        focusedProvider = provider
        focusMode = .focusedProvider
        didSeedFocus = true
    }

    func isVisible(_ provider: String) -> Bool {
        !hiddenProviders.contains(provider)
    }

    func setVisible(_ visible: Bool, provider: String) {
        if visible {
            hiddenProviders.remove(provider)
        } else {
            hiddenProviders.insert(provider)
        }
    }
}
