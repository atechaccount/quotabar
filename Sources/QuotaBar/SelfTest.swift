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

        print("SELFTEST resize \(await statusItem.resizeAnimationReport())")

        // The panel now sizes to its page on purpose, so differing heights here
        // are correct. What must not vary is the same page measured twice, and
        // the width, which is fixed for every page.
        let sizes = await statusItem.pageSizeReport()
        var byPage: [String: Set<String>] = [:]
        for entry in sizes {
            let parts = entry.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            byPage[parts[0], default: []].insert(parts[1])
        }
        let unstable = byPage.filter { $0.value.count > 1 }.keys.sorted()
        let widths = Set(sizes.compactMap { $0.split(separator: "=").last?.split(separator: "x").first })
        print("SELFTEST panelsize \(sizes.joined(separator: " ")) "
            + "oneWidth=\(widths.count == 1) "
            + "pagesThatChangedSize=\(unstable.isEmpty ? "none" : unstable.joined(separator: ","))")
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
            .map { StatusItemController.reservedPercent($0) } ?? ""
        let drawnTitle = button.attributedTitle.string
            .replacingOccurrences(of: "\u{FFFC}", with: "")
        print("SELFTEST statusitem buttonTitle=\"\(drawnTitle)\" "
            + "expected=\"\(expectedTitle)\" "
            + "match=\(drawnTitle == expectedTitle) "
            + "imagePosition=\(button.imagePosition.rawValue) "
            + "appearance=\(StatusItemController.isDark(button.effectiveAppearance) ? "dark" : "light")")

        if let image = StatusItemController.markImage(in: button.attributedTitle) {
            let ink = inkCoverage(of: image)
            print(String(
                format: "SELFTEST statusitem imageInk coverage=%.1f%% avg=(%.2f,%.2f,%.2f) drawn=%@",
                ink.coverage, ink.average.red, ink.average.green, ink.average.blue,
                ink.coverage > 0 ? "yes" : "NO-INK"))
        } else {
            print("SELFTEST statusitem imageInk drawn=NO-IMAGE")
        }

        print("SELFTEST statusitem buttonInk \(buttonInkReport(button))")
        dumpAppearance(model: model, button: button)
        dumpAppearanceSweep(model: model, statusItem: statusItem, button: button)
        dumpMenuBarGapSweep(
            button: button,
            provider: model.menuBarReadout.provider,
            appearance: model.preferences.menuBarAppearance)

    }

    /// Draws the live status button into a bitmap and reports how much ink lands
    /// in the leading square - the region the mark occupies. This is what tells
    /// the difference between "the model wanted a mark" and "the menu bar drew
    /// one", which is precisely what the earlier offscreen check could not.
    private static func buttonInkReport(_ button: NSStatusBarButton) -> String {
        // The gap is only measurable when there is a number to measure against.
        // If the focused provider has none right now, borrow a representative
        // one for the measurement and hand the real title straight back.
        let realTitle = button.attributedTitle
        let simulated = realTitle.string.replacingOccurrences(of: "\u{FFFC}", with: "").isEmpty
        if simulated, let mark = StatusItemController.markImage(in: realTitle) {
            button.attributedTitle = StatusItemController.statusTitle(
                mark: mark, percent: StatusItemController.reservedPercent(42))
            button.layoutSubtreeIfNeeded()
        }
        defer {
            if simulated {
                button.attributedTitle = realTitle
                button.layoutSubtreeIfNeeded()
            }
        }

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

        // The widest run of empty columns between the first and last ink is the
        // gap between the mark and its number, which is the thing that read as
        // too wide. Reported in points so it can be compared against a target.
        var inkColumns: [Bool] = []
        for x in 0..<bitmap.pixelsWide {
            var any = false
            for y in 0..<bitmap.pixelsHigh
            where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1 {
                any = true
                break
            }
            inkColumns.append(any)
        }
        let firstInk = inkColumns.firstIndex(of: true) ?? 0
        let lastInk = inkColumns.lastIndex(of: true) ?? 0
        var widestGap = 0
        var run = 0
        for x in firstInk...max(firstInk, lastInk) {
            run = inkColumns[x] ? 0 : run + 1
            widestGap = max(widestGap, run)
        }
        let scale = bounds.width > 0 ? CGFloat(bitmap.pixelsWide) / bounds.width : 2

        return String(
            format: "frame=%.0fx%.0f px=%dx%d markRegionPx=%d markInk=%d totalInk=%d "
                + "markToNumberGap=%.1fpt title=%@ drawn=%@",
            bounds.width, bounds.height, bitmap.pixelsWide, bitmap.pixelsHigh,
            markWidth, markInk, totalInk,
            CGFloat(widestGap) / scale,
            simulated ? "simulated" : "live",
            markInk > 0 ? "yes" : "NO-MARK-INK")
    }

    /// The gap between the mark and its number, measured at every digit count
    /// and in both appearances. It has to be tiny, and it has to never reach
    /// zero - a zero here means the glyphs have run into each other.
    /// What the appearance settings actually did to the drawn item: which plate
    /// is in play, whether the button's own layer carries the wide one, and what
    /// face and colour the number came out in.
    private static func dumpAppearance(model: AppModel, button: NSStatusBarButton) {
        let appearance = model.preferences.menuBarAppearance
        let dark = StatusItemController.isDark(button.effectiveAppearance)
        let plate = StatusItemController.wholeItemPlate(appearance: appearance, dark: dark)
        let layerAlpha = button.layer?.backgroundColor?.alpha ?? 0
        let font = (button.attributedTitle.length > 0
            ? button.attributedTitle.attribute(
                .font, at: button.attributedTitle.length - 1, effectiveRange: nil) as? NSFont
            : nil) ?? StatusItemController.titleFont

        print(String(
            format: "SELFTEST appearance scope=%@ mark=%@ backing=%@ text=%@ font=%@ "
                + "drawnFont=%@ wholeItemPlate=%@ layerAlpha=%.3f",
            appearance.backingScope.rawValue,
            appearance.markStyle.rawValue,
            appearance.backingColorStyle.rawValue,
            appearance.textColorStyle.rawValue,
            appearance.font.rawValue,
            font.fontName,
            plate == nil ? "none" : "yes",
            layerAlpha))
    }

    /// Each appearance option put through the real status item, because the
    /// plate that covers mark and number together is the button's own layer -
    /// nothing offscreen can prove it landed. The captain's own settings are put
    /// back at the end.
    private static func dumpAppearanceSweep(
        model: AppModel, statusItem: StatusItemController, button: NSStatusBarButton)
    {
        let original = model.preferences.menuBarAppearance
        defer {
            model.preferences.menuBarAppearance = original
            statusItem.refresh()
        }

        var variants: [(String, MenuBarAppearance)] = []
        for scope in MenuBarBackingScope.allCases {
            var appearance = MenuBarAppearance.default
            appearance.backingScope = scope
            variants.append(("scope=\(scope.rawValue)", appearance))
        }
        var greyscale = MenuBarAppearance.default
        greyscale.markStyle = .greyscale
        variants.append(("mark=greyscale", greyscale))

        var custom = MenuBarAppearance.default
        custom.backingScope = .markAndNumber
        custom.backingColorStyle = .custom
        custom.backingColorHex = "#3366FF"
        custom.backingOpacity = 0.3
        custom.textColorStyle = .white
        custom.font = .rounded
        variants.append(("custom", custom))

        for (label, appearance) in variants {
            model.preferences.menuBarAppearance = appearance
            statusItem.refresh()
            button.layoutSubtreeIfNeeded()

            let mark = StatusItemController.markImage(in: button.attributedTitle)
            let markInk = mark.map { inkCoverage(of: $0) }
            let plate = button.layer?.backgroundColor
            print(String(
                format: "SELFTEST appearancesweep %@ mark=%@ markAvg=(%.2f,%.2f,%.2f) "
                    + "layerAlpha=%.3f layerRadius=%.1f width=%.0f",
                label,
                mark == nil ? "MISSING" : "yes",
                markInk?.average.red ?? 0, markInk?.average.green ?? 0,
                markInk?.average.blue ?? 0,
                plate?.alpha ?? 0,
                button.layer?.cornerRadius ?? 0,
                button.bounds.width))
        }
    }

    private static func dumpMenuBarGapSweep(
        button: NSStatusBarButton,
        provider: String?,
        appearance: MenuBarAppearance) {
        let original = button.attributedTitle
        defer {
            button.attributedTitle = original
            button.layoutSubtreeIfNeeded()
        }

        var measurements: [String] = []
        var smallest = CGFloat.greatestFiniteMagnitude
        var smallestAt = "-"
        // Every face, not only the chosen one. The gap is small by design and
        // the item is small, so a face that sets its digits tighter is exactly
        // where the mark and the number would first run into each other.
        for face in MenuBarFontChoice.allCases {
            var variant = appearance
            variant.font = face
            for dark in [false, true] {
                let mark = ProviderMarkImage.menuBarImage(
                    provider: provider, dark: dark, appearance: variant)
                for value in [7.0, 44, 100] {
                    button.attributedTitle = StatusItemController.statusTitle(
                        mark: mark,
                        percent: StatusItemController.reservedPercent(value),
                        appearance: variant)
                    button.layoutSubtreeIfNeeded()
                    let gap = measuredGap(of: button)
                    let label = String(
                        format: "%@/%@/%.0f%%", face.rawValue, dark ? "dark" : "light", value)
                    if let gap, gap < smallest {
                        smallest = gap
                        smallestAt = label
                    }
                    measurements.append(String(
                        format: "%@=%@", label,
                        gap.map { String(format: "%.1f", $0) } ?? "?"))
                }
            }
        }

        print("SELFTEST menubargap \(measurements.joined(separator: " ")) "
            + String(format: "smallest=%.1fpt at=%@ touching=%@",
                     smallest, smallestAt, smallest <= 0 ? "YES" : "no"))
    }

    /// The widest run of empty columns between the first and last ink in the
    /// button - which, with a mark then a number, is the gap between them.
    private static func measuredGap(of button: NSStatusBarButton) -> CGFloat? {
        let bounds = button.bounds
        guard bounds.width > 1,
              let bitmap = button.bitmapImageRepForCachingDisplay(in: bounds)
        else { return nil }
        button.cacheDisplay(in: bounds, to: bitmap)

        var ink: [Bool] = []
        for x in 0..<bitmap.pixelsWide {
            var any = false
            for y in 0..<bitmap.pixelsHigh
            where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1 {
                any = true
                break
            }
            ink.append(any)
        }
        guard let first = ink.firstIndex(of: true), let last = ink.lastIndex(of: true)
        else { return nil }

        var widest = 0
        var run = 0
        for x in first...last {
            run = ink[x] ? 0 : run + 1
            widest = max(widest, run)
        }
        return CGFloat(widest) / (CGFloat(bitmap.pixelsWide) / bounds.width)
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
