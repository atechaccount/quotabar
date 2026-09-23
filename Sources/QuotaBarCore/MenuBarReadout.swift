import Foundation

/// What the menu bar item shows. A focused provider is the default because an
/// unattributed percentage - especially one picked because it happened to be the
/// lowest anywhere - tells you nothing about which subscription it describes.
public enum MenuBarFocusMode: String, CaseIterable, Identifiable, Sendable {
    case focusedProvider
    case lowestOfShown
    case iconOnly

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .focusedProvider: "Focused provider"
        case .lowestOfShown: "Lowest of shown"
        case .iconOnly: "Icon only"
        }
    }
}

public struct MenuBarReadout: Sendable, Equatable {
    /// Provider key, used to pick the brand mark. `nil` renders the app's own glyph.
    public let provider: String?
    public let providerLabel: String?
    public let percentRemaining: Double?
    public let windowLabel: String?
    public let extraUsageSpent: String?
    public let usageState: QuotaUsageState

    public init(
        provider: String?,
        providerLabel: String?,
        percentRemaining: Double?,
        windowLabel: String?,
        extraUsageSpent: String? = nil,
        usageState: QuotaUsageState = .unknown)
    {
        self.provider = provider
        self.providerLabel = providerLabel
        self.percentRemaining = percentRemaining
        self.windowLabel = windowLabel
        self.extraUsageSpent = extraUsageSpent
        self.usageState = usageState
    }

    public static let empty = MenuBarReadout(
        provider: nil, providerLabel: nil, percentRemaining: nil, windowLabel: nil)

    public var accessibilityDescription: String {
        guard let percentRemaining else {
            guard let name = providerLabel ?? provider else { return "QuotaBar" }
            let extra = extraUsageSpent.map { ", \($0) extra usage spent" } ?? ""
            return "QuotaBar, \(name) usage unknown\(extra)"
        }
        let percent = QuotaFormatting.percent(percentRemaining)
        let name = providerLabel ?? provider ?? "quota"
        let window = windowLabel.map { " \($0)" } ?? ""
        let stale = usageState == .stale ? ", stale" : ""
        let extra = extraUsageSpent.map { ", \($0) extra usage spent" } ?? ""
        return "QuotaBar, \(name)\(window) \(percent) remaining\(extra)\(stale)"
    }
}

public enum MenuBarReadoutResolver {
    /// Providers the captain is most likely to be working in, tried in order when
    /// seeding the focus for the first time.
    public static let preferredFocusOrder = ["claude", "codex"]

    public static func resolve(
        snapshot: QuotaSnapshot?,
        mode: MenuBarFocusMode,
        focusedProvider: String,
        isVisible: (String) -> Bool) -> MenuBarReadout
    {
        guard mode != .iconOnly else { return .empty }
        let providers = snapshot?.providers ?? []

        let chosen: QuotaProvider?
        switch mode {
        case .iconOnly:
            chosen = nil
        case .focusedProvider:
            chosen = providers.first { $0.provider == focusedProvider }
        case .lowestOfShown:
            chosen = providers
                .filter { $0.isFresh && isVisible($0.provider) && $0.headline != nil }
                .min { ($0.headline?.percentRemaining ?? 101) < ($1.headline?.percentRemaining ?? 101) }
        }

        guard let chosen else { return .empty }
        guard let headline = chosen.headline else {
            // Keep the mark so the captain still sees which provider is focused,
            // and show no number rather than a fake zero.
            return MenuBarReadout(
                provider: chosen.provider,
                providerLabel: chosen.displayName,
                percentRemaining: nil,
                windowLabel: nil,
                extraUsageSpent: QuotaFormatting.extraUsageSpent(chosen.extraUsageWindow?.spentUsd),
                usageState: .unknown)
        }
        return MenuBarReadout(
            provider: chosen.provider,
            providerLabel: chosen.displayName,
            percentRemaining: headline.percentRemaining,
            windowLabel: headline.windowLabel,
            extraUsageSpent: QuotaFormatting.extraUsageSpent(chosen.extraUsageWindow?.spentUsd),
            usageState: chosen.usageState)
    }

    /// The provider to focus when the captain has not picked one yet: a signed-in
    /// provider he actually uses, never whichever number happens to be lowest.
    public static func defaultFocus(in snapshot: QuotaSnapshot?) -> String? {
        let providers = snapshot?.providers ?? []
        for candidate in preferredFocusOrder {
            if let match = providers.first(where: { $0.provider == candidate && $0.isFresh }) {
                return match.provider
            }
        }
        return providers.first(where: { $0.isFresh && $0.headline != nil })?.provider
    }
}
