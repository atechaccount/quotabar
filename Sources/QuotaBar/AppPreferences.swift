import Foundation

enum MenuBarDisplayStyle: String, CaseIterable, Identifiable {
    case constrained
    case pinned
    case iconOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .constrained: "Most constrained"
        case .pinned: "Pinned provider"
        case .iconOnly: "Icon only"
        }
    }
}

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
        static let displayStyle = "menuBarDisplayStyle"
        static let pinnedProvider = "pinnedProvider"
        static let readOnly = "readOnlyRefresh"
        static let hiddenProviders = "hiddenProviders"
    }

    private let defaults: UserDefaults

    @Published var refreshInterval: TimeInterval {
        didSet { defaults.set(refreshInterval, forKey: Key.refreshInterval) }
    }

    @Published var displayStyle: MenuBarDisplayStyle {
        didSet { defaults.set(displayStyle.rawValue, forKey: Key.displayStyle) }
    }

    @Published var pinnedProvider: String {
        didSet { defaults.set(pinnedProvider, forKey: Key.pinnedProvider) }
    }

    @Published var readOnlyRefresh: Bool {
        didSet { defaults.set(readOnlyRefresh, forKey: Key.readOnly) }
    }

    @Published private(set) var hiddenProviders: Set<String> {
        didSet { defaults.set(Array(hiddenProviders).sorted(), forKey: Key.hiddenProviders) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        refreshInterval = defaults.object(forKey: Key.refreshInterval) == nil
            ? 120
            : max(1, defaults.double(forKey: Key.refreshInterval))
        displayStyle = MenuBarDisplayStyle(
            rawValue: defaults.string(forKey: Key.displayStyle) ?? "") ?? .constrained
        pinnedProvider = defaults.string(forKey: Key.pinnedProvider) ?? ""
        readOnlyRefresh = defaults.object(forKey: Key.readOnly) as? Bool ?? false
        hiddenProviders = Set(defaults.stringArray(forKey: Key.hiddenProviders) ?? [])
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
