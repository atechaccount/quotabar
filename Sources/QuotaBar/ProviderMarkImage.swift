import AppKit
import QuotaBarCore

/// Loads each provider's real mark from `Resources/ProviderMarks` and returns it
/// as an `NSImage` already painted in the appearance-adjusted brand color.
///
/// Two things here matter for the menu bar. The image is a real `NSImage`, which
/// is what `NSStatusItem.button` consumes - a custom SwiftUI `Shape` is not, and
/// the `MenuBarExtra` label bridge dropped it silently. And `isTemplate` stays
/// `false`, so AppKit keeps the color instead of flattening the mark to the
/// menu bar's own ink.
/// Only here so `Bundle(for:)` can find the binary this code is linked into.
private final class ResourceBundleMarker {}

@MainActor
enum ProviderMarkImage {
    private struct CacheKey: Hashable {
        let provider: String
        let dark: Bool
        let side: CGFloat
        let backingOpacity: Double
        let backingColor: String
        let markStyle: String
        let insetMark: Bool
        let trailingTrim: CGFloat
        let availabilityDot: Bool
    }

    private static var cache: [CacheKey: NSImage] = [:]

    /// Marks are square. The menu bar image is larger than the mark itself
    /// because it carries a backing plate behind it. The size comes from
    /// `MenuBarMetrics`, which scales it in step with the number beside it.
    static let menuBarSide = MenuBarMetrics.side

    /// The clear space the menu bar image keeps after the mark, before the
    /// readout. `MenuBarMetrics.markTrailingMargin` is where it is decided and
    /// why it is that size.
    static let menuBarGap = MenuBarMetrics.markTrailingMargin

    static func menuBarSide(for appearance: MenuBarAppearance) -> CGFloat {
        MenuBarMetrics.markSide(for: appearance)
    }

    /// How far a mark is inset inside its backing plate, for a plate of `side`.
    /// Proportional, so the plate keeps the same visual margin at every size it
    /// is drawn at - the menu bar's and the dropdown's alike.
    static func backingInset(side: CGFloat) -> CGFloat {
        side * MenuBarMetrics.backingInsetFraction
    }

    /// The inset of the menu bar plate specifically: the transparent margin the
    /// mark's own image carries, which `MenuBarMetrics.markTrailingTrim` crops
    /// back on the trailing edge so the readout can sit closer.
    static let menuBarBackingInset = MenuBarMetrics.side * MenuBarMetrics.backingInsetFraction

    static func menuBarBackingInset(for side: CGFloat) -> CGFloat {
        backingInset(side: side)
    }

    /// The corner radius of a plate, as a fraction of its shorter side. Shared
    /// with the plate the status item draws behind mark and number together, so
    /// the two backing scopes are the same shape.
    static let backingCornerFraction: CGFloat = 0.28

    /// The provider's mark in its readable brand color, or QuotaBar's own glyph
    /// when there is no provider or no mark for it. Never returns another
    /// provider's artwork as a stand-in.
    /// `backing: nil` means no plate at all, which is what everything inside the
    /// dropdown uses. `insetMark` keeps the mark at its plated size even when no
    /// plate is drawn, so the menu bar mark does not change size as the backing
    /// scope changes.
    static func image(
        provider: String?,
        dark: Bool,
        side: CGFloat,
        backing: (color: BrandRGB, opacity: Double)? = nil,
        markStyle: MenuBarMarkStyle = .color,
        insetMark: Bool = false,
        trailingTrim: CGFloat = 0,
        availabilityDot: Bool = false) -> NSImage
    {
        let key = CacheKey(
            provider: provider ?? "",
            dark: dark,
            side: side,
            backingOpacity: backing?.opacity ?? 0,
            backingColor: backing.map { BrandColors.hex(from: $0.color) } ?? "",
            markStyle: markStyle.rawValue,
            insetMark: insetMark,
            trailingTrim: trailingTrim,
            availabilityDot: availabilityDot)
        if let cached = cache[key] { return cached }

        let made = render(
            provider: provider,
            dark: dark,
            side: side,
            backing: backing,
            markStyle: markStyle,
            insetMark: insetMark,
            trailingTrim: trailingTrim,
            availabilityDot: availabilityDot)
        cache[key] = made
        return made
    }

