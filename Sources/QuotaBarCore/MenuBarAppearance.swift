import Foundation

/// How the menu bar item is drawn. Every value here is the captain's to set, and
/// every default is exactly what QuotaBar drew before these settings existed, so
/// an untouched install looks unchanged.
///
/// The decisions live in this module, away from AppKit, because they are the
/// part worth testing: what the backing covers, what colour the mark and the
/// number come out in, and which font the readout is set in. `ProviderMarkImage`
/// and `StatusItemController` only carry these answers to the drawing calls.

/// What the faint backing plate sits behind.
public enum MenuBarBackingScope: String, CaseIterable, Identifiable, Sendable {
    /// No plate at all.
    case none
    /// Behind the mark only - the original presentation.
    case mark
    /// One plate behind the mark and the number together.
    case markAndNumber

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .none: "None"
        case .mark: "Behind the icon"
        case .markAndNumber: "Behind the icon and number"
        }
    }

    /// Drawn into the mark image itself, because the mark is an image.
    public var platesTheMark: Bool { self == .mark }

    /// Drawn as a layer under the whole status item, because the number is text
    /// AppKit lays out and no image can reach behind it.
    public var platesTheWholeItem: Bool { self == .markAndNumber }
}

/// Whether the provider mark keeps its brand colour.
public enum MenuBarMarkStyle: String, CaseIterable, Identifiable, Sendable {
    case color
    case greyscale

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .color: "Brand colour"
        case .greyscale: "Greyscale"
        }
    }
}

/// Where the backing plate's colour comes from.
public enum MenuBarBackingColorStyle: String, CaseIterable, Identifiable, Sendable {
    /// A touch of the menu bar's own contrast direction: white on a dark menu
    /// bar, black on a light one, at the original barely-there strength.
    case automatic
    /// A colour and a strength the captain picked.
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .automatic: "Match the menu bar"
        case .custom: "Custom"
        }
    }
}

/// What colour the percentage is set in.
public enum MenuBarTextColorStyle: String, CaseIterable, Identifiable, Sendable {
    /// The system label colour, which follows the menu bar's appearance.
    case automatic
    case white
    case black
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .automatic: "Match the menu bar"
        case .white: "White"
        case .black: "Black"
        case .custom: "Custom"
        }
    }
}

/// The face the percentage is set in. Every one of these is a system font
/// design, so the readout keeps tabular figures - a readout that changes width
/// as the number changes is the bug the reserved column exists to prevent.
public enum MenuBarFontChoice: String, CaseIterable, Identifiable, Sendable {
    case system
    case rounded
    case monospaced
    case serif

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: "System"
        case .rounded: "Rounded"
        case .monospaced: "Monospaced"
        case .serif: "Serif"
        }
    }
}

public struct MenuBarAppearance: Equatable, Sendable {
    public var backingScope: MenuBarBackingScope
    public var markStyle: MenuBarMarkStyle
    public var backingColorStyle: MenuBarBackingColorStyle
    public var backingColorHex: String
    public var backingOpacity: Double
    public var textColorStyle: MenuBarTextColorStyle
    public var textColorHex: String
    public var font: MenuBarFontChoice

    public init(
        backingScope: MenuBarBackingScope = .mark,
        markStyle: MenuBarMarkStyle = .color,
        backingColorStyle: MenuBarBackingColorStyle = .automatic,
        backingColorHex: String = MenuBarAppearance.defaultCustomBackingHex,
        backingOpacity: Double = MenuBarAppearance.defaultCustomBackingOpacity,
        textColorStyle: MenuBarTextColorStyle = .automatic,
        textColorHex: String = MenuBarAppearance.defaultCustomTextHex,
        font: MenuBarFontChoice = .system)
    {
        self.backingScope = backingScope
        self.markStyle = markStyle
        self.backingColorStyle = backingColorStyle
        self.backingColorHex = backingColorHex
        self.backingOpacity = backingOpacity
        self.textColorStyle = textColorStyle
        self.textColorHex = textColorHex
        self.font = font
    }

    /// The presentation QuotaBar shipped before any of this was configurable.
    public static let `default` = MenuBarAppearance()

    /// Only used once the captain switches the backing to a custom colour, so
    /// the first custom state is a visible version of the automatic one rather
    /// than an invisible nothing.
    public static let defaultCustomBackingHex = "#808080"
    public static let defaultCustomBackingOpacity = 0.12
    public static let defaultCustomTextHex = "#FFFFFF"

    /// Deliberately faint. The backing keeps a coloured mark legible when a
    /// bright or busy wallpaper shows through a translucent menu bar; anything
    /// stronger reads as a badge in the menu bar.
    public static let automaticOpacityOnDark = 0.11
    public static let automaticOpacityOnLight = 0.07

    public static let opacityRange: ClosedRange<Double> = 0...0.6

    /// The plate's ink, or `nil` when this scope draws no plate at all. The
    /// caller decides where it goes; this decides whether and in what.
    public func backing(dark: Bool) -> (color: BrandRGB, opacity: Double)? {
        guard backingScope != .none else { return nil }
        switch backingColorStyle {
        case .automatic:
            return (
                dark ? BrandRGB(red: 1, green: 1, blue: 1) : BrandRGB(red: 0, green: 0, blue: 0),
                dark ? Self.automaticOpacityOnDark : Self.automaticOpacityOnLight)
        case .custom:
            return (
                BrandColors.rgb(fromHex: backingColorHex),
                min(max(backingOpacity, Self.opacityRange.lowerBound), Self.opacityRange.upperBound))
        }
    }

    /// The plate drawn into the mark image, which is the only plate an image can
    /// carry. `nil` for every other scope, including the one that plates the
    /// whole item.
    public func markBacking(dark: Bool) -> (color: BrandRGB, opacity: Double)? {
        backingScope.platesTheMark ? backing(dark: dark) : nil
    }

    /// The plate drawn under the whole status item.
    public func wholeItemBacking(dark: Bool) -> (color: BrandRGB, opacity: Double)? {
        backingScope.platesTheWholeItem ? backing(dark: dark) : nil
    }

    /// The colour the provider's mark is painted in: its readable brand colour,
    /// or the same colour drained of hue and brought back up to a readable
    /// contrast against the menu bar it sits on.
    public func markColor(for provider: String, dark: Bool) -> BrandRGB {
        let brand = BrandColors.readableColor(for: provider, darkAppearance: dark)
        switch markStyle {
        case .color: return brand
        case .greyscale:
            return BrandColors.readable(
                BrandColors.greyscale(brand),
                on: dark ? BrandColors.darkBackground : BrandColors.lightBackground)
        }
    }

    /// The percentage's colour, or `nil` for the system label colour - which is
    /// not a fixed value, because it follows the menu bar's own appearance.
    public func textColor() -> BrandRGB? {
        switch textColorStyle {
        case .automatic: nil
        case .white: BrandRGB(red: 1, green: 1, blue: 1)
        case .black: BrandRGB(red: 0, green: 0, blue: 0)
        case .custom: BrandColors.rgb(fromHex: textColorHex)
        }
    }
}
