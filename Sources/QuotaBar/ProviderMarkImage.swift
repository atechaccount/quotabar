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
    }

    private static var cache: [CacheKey: NSImage] = [:]

    /// Marks are square. The menu bar image is larger than the mark itself
    /// because it carries a backing plate behind it; the mark inside stays the
    /// size it has always been, because shrinking it would undo the legibility
    /// the plate is there to buy.
    static let menuBarSide: CGFloat = 20

    /// How far the mark is inset inside its backing plate.
    static let backingInset: CGFloat = 2

    /// Deliberately faint. The backing exists to keep a colored mark legible
    /// when a bright or busy wallpaper shows through a translucent menu bar,
    /// not to draw a button in the menu bar. Anything stronger than this reads
    /// as a badge.
    static let backingOpacityOnDark: Double = 0.11
    static let backingOpacityOnLight: Double = 0.07

    /// The provider's mark in its readable brand color, or QuotaBar's own glyph
    /// when there is no provider or no mark for it. Never returns another
    /// provider's artwork as a stand-in.
    /// `backingOpacity: 0` means no plate at all, which is what everything
    /// inside the dropdown uses.
    static func image(
        provider: String?,
        dark: Bool,
        side: CGFloat,
        backingOpacity: Double = 0) -> NSImage
    {
        let key = CacheKey(
            provider: provider ?? "", dark: dark, side: side, backingOpacity: backingOpacity)
        if let cached = cache[key] { return cached }

        let made = render(
            provider: provider, dark: dark, side: side, backingOpacity: backingOpacity)
        cache[key] = made
        return made
    }

    static func defaultBackingOpacity(dark: Bool) -> Double {
        dark ? backingOpacityOnDark : backingOpacityOnLight
    }

    /// The menu bar image: the mark on its faint backing plate, ready for
    /// `NSStatusItem.button.image`.
    static func menuBarImage(provider: String?, dark: Bool) -> NSImage {
        image(
            provider: provider,
            dark: dark,
            side: menuBarSide,
            backingOpacity: defaultBackingOpacity(dark: dark))
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
        backingOpacity: Double) -> NSImage
    {
        let size = NSSize(width: side, height: side)
        let backing = backingOpacity > 0
        let markSide = backing ? side - backingInset * 2 : side

        guard let provider,
              let url = markURL(for: provider),
              let base = NSImage(contentsOf: url)
        else {
            return appGlyph(side: side, dark: dark, backingOpacity: backingOpacity)
        }

        base.size = NSSize(width: markSide, height: markSide)
        let tint = NSColor(BrandColors.readableColor(for: provider, darkAppearance: dark))

        let composed = NSImage(size: size, flipped: false) { rect in
            drawBacking(in: rect, dark: dark, opacity: backingOpacity)

            let markRect = backing ? rect.insetBy(dx: backingInset, dy: backingInset) : rect
            // The mark is drawn into its own layer so the `.sourceAtop` recolor
            // cannot bleed onto the backing plate underneath it.
            NSGraphicsContext.current?.cgContext.beginTransparencyLayer(auxiliaryInfo: nil)
            base.draw(in: markRect, from: .zero, operation: .sourceOver, fraction: 1)
            tint.setFill()
            // `.sourceAtop` keeps the mark's own alpha - including its cut-outs -
            // and replaces only the color inside it.
            markRect.fill(using: .sourceAtop)
            NSGraphicsContext.current?.cgContext.endTransparencyLayer()
            return true
        }
        composed.isTemplate = false
        composed.accessibilityDescription = provider
        return composed
    }

    /// A faint rounded plate in the menu bar's own contrast direction: a touch
    /// of white on a dark menu bar, a touch of black on a light one. It reads as
    /// a slight settling of the background, not as a control.
    private static func drawBacking(in rect: NSRect, dark: Bool, opacity: Double) {
        guard opacity > 0 else { return }
        let ink = dark ? NSColor.white : NSColor.black
        ink.withAlphaComponent(opacity).setFill()
        NSBezierPath(
            roundedRect: rect,
            xRadius: rect.width * 0.28,
            yRadius: rect.height * 0.28).fill()
    }

    /// QuotaBar's own mark: three rising bars. Shown only when no provider is
    /// focused, which is also what the menu bar shows before the first choice.
    static func appGlyph(side: CGFloat, dark: Bool, backingOpacity: Double = 0) -> NSImage {
        let size = NSSize(width: side, height: side)
        let backing = backingOpacity > 0
        let ink = dark
            ? NSColor(srgbRed: 0.95, green: 0.95, blue: 0.96, alpha: 1)
            : NSColor(srgbRed: 0.12, green: 0.12, blue: 0.13, alpha: 1)

        let image = NSImage(size: size, flipped: false) { rect in
            drawBacking(in: rect, dark: dark, opacity: backingOpacity)

            let box = backing ? rect.insetBy(dx: backingInset, dy: backingInset) : rect
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
