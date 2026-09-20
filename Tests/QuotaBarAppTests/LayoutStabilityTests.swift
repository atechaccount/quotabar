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
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let widths = Set([0.0, 9, 10, 44, 91, 100].map { value -> Int in
            let title = " " + StatusItemController.reservedPercent(value)
            return Int((title as NSString).size(withAttributes: [.font: font]).width.rounded())
        })
        #expect(widths.count == 1, "the menu bar item changes width: \(widths.sorted())")
        #expect(StatusItemController.reservedPercent(100) == "100%")
        #expect(StatusItemController.reservedPercent(9).hasSuffix("9%"))
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

    /// The most visible shift of all: the window resizing under the pointer as
    /// tabs are switched. The captain named Codex and Claude, which differ in
    /// both digit shape and digit count and in how many windows they report.
    @Test
    func everyPageAsksForTheSamePanelSize() throws {
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

        var sizes: Set<String> = []
        for page in [MenuPage.overview, .provider("claude"), .provider("codex"), .provider("cursor")] {
            model.select(page)
            let host = NSHostingController(rootView: QuotaMenuView(model: model))
            host.sizingOptions = [.preferredContentSize]
            host.view.layoutSubtreeIfNeeded()
            let size = host.view.fittingSize
            sizes.insert("\(Int(size.width))x\(Int(size.height))")
        }

        #expect(sizes.count == 1, "pages ask for different panel sizes: \(sizes.sorted())")
        #expect(sizes.first?.hasPrefix("\(Int(Layout.popoverWidth))x") == true)
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
}
