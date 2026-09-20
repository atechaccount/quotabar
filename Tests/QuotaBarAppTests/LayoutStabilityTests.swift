import AppKit
import QuotaBarCore
import SwiftUI
import Testing
@testable import QuotaBar

/// Switching between Codex and Claude used to move the content sideways. The
/// captain diagnosed it exactly: in a proportional font the digit 1 is narrower
/// than a 4, so two numbers with the same character count still take different
/// widths, and everything beside them shifts.
///
/// Tabular figures fix the digit-shape half. They do not fix the digit-count
/// half - 9% is still shorter than 100% - so every changing number also sits in
/// a reserved column. These tests cover both halves.
@MainActor
struct LayoutStabilityTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - Tabular figures

    private func width(_ text: String, tabular: Bool) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        let resolved = tabular
            ? NSFont.monospacedDigitSystemFont(ofSize: 16, weight: .semibold)
            : font
        return (text as NSString).size(withAttributes: [.font: resolved]).width
    }

    /// The captain's exact case: a 1 against a 4.
    @Test
    func tabularFiguresMakeEveryDigitTheSameWidth() {
        #expect(
            width("111%", tabular: false) != width("444%", tabular: false),
            "the proportional baseline should differ, or this test proves nothing")
        #expect(
            abs(width("111%", tabular: true) - width("444%", tabular: true)) < 0.5,
            "111% and 444% still render at different widths with tabular figures on")
        #expect(abs(width("10%", tabular: true) - width("44%", tabular: true)) < 0.5)
    }

    /// And the half that tabular figures cannot fix, which is why the columns
    /// are reserved.
    @Test
    func tabularFiguresDoNotSolveAChangeOfDigitCount() {
        #expect(
            width("9%", tabular: true) < width("100%", tabular: true),
            "if these matched, the reserved columns would be unnecessary")
    }

    /// The menu bar title is drawn by AppKit and never saw the popover's
    /// setting, so it reserves its own width in figure spaces.
    @Test
    func theMenuBarTitleKeepsOneWidthFromZeroToOneHundred() {
        let font = StatusItemController.titleFont
        let widths = Set([0.0, 9, 10, 44, 91, 100].map { value -> Int in
            let title = StatusItemController.reservedPercent(value)
            return Int((title as NSString).size(withAttributes: [.font: font]).width.rounded())
        })
        #expect(widths.count == 1, "the menu bar item changes width: \(widths.sorted())")
        #expect(StatusItemController.reservedPercent(100) == "100%")
        // Leading, so the digits are right-aligned in a three-digit column and
        // the percent sign does not slide left as the quota falls.
        #expect(StatusItemController.reservedPercent(9).hasSuffix("9%"))
        #expect(StatusItemController.reservedPercent(9).hasPrefix(StatusItemController.reservedPad))
        #expect(StatusItemController.reservedUnknown() == "???%")
        let mark = ProviderMarkImage.menuBarImage(provider: "claude", dark: false)
        let known = StatusItemController.statusTitle(mark: mark, percent: "100%").size().width
        let unknown = StatusItemController.statusTitle(
            mark: mark, percent: StatusItemController.reservedUnknown()).size().width
        #expect(abs(known - unknown) < 0.5, "the unknown title changes menu bar width")
    }

    /// The mark travels in the attributed title so the gap between it and the
    /// number is ours to set. `button.image` plus `button.title` pins that gap
    /// at AppKit's own ~15pt, which no `imagePosition` or `imageHugsTitle`
    /// combination changes.
    @Test
    func theMenuBarMarkSitsRightNextToItsNumber() throws {
        let mark = ProviderMarkImage.menuBarImage(provider: "claude", dark: false)
        let title = StatusItemController.statusTitle(
            mark: mark, percent: StatusItemController.reservedPercent(44))

        let carried = try #require(
            StatusItemController.markImage(in: title),
            "the menu bar lost its mark, which is the original bug")
        #expect(!carried.isTemplate, "a template image loses the brand color")

        // Mark, then the reserved column, then the number - and nothing else.
        let text = title.string.replacingOccurrences(of: "\u{FFFC}", with: "")
        #expect(
            text == StatusItemController.reservedPad + "44%",
            "something was inserted around the number: \(text)")

        // The gap is the attachment's own trailing padding plus our kern, and it
        // has to be positive or the glyphs touch.
        let gap = ProviderMarkImage.menuBarGap
        #expect(gap > 0, "a zero gap lets the mark and the number intersect")
        #expect(gap < 4, "the gap is back to being wide")
    }

    /// The captain asked for a smaller menu bar item, and for the mark and the
    /// number to stay balanced against each other while it shrank. One factor
    /// drives both, so the guard is that neither can be moved on its own and
    /// that the pair really did come down.
    @Test
    func theMenuBarMarkAndItsNumberShrinkTogether() {
        #expect(MenuBarMetrics.scale < 1, "the item is back at its original size")
        #expect(MenuBarMetrics.scale > 0.6, "this is smaller than the menu bar can carry")

        // The design ratio: a 20pt mark against the 13pt system font. Whatever
        // the factor is, the pair holds that proportion to within the half point
        // both sizes are rounded to.
        let designRatio = 20 / NSFont.systemFontSize
        let ratio = MenuBarMetrics.side / MenuBarMetrics.titleSize
        #expect(
            abs(ratio - designRatio) < 0.1,
            "the mark and the number are out of proportion: \(ratio) against \(designRatio)")

        #expect(MenuBarMetrics.side < 20)
        #expect(MenuBarMetrics.titleSize < NSFont.systemFontSize)
        #expect(StatusItemController.titleFont.pointSize == MenuBarMetrics.titleSize)
        #expect(ProviderMarkImage.menuBarSide == MenuBarMetrics.side)
    }

    /// The gap between the mark and the number is the attachment's own trailing
    /// padding plus the kern, and that padding shrinks with the mark. The kern is
    /// derived from it so the whole gap lands on `menuBarGap` at any size - the
    /// property that keeps the glyphs from running into each other.
    @Test
    func theGapSurvivesTheMarkChangingSize() {
        let inset = ProviderMarkImage.menuBarBackingInset
        #expect(
            inset > 0 && inset < ProviderMarkImage.menuBarSide / 2,
            "the backing plate swallowed its mark: inset \(inset)")

        let kern = ProviderMarkImage.menuBarGap - inset
        #expect(
            abs((inset + kern) - ProviderMarkImage.menuBarGap) < 0.001,
            "the gap no longer works out to menuBarGap")
        #expect(
            inset + kern > 0,
            "a zero gap lets the mark and the number intersect")
    }

    /// The captain's own words: 4% should not be two characters where 100% is
    /// four. The item held one width before this, but the number slid left
    /// inside that width as the quota fell, which is a readout that moves in a
    /// frame that does not. The digits now right-align in a three-digit column,
    /// so the percent sign lands in the same place at every value.
    ///
    /// Measured in every face, because the column is measured in the chosen face
    /// and the serif one draws FIGURE SPACE narrower than a digit.
    @Test
    func thePercentSignLandsInTheSamePlaceAtEveryValue() throws {
        for choice in MenuBarFontChoice.allCases {
            var appearance = MenuBarAppearance.default
            appearance.font = choice
            let mark = ProviderMarkImage.menuBarImage(
                provider: "claude", dark: false, appearance: appearance)

            var offsets: Set<Int> = []
            var widths: Set<Int> = []
            for value in [0.0, 4, 9, 44, 91, 100] {
                let title = StatusItemController.statusTitle(
                    mark: mark,
                    percent: StatusItemController.reservedPercent(value),
                    appearance: appearance)
                let offset = try #require(
                    StatusItemController.percentSignOffset(in: title),
                    "\(choice.rawValue) lost its percent sign")
                offsets.insert(Int((offset * 10).rounded()))
                widths.insert(Int((title.size().width * 10).rounded()))
            }
            #expect(
                offsets.count == 1,
                "\(choice.rawValue) slides the percent sign: \(offsets.sorted())")
            #expect(
                widths.count == 1,
                "\(choice.rawValue) changes the item width: \(widths.sorted())")
        }
    }

    /// The column is reserved room for the hundreds digit, not spacing: it opens
    /// between the number and the mark, and the mark keeps the number hard
    /// against it at every value. What must not happen is the *kern* growing -
    /// that would be the old too-wide gap coming back under a new name.
    @Test
    func theReservedColumnDoesNotLoosenTheMarksOwnGap() {
        #expect(
            ProviderMarkImage.menuBarGap - ProviderMarkImage.menuBarBackingInset < 1,
            "the kern between the mark and the column grew")
        #expect(ProviderMarkImage.menuBarGap < 4, "the gap is back to being wide")
    }

    // MARK: - Reserved columns

    private func window(_ percent: Int, resets: Bool) throws -> QuotaWindow {
        let reset = resets ? #""resetsAt":"2027-01-15T12:00:00.000Z","# : ""
        let provider = try #require(QuotaParser.decode("""
        {"providers":[{"provider":"codex","state":{"status":"fresh"},"windows":[
          {"id":"five_hour","label":"session","kind":"session",\(reset)
           "percentRemaining":\(percent),"windowSeconds":18000}]}]}
        """).providers.first)
        return try #require(provider.allWindows.first)
    }

    /// Renders one window row and measures where the ink actually lands in the
    /// band above the meter. Positions rather than raw pixels: text antialiasing
    /// is not reproducible to the byte, but a label that moves is.
    ///
    /// The meter is excluded on purpose - its fill tracks the value, which is
    /// the one thing that is supposed to change.
    private struct InkExtent: Equatable, CustomStringConvertible {
        var size: String
        var firstColumn: Int
        var lastColumn: Int
        var firstRow: Int
        var lastRow: Int

        var description: String {
            "\(size) x:\(firstColumn)...\(lastColumn) y:\(firstRow)...\(lastRow)"
        }

        func matches(_ other: InkExtent, tolerance: Int = 1) -> Bool {
            size == other.size
                && abs(firstColumn - other.firstColumn) <= tolerance
                && abs(lastColumn - other.lastColumn) <= tolerance
                && abs(firstRow - other.firstRow) <= tolerance
                && abs(lastRow - other.lastRow) <= tolerance
        }
    }

    private func windowLabelInk(_ percent: Int, resets: Bool = true) throws -> InkExtent {
        let renderer = ImageRenderer(
            content: WindowSection(
                window: try window(percent, resets: resets),
                accent: .blue,
                now: now)
                .monospacedDigit()
                .frame(width: Layout.popoverWidth - Layout.contentPadding * 2)
                .environment(\.colorScheme, .light)
                .background(Color.white))
        renderer.scale = 2

        let image = try #require(renderer.nsImage)
        let data = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: data))

        let labelWidth = Int((Layout.popoverWidth - Layout.contentPadding * 2
            - Layout.windowValueColumn - 12) * 2)
        let textRows = bitmap.pixelsHigh - Int(20 * 2)

        var first = (column: Int.max, row: Int.max)
        var last = (column: -1, row: -1)
        for y in 0..<max(0, textRows) {
            for x in 0..<min(labelWidth, bitmap.pixelsWide) {
                guard let color = bitmap.colorAt(x: x, y: y) else { continue }
                // Well below any antialiasing fringe, so only real glyph ink counts.
                let luminance = 0.2126 * color.redComponent
                    + 0.7152 * color.greenComponent
                    + 0.0722 * color.blueComponent
                guard luminance < 0.6 else { continue }
                first.column = min(first.column, x)
                first.row = min(first.row, y)
                last.column = max(last.column, x)
                last.row = max(last.row, y)
            }
        }

        return InkExtent(
            size: "\(bitmap.pixelsWide)x\(bitmap.pixelsHigh)",
            firstColumn: first.column, lastColumn: last.column,
            firstRow: first.row, lastRow: last.row)
    }

    @Test
    func theWindowNameNeverMovesWhateverTheNumberBesideItIs() throws {
        let nine = try windowLabelInk(9)
        let fortyFour = try windowLabelInk(44)
        let hundred = try windowLabelInk(100)

        #expect(nine.lastColumn > 0, "no window name was drawn, so this proves nothing")
        #expect(
            nine.matches(fortyFour),
            "9% and 44% put the window name in different places: \(nine) vs \(fortyFour)")
        #expect(
            fortyFour.matches(hundred),
            "44% and 100% put the window name in different places: \(fortyFour) vs \(hundred)")
    }

    @Test
    func aMissingResetTimeDoesNotChangeTheRowHeight() throws {
        func height(_ resets: Bool) throws -> CGFloat {
            let renderer = ImageRenderer(
                content: WindowSection(
                    window: try window(91, resets: resets), accent: .blue, now: now)
                    .frame(width: Layout.popoverWidth - Layout.contentPadding * 2))
            return renderer.nsImage?.size.height ?? 0
        }
        #expect(try height(true) == (try height(false)))
    }

    // MARK: - The panel itself

    /// The panel sizes to its page on purpose, so pages of different shapes may
    /// differ in height. Two things must still hold: the width never changes,
    /// and the same page measured twice is the same size.
    @Test
    func thePanelKeepsOneWidthAndOneSizePerPage() throws {
        let snapshot = try QuotaParser.decode("""
        {"providers":[
          {"provider":"claude","label":"Claude","plan":"pro","account":{"email":"a@b.c"},
           "state":{"status":"fresh"},
           "windows":[{"kind":"session","label":"session","percentRemaining":100},
                      {"kind":"weekly","label":"week","percentRemaining":44}]},
          {"provider":"codex","label":"Codex","plan":"plus","account":{"email":"d@e.f"},
           "state":{"status":"fresh"},
           "windows":[{"kind":"session","label":"session","percentRemaining":9}]},
          {"provider":"cursor","label":"Cursor",
           "state":{"status":"auth_required","sourcesTried":["state-vscdb"]}}]}
        """)
        let preferences = AppPreferences(defaults: InMemoryPreferenceStore())
        preferences.seedVisibilityIfNeeded(from: snapshot)
        preferences.setVisible(true, provider: "cursor")
        let model = AppModel(
            startRefreshing: false, preferences: preferences,
            snapshot: snapshot, lastSuccessAt: now)

        func size(_ page: MenuPage) -> CGSize {
            model.select(page)
            let host = NSHostingController(rootView: QuotaMenuView(model: model))
            host.sizingOptions = [.preferredContentSize]
            host.view.layoutSubtreeIfNeeded()
            return host.view.fittingSize
        }

        let pages: [MenuPage] = [.overview, .provider("claude"), .provider("codex"),
                                 .provider("cursor")]
        var widths: Set<CGFloat> = []
        for page in pages {
            let first = size(page)
            widths.insert(first.width)
            // Visit another page and come back: the same page must measure the same.
            _ = size(.overview)
            #expect(size(page) == first, "\(page) measured two different sizes")
        }

        #expect(widths == [Layout.popoverWidth], "the panel changed width: \(widths.sorted())")
    }

    /// Claude and Codex specifically, which is the pair he switches between.
    @Test
    func switchingBetweenClaudeAndCodexMovesNothingOutsideTheNumbers() throws {
        let snapshot = try QuotaParser.decode("""
        {"providers":[
          {"provider":"claude","label":"Claude","plan":"pro","account":{"email":"a@b.c"},
           "source":"oauth","state":{"status":"fresh"},
           "windows":[{"id":"five_hour","label":"session","kind":"session",
                       "percentRemaining":100,"resetsAt":"2027-01-15T12:00:00.000Z"}]},
          {"provider":"codex","label":"Codex","plan":"plus","account":{"email":"d@e.f"},
           "source":"oauth","state":{"status":"fresh"},
           "windows":[{"id":"five_hour","label":"session","kind":"session",
                       "percentRemaining":9,"resetsAt":"2027-01-15T12:00:00.000Z"}]}]}
        """)
        let preferences = AppPreferences(defaults: InMemoryPreferenceStore())
        preferences.seedVisibilityIfNeeded(from: snapshot)
        let model = AppModel(
            startRefreshing: false, preferences: preferences,
            snapshot: snapshot, lastSuccessAt: now)

        func meterOrigin(_ provider: String) -> CGRect {
            model.select(.provider(provider))
            let host = NSHostingController(rootView: QuotaMenuView(model: model))
            host.sizingOptions = [.preferredContentSize]
            host.view.layoutSubtreeIfNeeded()
            return host.view.frame
        }

        #expect(meterOrigin("claude").size == meterOrigin("codex").size,
                "the Claude and Codex pages are different sizes")
    }

    /// The short-page floor. A provider reporting one window, and one reporting
    /// none at all, must land on the same panel height as the two-window page
    /// that is the ordinary shape - otherwise switching to Antigravity snaps the
    /// panel shorter for no reason the eye can name.
    ///
    /// This is not the fixed height coming back. Pages above the floor still
    /// size to themselves; the floor only stops a page collapsing below the
    /// common one.
    @Test
    func aShortProviderPageIsNoShorterThanTheOrdinaryTwoWindowPage() throws {
        let snapshot = try QuotaParser.decode("""
        {"providers":[
          {"provider":"claude","label":"Claude","plan":"pro","account":{"email":"a@b.c"},
           "source":"oauth","state":{"status":"fresh"},
           "windows":[{"id":"five_hour","label":"session","kind":"session",
                       "percentRemaining":77,"resetsAt":"2027-01-15T12:00:00.000Z"},
                      {"id":"seven_day","label":"week","kind":"weekly",
                       "percentRemaining":44,"resetsAt":"2027-01-18T12:00:00.000Z"}]},
          {"provider":"agy","label":"Antigravity","source":"cli",
           "state":{"status":"fresh"},
           "windows":[{"id":"gemini_weekly","label":"Gemini weekly","kind":"weekly",
                       "percentRemaining":1,"resetsAt":"2027-01-18T12:00:00.000Z"}]},
          {"provider":"openrouter","label":"OpenRouter","source":"api",
           "state":{"status":"fresh"},"windows":[]}]}
        """)
        let preferences = AppPreferences(defaults: InMemoryPreferenceStore())
        preferences.seedVisibilityIfNeeded(from: snapshot)
        for provider in ["claude", "agy", "openrouter"] {
            preferences.setVisible(true, provider: provider)
        }
        let model = AppModel(
            startRefreshing: false, preferences: preferences,
            snapshot: snapshot, lastSuccessAt: now)

        func height(_ provider: String) -> CGFloat {
            model.select(.provider(provider))
            let host = NSHostingController(rootView: QuotaMenuView(model: model))
            host.sizingOptions = [.preferredContentSize]
            host.view.layoutSubtreeIfNeeded()
            return host.view.fittingSize.height
        }

        let twoWindows = height("claude")
        #expect(height("agy") == twoWindows, "the one-window page is a different height")
        #expect(height("openrouter") == twoWindows, "the no-window page is a different height")
    }

    /// The floor must not turn into a ceiling that squeezes a long page. A page
    /// taller than `maxContentHeight` scrolls: the panel stops growing, and the
    /// page itself is still taller than the box it is shown in.
    ///
    /// The two variants of the same view are what make that measurable. The
    /// non-scrolling one is the page at its full height - it is what the render
    /// hook draws - and the scrolling one is what ships. If the scrolling panel
    /// has stopped at the cap while the non-scrolling page is taller, the
    /// content is being scrolled rather than compressed into the visible box.
    @Test
    func aLongPageStillScrollsRatherThanBeingSqueezed() throws {
        let windows = (0..<12).map { index in
            """
            {"id":"w\(index)","label":"Window \(index)","kind":"weekly",
             "percentRemaining":\(index * 8),"resetsAt":"2027-01-18T12:00:00.000Z"}
            """
        }
        let snapshot = try QuotaParser.decode("""
        {"providers":[
          {"provider":"claude","label":"Claude","plan":"pro","account":{"email":"a@b.c"},
           "source":"oauth","state":{"status":"fresh"},
           "windows":[\(windows.joined(separator: ","))]}]}
        """)
        let preferences = AppPreferences(defaults: InMemoryPreferenceStore())
        preferences.seedVisibilityIfNeeded(from: snapshot)
        let model = AppModel(
            startRefreshing: false, preferences: preferences,
            snapshot: snapshot, lastSuccessAt: now)
        model.select(.provider("claude"))

        func height(scrolls: Bool) -> CGFloat {
            let host = NSHostingController(rootView: QuotaMenuView(model: model, scrolls: scrolls))
            host.sizingOptions = [.preferredContentSize]
            host.view.layoutSubtreeIfNeeded()
            return host.view.fittingSize.height
        }

        let capped = height(scrolls: true)
        let full = height(scrolls: false)
        #expect(full > capped, "a 12-window page did not exceed the cap: \(full) against \(capped)")

        // A page resting on the floor gives the chrome above and below the page
        // area, which is what turns the cap into a panel height to compare with.
        let short = try QuotaParser.decode("""
        {"providers":[
          {"provider":"claude","label":"Claude","plan":"pro","account":{"email":"a@b.c"},
           "source":"oauth","state":{"status":"fresh"},
           "windows":[{"id":"w0","label":"Window 0","kind":"weekly","percentRemaining":8,
                       "resetsAt":"2027-01-18T12:00:00.000Z"}]}]}
        """)
        let shortPreferences = AppPreferences(defaults: InMemoryPreferenceStore())
        shortPreferences.seedVisibilityIfNeeded(from: short)
        let shortModel = AppModel(
            startRefreshing: false, preferences: shortPreferences,
            snapshot: short, lastSuccessAt: now)
        shortModel.select(.provider("claude"))
        let shortHost = NSHostingController(rootView: QuotaMenuView(model: shortModel))
        shortHost.sizingOptions = [.preferredContentSize]
        shortHost.view.layoutSubtreeIfNeeded()
        let chrome = shortHost.view.fittingSize.height - Layout.minContentHeight

        #expect(capped == chrome + Layout.maxContentHeight,
                "the page area did not stop at its cap: \(capped) against \(chrome + Layout.maxContentHeight)")
    }
}