    static func defaultBackingOpacity(dark: Bool) -> Double {
        dark ? MenuBarAppearance.automaticOpacityOnDark : MenuBarAppearance.automaticOpacityOnLight
    }

    /// The menu bar image for the captain's chosen appearance: the mark, in its
    /// brand colour or in a flat black or white, on its plate when the backing
    /// sits behind the icon alone. The plate that covers icon and number together is not an image -
    /// `StatusItemController` draws that one under the whole item.
    static func menuBarImage(
        provider: String?,
        dark: Bool,
        appearance: MenuBarAppearance = .default,
        availabilityDot: Bool = false) -> NSImage
    {
        let side = menuBarSide(for: appearance)
        return image(
            provider: provider,
            dark: dark,
            side: side,
            backing: appearance.markBacking(dark: dark),
            markStyle: appearance.markStyle,
            // Always inset: the mark keeps one size whether or not it is plated.
            insetMark: true,
            // The image is the attachment's advance, so the crop is the gap.
            trailingTrim: MenuBarMetrics.markTrailingTrim(for: side),
            availabilityDot: availabilityDot && provider == "claude")
    }

    /// Whether a real vendor mark exists and loaded. The self-test asserts this
    /// for every provider, so a missing or unreadable resource is a failure
    /// rather than a silent fallback to the app glyph.
    static func hasVendorMark(for provider: String) -> Bool {
        markURL(for: provider) != nil
    }

    // MARK: - Resources

    /// SwiftPM puts target resources in `QuotaBar_QuotaBar.bundle`. `build.sh`
    /// copies that bundle into the app, so the signed app, `swift run` and the
    /// test runner all find the same files. `Bundle.module` is deliberately not
    /// used: its generated accessor traps when the bundle is somewhere it did
    /// not expect, and the assembled app is exactly that case.
    private static let bundleName = "QuotaBar_QuotaBar"

    private static let resourceBundle: Bundle? = {
        if let url = Bundle.main.url(forResource: bundleName, withExtension: "bundle"),
           let bundle = Bundle(url: url)
        {
            return bundle
        }

        // Walk out from wherever this code actually sits. Inside the app that is
        // `Contents/MacOS`; under `swift test` the module is linked into an
        // .xctest bundle that a helper binary loads, so `Bundle.main` points at
        // the helper and only `Bundle(for:)` finds the right place.
        let ownBundle = Bundle(for: ResourceBundleMarker.self)
        var searched: [URL] = []
        for start in [
            ownBundle.resourceURL,
            ownBundle.bundleURL,
            Bundle.main.bundleURL,
            Bundle.main.executableURL?.deletingLastPathComponent(),
        ].compactMap({ $0 }) {
            var directory = start
            for _ in 0..<4 {
                searched.append(directory)
                directory = directory.deletingLastPathComponent()
            }
        }
        for directory in searched {
            let candidate = directory.appendingPathComponent("\(bundleName).bundle")
            if let bundle = Bundle(url: candidate) { return bundle }
            let inResources = directory
                .appendingPathComponent("Resources")
                .appendingPathComponent("\(bundleName).bundle")
            if let bundle = Bundle(url: inResources) { return bundle }
        }

        return nil
    }()

    private static func markURL(for provider: String) -> URL? {
        guard let name = BrandColors.brand(for: provider).iconResourceName,
              let bundle = resourceBundle
        else { return nil }
        return bundle.url(forResource: name, withExtension: "svg")
    }

    // MARK: - Rendering

