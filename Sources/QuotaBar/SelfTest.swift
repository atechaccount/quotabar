import AppKit
import QuotaBarCore
import SwiftUI

/// Evidence hook for the built app. Launch the bundle with `QUOTABAR_SELFTEST=1`.
///
/// The previous version rendered each mark with `ImageRenderer` outside the
/// status-item host and passed while the real menu bar showed nothing. That gap
/// is why a missing mark reached the captain, so the check that matters now is
/// the last one: it reads the pixels of the *actual* `NSStatusBarButton`.
///
/// It shows no window, takes no screenshot and asks for no permission.
@MainActor
enum SelfTest {
    static func run(model: AppModel, statusItem: StatusItemController) async {
        print("SELFTEST begin activationPolicy=\(NSApp.activationPolicy().rawValue)")

        await waitForFirstSnapshot(model: model)
        dumpOverview(model: model)
        dumpVisibilitySeed(model: model)
        dumpMenuBarReadout(model: model)
        dumpMarkResources()
        dumpStatusItem(model: model, statusItem: statusItem)
        print("SELFTEST popover \(await statusItem.popoverReport())")
        await dumpStickyFocus(model: model, statusItem: statusItem)
        await observeSchedule(model: model)

        print("SELFTEST end")
    }

    private static func waitForFirstSnapshot(model: AppModel) async {
        for _ in 0..<60 {
            if model.snapshot != nil { return }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        print("SELFTEST no snapshot arrived")
    }

    private static func dumpOverview(model: AppModel) {
        let now = Date()
        let reported = model.snapshot?.providers.count ?? 0
        print("SELFTEST overview providersReported=\(reported) "
            + "shown=\(model.overviewProviders.count) "
            + "tabs=\(model.tabProviders.count) "
            + "notShown=\(model.providersNotShown.count)")

        for provider in model.overviewProviders {
            let headline = provider.headline
            print("SELFTEST row provider=\(provider.provider) label=\"\(provider.displayName)\" "
                + "context=\"\(provider.overviewContext)\" "
                + "headline=\(headline.map { QuotaFormatting.percent($0.percentRemaining) } ?? "-") "
                + "headlineWindow=\"\(headline?.windowLabel ?? "-")\" "
                + "isSession=\(headline?.isSession ?? false) windows=\(provider.allWindows.count)")

            for window in provider.allWindows {
                let reset = QuotaFormatting.date(from: window.resetsAt)
                    .map { QuotaFormatting.resetDescription($0, now: now) } ?? "no reset"
                print("SELFTEST   window label=\"\(window.displayLabel)\" "
                    + "remaining=\(window.percentRemaining.map { QuotaFormatting.percent($0) } ?? "-") "
                    + "cadence=\(QuotaFormatting.cadence(windowSeconds: window.windowSeconds) ?? "-") "
                    + "\(reset)")
            }
        }

        for provider in model.providersNotShown {
            print("SELFTEST notShown provider=\(provider.provider) "
                + "label=\"\(provider.displayName)\" state=\"\(provider.availability.label)\" "
                + "sources=\(provider.sourceDiagnostics.map(\.sourceID))")
        }
    }

    /// The captain's "why is everything enabled?" - answered with the actual
    /// switch states the first snapshot produced.
    private static func dumpVisibilitySeed(model: AppModel) {
        let hidden = model.preferences.hiddenProviders.sorted()
        let shown = (model.snapshot?.providers ?? [])
            .map(\.provider)
            .filter { model.preferences.isVisible($0) }
            .sorted()
        print("SELFTEST visibility seeded=\(model.preferences.didSeedVisibility) "
            + "on=\(shown) off=\(hidden)")
    }

    private static func dumpMenuBarReadout(model: AppModel) {
        let readout = model.menuBarReadout
        print("SELFTEST menubar mode=\(model.preferences.focusMode.rawValue) "
            + "focus=\(model.preferences.focusedProvider) "
            + "mark=\(readout.provider ?? "<app glyph>") "
            + "percent=\(readout.percentRemaining.map { QuotaFormatting.percent($0) } ?? "-") "
            + "window=\"\(readout.windowLabel ?? "-")\" "
            + "accessibility=\"\(readout.accessibilityDescription)\"")
    }

    /// Proves every provider's real mark resource is present and rasterizes to
    /// something, in both appearances, in the shipped bundle.
    private static func dumpMarkResources() {
        for provider in BrandColors.brands.keys.sorted() {
            let hasResource = ProviderMarkImage.hasVendorMark(for: provider)
            for dark in [false, true] {
                let image = ProviderMarkImage.image(
                    provider: provider, dark: dark, side: 32)
                let ink = inkCoverage(of: image)
                let expected = BrandColors.readableColor(for: provider, darkAppearance: dark)
                print(String(
                    format: "SELFTEST mark provider=%@ dark=%@ resource=%@ coverage=%.1f%% "
                        + "avg=(%.2f,%.2f,%.2f) expected=(%.2f,%.2f,%.2f) template=%@",
                    provider, dark ? "yes" : "no", hasResource ? "yes" : "MISSING",
                    ink.coverage, ink.average.red, ink.average.green, ink.average.blue,
                    expected.red, expected.green, expected.blue,
                    image.isTemplate ? "yes" : "no"))
            }
        }
    }

    /// The check the old self-test was missing: read the real status item.
    ///
    /// It asserts what the button was handed, then rasterizes the button's own
    /// view and measures the ink in the image half. An empty image region is
    /// exactly the failure the captain saw, and it now fails here first.
    private static func dumpStatusItem(model: AppModel, statusItem: StatusItemController) {
        statusItem.refresh()
        let rendered = statusItem.rendered
        print("SELFTEST statusitem provider=\(rendered.provider ?? "<app glyph>") "
            + "title=\"\(rendered.title)\" hasImage=\(rendered.hasImage) "
            + "isTemplate=\(rendered.imageIsTemplate) "
            + String(format: "imageSize=%.0fx%.0f ", rendered.imageSize.width, rendered.imageSize.height)
            + "vendorMark=\(rendered.usedVendorMark)")

        guard let button = statusItem.button else {
            print("SELFTEST statusitem button=MISSING")
            return
        }

        let expectedTitle = model.menuBarReadout.percentRemaining
            .map { " " + QuotaFormatting.percent($0) } ?? ""
        print("SELFTEST statusitem buttonTitle=\"\(button.title)\" "
            + "expected=\"\(expectedTitle)\" "
            + "match=\(button.title == expectedTitle) "
            + "imagePosition=\(button.imagePosition.rawValue) "
            + "appearance=\(StatusItemController.isDark(button.effectiveAppearance) ? "dark" : "light")")

        if let image = button.image {
            let ink = inkCoverage(of: image)
            print(String(
                format: "SELFTEST statusitem imageInk coverage=%.1f%% avg=(%.2f,%.2f,%.2f) drawn=%@",
                ink.coverage, ink.average.red, ink.average.green, ink.average.blue,
                ink.coverage > 0 ? "yes" : "NO-INK"))
        } else {
            print("SELFTEST statusitem imageInk drawn=NO-IMAGE")
        }

        print("SELFTEST statusitem buttonInk \(buttonInkReport(button))")

    }

    /// Draws the live status button into a bitmap and reports how much ink lands
    /// in the leading square - the region the mark occupies. This is what tells
    /// the difference between "the model wanted a mark" and "the menu bar drew
    /// one", which is precisely what the earlier offscreen check could not.
    private static func buttonInkReport(_ button: NSStatusBarButton) -> String {
        let bounds = button.bounds
        guard bounds.width > 1, bounds.height > 1,
              let bitmap = button.bitmapImageRepForCachingDisplay(in: bounds)
        else { return "frame=\(NSStringFromRect(bounds)) UNRENDERABLE" }

        button.cacheDisplay(in: bounds, to: bitmap)

        let markWidth = min(bitmap.pixelsWide, Int((ProviderMarkImage.menuBarSide + 6)
            / max(bounds.width, 1) * CGFloat(bitmap.pixelsWide)))
        var markInk = 0
        var totalInk = 0
        for x in 0..<bitmap.pixelsWide {
            for y in 0..<bitmap.pixelsHigh {
                guard let color = bitmap.colorAt(x: x, y: y), color.alphaComponent > 0.1 else {
                    continue
                }
                totalInk += 1
                if x < markWidth { markInk += 1 }
            }
        }

        return String(
            format: "frame=%.0fx%.0f px=%dx%d markRegionPx=%d markInk=%d totalInk=%d drawn=%@",
            bounds.width, bounds.height, bitmap.pixelsWide, bitmap.pixelsHigh,
            markWidth, markInk, totalInk, markInk > 0 ? "yes" : "NO-MARK-INK")
    }

    /// The sticky selection, exercised the way the captain described it: pick a
    /// provider, go back to Overview, and check the menu bar has not moved.
    private static func dumpStickyFocus(model: AppModel, statusItem: StatusItemController) async {
        guard let target = model.tabProviders.first(where: {
            $0.provider != model.preferences.focusedProvider
        }) else {
            print("SELFTEST sticky skipped=only-one-provider-visible")
            return
        }

        let original = model.preferences.focusedProvider
        let originalPage = model.resolvedPage

        model.select(.provider(target.provider))
        statusItem.refresh()
        let afterSelect = statusItem.rendered.provider

        model.select(.overview)
        statusItem.refresh()
        let afterOverview = statusItem.rendered.provider

        print("SELFTEST sticky selected=\(target.provider) "
            + "menuBarAfterSelect=\(afterSelect ?? "-") "
            + "menuBarAfterOverview=\(afterOverview ?? "-") "
            + "persisted=\(model.preferences.focusedProvider) "
            + "held=\(afterOverview == target.provider && model.preferences.focusedProvider == target.provider)")

        // Hand the captain's own choice back; a self-test must not rewrite it.
        if original.isEmpty {
            model.select(.overview)
        } else {
            model.select(.provider(original))
        }
        model.select(originalPage)
        statusItem.refresh()
        print("SELFTEST sticky restored=\(model.preferences.focusedProvider)")
    }

    private static func inkCoverage(of image: NSImage)
        -> (coverage: Double, average: BrandRGB)
    {
        guard let data = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: data)
        else { return (0, BrandRGB(red: 0, green: 0, blue: 0)) }

        var covered = 0
        var total = 0
        var sum = (red: 0.0, green: 0.0, blue: 0.0)
        for x in 0..<bitmap.pixelsWide {
            for y in 0..<bitmap.pixelsHigh {
                total += 1
                guard let color = bitmap.colorAt(x: x, y: y), color.alphaComponent > 0.5 else {
                    continue
                }
                covered += 1
                sum.red += Double(color.redComponent)
                sum.green += Double(color.greenComponent)
                sum.blue += Double(color.blueComponent)
            }
        }

        let average = covered == 0
            ? BrandRGB(red: 0, green: 0, blue: 0)
            : BrandRGB(
                red: sum.red / Double(covered),
                green: sum.green / Double(covered),
                blue: sum.blue / Double(covered))
        return (total == 0 ? 0 : Double(covered) / Double(total) * 100, average)
    }

    /// Drops the interval to 30s and watches the clock, so the captain's main
    /// complaint - refreshes that silently stop - is checked in the real app.
    private static func observeSchedule(model: AppModel) async {
        // Borrow a short interval, then hand the captain's setting back.
        let original = model.preferences.refreshInterval
        defer { model.preferences.refreshInterval = original }
        model.preferences.refreshInterval = 30
        print("SELFTEST schedule interval=30s (restoring \(Int(original))s afterwards)")

        var seen = 0
        var last = model.lastSuccessAt
        let deadline = Date().addingTimeInterval(80)

        while Date() < deadline, seen < 2 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if let current = model.lastSuccessAt, current != last {
                seen += 1
                let gap = last.map { current.timeIntervalSince($0) } ?? 0
                print(String(format: "SELFTEST tick #%d gapSeconds=%.1f", seen, gap))
                last = current
            }
        }

        print("SELFTEST schedule ticksObserved=\(seen) lastError=\(model.lastError ?? "none")")
    }
}
