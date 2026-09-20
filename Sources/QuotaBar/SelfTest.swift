import AppKit
import QuotaBarCore
import SwiftUI

/// Evidence hook for the built app: proves the overview renders real quota-axi
/// output, that every provider's mark actually draws in its brand color, and that
/// the schedule keeps firing. Launch the bundle with `QUOTABAR_SELFTEST=1`.
/// It never touches the menu bar UI, shows no window and asks for no permission.
@MainActor
enum SelfTest {
    static func run(model: AppModel) async {
        print("SELFTEST begin activationPolicy=\(NSApp.activationPolicy().rawValue)")

        await waitForFirstSnapshot(model: model)
        dumpOverview(model: model)
        dumpMenuBarReadout(model: model)
        dumpMarkRendering()
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
            + "active=\(model.activeProviders.count) inactive=\(model.inactiveProviders.count)")

        for provider in model.activeProviders {
            let headline = provider.headline
            print("SELFTEST row provider=\(provider.provider) label=\"\(provider.displayName)\" "
                + "plan=\(provider.plan ?? "-") "
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

        for provider in model.inactiveProviders {
            print("SELFTEST dimmed provider=\(provider.provider) "
                + "label=\"\(provider.displayName)\" state=\(provider.unavailableDescription)")
        }
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

    /// Renders each mark offscreen and reports its coverage and average color, so
    /// the glyphs are proven to draw - and to draw in brand color - without a
    /// screenshot of the screen.
    private static func dumpMarkRendering() {
        for provider in BrandColors.brands.keys.sorted() {
            for dark in [false, true] {
                let renderer = ImageRenderer(
                    content: ProviderMark(provider: provider, size: 16)
                        .environment(\.colorScheme, dark ? .dark : .light))
                renderer.scale = 2

                guard let image = renderer.nsImage,
                      let data = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: data)
                else {
                    print("SELFTEST mark provider=\(provider) dark=\(dark) RENDER-FAILED")
                    continue
                }

                var covered = 0
                var total = 0
                var sum = (red: 0.0, green: 0.0, blue: 0.0)
                for x in 0..<bitmap.pixelsWide {
                    for y in 0..<bitmap.pixelsHigh {
                        total += 1
                        guard let color = bitmap.colorAt(x: x, y: y), color.alphaComponent > 0.5
                        else { continue }
                        covered += 1
                        sum.red += Double(color.redComponent)
                        sum.green += Double(color.greenComponent)
                        sum.blue += Double(color.blueComponent)
                    }
                }

                let expected = BrandColors.readableColor(for: provider, darkAppearance: dark)
                let average = covered == 0
                    ? BrandRGB(red: 0, green: 0, blue: 0)
                    : BrandRGB(
                        red: sum.red / Double(covered),
                        green: sum.green / Double(covered),
                        blue: sum.blue / Double(covered))
                let coverage = total == 0 ? 0 : Double(covered) / Double(total) * 100

                print(String(
                    format: "SELFTEST mark provider=%@ dark=%@ coverage=%.1f%% "
                        + "avg=(%.2f,%.2f,%.2f) expected=(%.2f,%.2f,%.2f) mark=%@",
                    provider, dark ? "yes" : "no", coverage,
                    average.red, average.green, average.blue,
                    expected.red, expected.green, expected.blue,
                    BrandColors.brand(for: provider).mark.rawValue))
            }
        }
    }

    /// Drops the interval to 30s and watches the clock, so the captain's main
    /// complaint - refreshes that silently stop - is checked in the real app.
    private static func observeSchedule(model: AppModel) async {
        model.preferences.refreshInterval = 30
        print("SELFTEST schedule interval=30s watching for ticks")

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