    private static func render(
        provider: String?,
        dark: Bool,
        side: CGFloat,
        backing: (color: BrandRGB, opacity: Double)?,
        markStyle: MenuBarMarkStyle,
        insetMark: Bool,
        trailingTrim: CGFloat,
        availabilityDot: Bool) -> NSImage
    {
        let size = NSSize(width: side - trailingTrim, height: side)
        let inset = insetMark || backing != nil
        let markInset = backingInset(side: side)
        let markSide = inset ? side - markInset * 2 : side

        guard let provider,
              let url = markURL(for: provider),
              let base = NSImage(contentsOf: url)
        else {
            return appGlyph(
                side: side, dark: dark, backing: backing, insetMark: insetMark,
                trailingTrim: trailingTrim)
        }

        base.size = NSSize(width: markSide, height: markSide)
        var appearance = MenuBarAppearance.default
        appearance.markStyle = markStyle
        let tint = NSColor(appearance.markColor(for: provider, dark: dark))

        let composed = NSImage(size: size, flipped: false) { rect in
            drawBacking(in: rect, backing: backing)

            let markRect = inset
                ? NSRect(x: markInset, y: markInset, width: markSide, height: markSide)
                : NSRect(x: 0, y: 0, width: markSide, height: markSide)
            // The mark is drawn into its own layer so the `.sourceAtop` recolor
            // cannot bleed onto the backing plate underneath it.
            NSGraphicsContext.current?.cgContext.beginTransparencyLayer(auxiliaryInfo: nil)
            base.draw(in: markRect, from: .zero, operation: .sourceOver, fraction: 1)
            tint.setFill()
            // `.sourceAtop` keeps the mark's own alpha - including its cut-outs -
            // and replaces only the color inside it.
            markRect.fill(using: .sourceAtop)
            NSGraphicsContext.current?.cgContext.endTransparencyLayer()
            if availabilityDot {
                let diameter = max(4.5, side * 0.27)
                let dot = NSRect(
                    x: markRect.maxX - diameter * 0.58,
                    y: markRect.minY - diameter * 0.14,
                    width: diameter, height: diameter)
                (dark ? NSColor.black : NSColor.white).setFill()
                NSBezierPath(ovalIn: dot.insetBy(dx: -1, dy: -1)).fill()
                NSColor(BrandColors.rgb(fromHex: BrandColors.hex(for: "claude"))).setFill()
                NSBezierPath(ovalIn: dot).fill()
            }
            return true
        }
        composed.isTemplate = false
        composed.accessibilityDescription = provider
        return composed
    }

    /// A faint rounded plate in the menu bar's own contrast direction: a touch
    /// of white on a dark menu bar, a touch of black on a light one. It reads as
    /// a slight settling of the background, not as a control.
    private static func drawBacking(in rect: NSRect, backing: (color: BrandRGB, opacity: Double)?) {
        guard let backing, backing.opacity > 0 else { return }
        NSColor(backing.color).withAlphaComponent(backing.opacity).setFill()
        // One radius from the shorter side, not one per axis. The menu bar
        // plate is no longer square - it is cropped on its trailing edge to
        // bring the readout in - and a radius taken per axis would round its
        // corners into ellipses.
        let radius = min(rect.width, rect.height) * backingCornerFraction
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    }

    /// QuotaBar's own mark: three rising bars. Shown only when no provider is
    /// focused, which is also what the menu bar shows before the first choice.
    static func appGlyph(
        side: CGFloat,
        dark: Bool,
        backing: (color: BrandRGB, opacity: Double)? = nil,
        insetMark: Bool = false,
        trailingTrim: CGFloat = 0) -> NSImage
    {
        let size = NSSize(width: side - trailingTrim, height: side)
        let inset = insetMark || backing != nil
        let markInset = backingInset(side: side)
        let ink = dark
            ? NSColor(srgbRed: 0.95, green: 0.95, blue: 0.96, alpha: 1)
            : NSColor(srgbRed: 0.12, green: 0.12, blue: 0.13, alpha: 1)

        let image = NSImage(size: size, flipped: false) { rect in
            drawBacking(in: rect, backing: backing)

            let box = inset
                ? NSRect(
                    x: markInset, y: markInset,
                    width: side - markInset * 2, height: side - markInset * 2)
                : NSRect(x: 0, y: 0, width: side, height: side)
            let width = max(2, box.width / 5)
            let gap = (box.width - width * 3) / 2
            let heights = [box.height * 0.45, box.height * 0.72, box.height]
            ink.setFill()
            for index in 0..<3 {
                let bar = NSRect(
                    x: box.minX + CGFloat(index) * (width + gap),
                    y: box.minY,
                    width: width,
                    height: heights[index])
                NSBezierPath(roundedRect: bar, xRadius: width / 2, yRadius: width / 2).fill()
            }
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "QuotaBar"
        return image
    }
}

extension NSColor {
    convenience init(_ rgb: BrandRGB) {
        self.init(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
    }
}
