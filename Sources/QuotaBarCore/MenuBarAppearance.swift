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

/// What colour the provider mark is drawn in. Three plain choices: the brand
/// colour, or a solid fill in one ink.
///
/// Black and white mean exactly that. An earlier version offered "greyscale",
/// which drained the hue out of the brand colour and then lifted the result
/// back to a readable contrast - so a Claude mark came out one grey and a Codex
/// mark another, and neither was black or white. A flat ink is what was asked
/// for and it is also the only version of this that is predictable.
public enum MenuBarMarkStyle: String, CaseIterable, Identifiable, Sendable {
    case color
    case black
    case white

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .color: "Brand colour"
        case .black: "Black"
        case .white: "White"
        }
    }

    /// The raw value the retired greyscale choice was stored under.
    public static let retiredGreyscaleRawValue = "greyscale"

    /// Reads a stored choice, carrying the retired greyscale setting over to
    /// whichever flat ink is closest to what it was actually drawing.
    ///
    /// Greyscale resolved to a light grey on a dark menu bar and a dark grey on
    /// a light one, because it was pushed back to a readable contrast against
    /// the bar it sat on. So the honest migration is the appearance at the time
    /// of the read: white on dark, black on light. Resetting to the brand
    /// colour would instead undo a choice the captain made on purpose.
    public static func stored(_ rawValue: String?, dark: Bool) -> MenuBarMarkStyle {
        guard let rawValue else { return .color }
        if rawValue == retiredGreyscaleRawValue { return dark ? .white : .black }
        return MenuBarMarkStyle(rawValue: rawValue) ?? .color
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
    public var markSize: Double
    public var markGap: Double

    public init(
        backingScope: MenuBarBackingScope = .mark,
        markStyle: MenuBarMarkStyle = .color,
        backingColorStyle: MenuBarBackingColorStyle = .automatic,
        backingColorHex: String = MenuBarAppearance.defaultCustomBackingHex,
        backingOpacity: Double = MenuBarAppearance.defaultCustomBackingOpacity,
        textColorStyle: MenuBarTextColorStyle = .automatic,
        textColorHex: String = MenuBarAppearance.defaultCustomTextHex,
        font: MenuBarFontChoice = .system,
        markSize: Double = MenuBarAppearance.defaultMarkSize,
        markGap: Double = MenuBarAppearance.defaultMarkGap)
    {
        self.backingScope = backingScope
        self.markStyle = markStyle
        self.backingColorStyle = backingColorStyle
        self.backingColorHex = backingColorHex
        self.backingOpacity = backingOpacity
        self.textColorStyle = textColorStyle
        self.textColorHex = textColorHex
        self.font = font
        self.markSize = markSize
        self.markGap = markGap
    }

    /// The presentation QuotaBar shipped before any of this was configurable.
    public static let `default` = MenuBarAppearance()

    /// Only used once the captain switches the backing to a custom colour, so
    /// the first custom state is a visible version of the automatic one rather
    /// than an invisible nothing.
    public static let defaultCustomBackingHex = "#808080"
    public static let defaultCustomBackingOpacity = 0.12
    public static let defaultCustomTextHex = "#FFFFFF"

    /// The current 85% menu-bar scale resolves the original 20pt mark to 17pt.
    /// The gap is deliberately tighter than the former 1.5pt shipped spacing.
    public static let defaultMarkSize = 17.0
    public static let defaultMarkGap = 1.0

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

    /// What the item wears while the panel is open.
    ///
    /// Deliberately QuotaBar's own, and deliberately in the same shape and ink
    /// family as the backing plate, so the open item reads as the same object
    /// with the lights on. macOS draws its own momentary highlight while the
    /// mouse is down - a near-full-width pill, in a colour and a shape that no
    /// API exposes - and that one is not ours to restyle; what is ours is the
    /// state that lasts, which is the panel being open.
    ///
    /// Stronger than the backing on purpose. The backing has to disappear into
    /// the menu bar; this one has to be noticed, because it is the only thing
    /// saying the panel belongs to this item.
    public static let openOpacityOnDark = 0.20
    public static let openOpacityOnLight = 0.13

    /// The open indication on its own, before the backing is taken into account.
    public static func openIndication(dark: Bool) -> (color: BrandRGB, opacity: Double) {
        (
            dark ? BrandRGB(red: 1, green: 1, blue: 1) : BrandRGB(red: 0, green: 0, blue: 0),
            dark ? openOpacityOnDark : openOpacityOnLight)
    }

    /// The one plate `StatusItemController` draws under the whole item: the
    /// backing when the panel is shut, and the backing with the open indication
    /// over it when it is open. `nil` means draw nothing at all.
    ///
    /// The two are composited here rather than stacked as two layers so the
    /// status item has exactly one plate to place, whatever state it is in -
    /// one rectangle, one radius, one colour - and so the result is a value
    /// this module can test.
    public func itemPlate(dark: Bool, open: Bool) -> (color: BrandRGB, opacity: Double)? {
        let backing = wholeItemBacking(dark: dark)
        guard open else { return backing }
        let indication = Self.openIndication(dark: dark)
        guard let backing else { return indication }
        return Self.compositing(indication, over: backing)
    }

    /// Straight source-over of two translucent fills of the same rectangle.
    static func compositing(
        _ top: (color: BrandRGB, opacity: Double),
        over bottom: (color: BrandRGB, opacity: Double)) -> (color: BrandRGB, opacity: Double)
    {
        let alpha = top.opacity + bottom.opacity * (1 - top.opacity)
        guard alpha > 0 else { return (top.color, 0) }
        func channel(_ t: Double, _ b: Double) -> Double {
            (t * top.opacity + b * bottom.opacity * (1 - top.opacity)) / alpha
        }
        return (
            BrandRGB(
                red: channel(top.color.red, bottom.color.red),
                green: channel(top.color.green, bottom.color.green),
                blue: channel(top.color.blue, bottom.color.blue)),
            alpha)
    }

    /// The colour the provider's mark is painted in: its readable brand colour,
    /// or a solid black or white.
    ///
    /// Black and white are returned untouched, with no contrast adjustment.
    /// That is the point of them - a black asked for on a dark menu bar is the
    /// black that was asked for, not a grey the app decided was more readable.
    /// Only the brand colour is nudged, and only as far as it has to be.
    public func markColor(for provider: String, dark: Bool) -> BrandRGB {
        switch markStyle {
        case .color: BrandColors.readableColor(for: provider, darkAppearance: dark)
        case .black: BrandRGB(red: 0, green: 0, blue: 0)
        case .white: BrandRGB(red: 1, green: 1, blue: 1)
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
