import AppKit
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
        static let backingScope = "menuBarBackingScope"
        static let markStyle = "menuBarMarkStyle"
        static let backingColorStyle = "menuBarBackingColorStyle"
        static let backingColorHex = "menuBarBackingColorHex"
        static let backingOpacity = "menuBarBackingOpacity"
        static let textColorStyle = "menuBarTextColorStyle"
        static let textColorHex = "menuBarTextColorHex"
        static let readoutFont = "menuBarReadoutFont"
        static let markSize = "menuBarMarkSize"
        static let markGap = "menuBarMarkGap"
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

    /// How the menu bar item is drawn. Written field by field rather than as one
    /// archived blob, so a stored appearance stays readable and each setting can
    /// fall back to its default on its own.
    @Published var menuBarAppearance: MenuBarAppearance {
        didSet { write(menuBarAppearance) }
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

    /// `darkMenuBar` is only read to migrate the retired greyscale mark style.
    /// It defaults to the running system's appearance; the tests pass it
    /// explicitly, which is also why it is not simply read inline.
    init(defaults: PreferenceStore = UserDefaults.standard, darkMenuBar: Bool? = nil) {
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
        menuBarAppearance = Self.readAppearance(
            from: defaults, darkMenuBar: darkMenuBar ?? Self.systemIsDark)
        // The retired greyscale setting is migrated on read, so write the
        // resolved choice straight back. Without this the migration runs again
        // on every launch and a captain who was on greyscale in the dark would
        // flip to black the first time he launched in the light.
        if defaults.string(forKey: Key.markStyle) == MenuBarMarkStyle.retiredGreyscaleRawValue {
            defaults.set(menuBarAppearance.markStyle.rawValue, forKey: Key.markStyle)
        }
    }

    /// The menu bar's own appearance, which is what a migrated greyscale mark
    /// was being drawn against. Read once at init; `NSApp` may not exist yet
    /// under the test runner, and light is the right answer when it does not.
    static var systemIsDark: Bool {
        guard let appearance = NSApp?.effectiveAppearance else { return false }
        return appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    // MARK: - Menu bar appearance

    private static func readAppearance(
        from defaults: PreferenceStore, darkMenuBar: Bool) -> MenuBarAppearance
    {
        let fallback = MenuBarAppearance.default
        func choice<T: RawRepresentable>(_ key: String, _ fallback: T) -> T
        where T.RawValue == String {
            T(rawValue: defaults.string(forKey: key) ?? "") ?? fallback
        }

        return MenuBarAppearance(
            backingScope: choice(Key.backingScope, fallback.backingScope),
            // Not `choice`: the retired greyscale value has to become black or
            // white rather than fall back to the brand colour.
            markStyle: MenuBarMarkStyle.stored(
                defaults.string(forKey: Key.markStyle), dark: darkMenuBar),
            backingColorStyle: choice(Key.backingColorStyle, fallback.backingColorStyle),
            backingColorHex: defaults.string(forKey: Key.backingColorHex)
                ?? fallback.backingColorHex,
            backingOpacity: defaults.object(forKey: Key.backingOpacity) == nil
                ? fallback.backingOpacity
                : defaults.double(forKey: Key.backingOpacity),
            textColorStyle: choice(Key.textColorStyle, fallback.textColorStyle),
            textColorHex: defaults.string(forKey: Key.textColorHex) ?? fallback.textColorHex,
            font: choice(Key.readoutFont, fallback.font),
            markSize: defaults.object(forKey: Key.markSize) == nil
                ? fallback.markSize : defaults.double(forKey: Key.markSize),
            markGap: defaults.object(forKey: Key.markGap) == nil
                ? fallback.markGap : defaults.double(forKey: Key.markGap))
    }

    private func write(_ appearance: MenuBarAppearance) {
        defaults.set(appearance.backingScope.rawValue, forKey: Key.backingScope)
        defaults.set(appearance.markStyle.rawValue, forKey: Key.markStyle)
        defaults.set(appearance.backingColorStyle.rawValue, forKey: Key.backingColorStyle)
        defaults.set(appearance.backingColorHex, forKey: Key.backingColorHex)
        defaults.set(appearance.backingOpacity, forKey: Key.backingOpacity)
        defaults.set(appearance.textColorStyle.rawValue, forKey: Key.textColorStyle)
        defaults.set(appearance.textColorHex, forKey: Key.textColorHex)
        defaults.set(appearance.font.rawValue, forKey: Key.readoutFont)
        defaults.set(appearance.markSize, forKey: Key.markSize)
        defaults.set(appearance.markGap, forKey: Key.markGap)
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
