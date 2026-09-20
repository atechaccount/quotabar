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
        static let didSeedVisibility = "didSeedProviderVisibility"
    }

    private let defaults: PreferenceStore

    @Published var refreshInterval: TimeInterval {
        didSet { defaults.set(refreshInterval, forKey: Key.refreshInterval) }
    }

    @Published var focusMode: MenuBarFocusMode {
        didSet { defaults.set(focusMode.rawValue, forKey: Key.focusMode) }
    }

    /// The sticky menu bar selection. Every write lands in `UserDefaults`, which
    /// is what makes the choice survive closing the popover, moving back to
    /// Overview, quitting, and relaunching.
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

    private(set) var didSeedVisibility: Bool {
        didSet { defaults.set(didSeedVisibility, forKey: Key.didSeedVisibility) }
    }

    init(defaults: PreferenceStore = UserDefaults.standard) {
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
        didSeedVisibility = defaults.bool(forKey: Key.didSeedVisibility)
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

    /// Decides provider visibility once, from the first snapshot that can decide
    /// it. Later snapshots never touch these switches again: a provider the user
    /// turned on stays on when it signs out, and one they turned off stays off
    /// when it starts reporting.
    func seedVisibilityIfNeeded(from snapshot: QuotaSnapshot?) {
        guard !didSeedVisibility else { return }
        guard let seed = ProviderVisibilitySeed.hiddenProviders(from: snapshot) else { return }
        hiddenProviders = seed
        didSeedVisibility = true
    }

    /// Selecting a provider page is also what points the menu bar at it.
    func focus(on provider: String) {
        focusedProvider = provider
        focusMode = .focusedProvider
        didSeedFocus = true
    }

    func isVisible(_ provider: String) -> Bool {
        !hiddenProviders.contains(provider)
    }

    /// Hiding a provider removes its tab and its Overview row. It deliberately
    /// does not rewrite `focusedProvider`: a silent rewrite would lose a choice
    /// the user made explicitly, and the readout already falls back to the app
    /// glyph when the remembered provider is not in the snapshot.
    func setVisible(_ visible: Bool, provider: String) {
        if visible {
            hiddenProviders.remove(provider)
        } else {
            hiddenProviders.insert(provider)
        }
        didSeedVisibility = true
    }
}
