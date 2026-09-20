import AppKit
import QuotaBarCore
import SwiftUI
import Testing
@testable import QuotaBar

/// The overview used to state a percentage and leave the captain to open a
/// provider tab to find out when it came back. The countdown now sits under the
/// headline number, drawn by the same `QuotaFormatting.resetLine` the provider
/// pages use.
///
/// Two things have to hold at once: a provider that reports a reset must show
/// it, and a provider that reports none must look like a row that never had a
/// countdown - no dash, no empty line, and no widening of the panel.
@MainActor
struct OverviewResetTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000) // 2027-01-15T08:00Z

    private func provider(resets: Bool) throws -> QuotaProvider {
        let reset = resets ? #""resetsAt":"2027-01-15T12:00:00.000Z","# : ""
        return try #require(QuotaParser.decode("""
        {"providers":[{"provider":"claude","label":"Claude","plan":"pro",
          "account":{"email":"a@b.c"},"state":{"status":"fresh"},
          "windows":[{"id":"five_hour","label":"session","kind":"session",\(reset)
            "percentRemaining":44,"windowSeconds":18000}]}]}
        """).providers.first)
    }

    private func row(resets: Bool) throws -> some View {
        OverviewProviderRow(provider: try provider(resets: resets), now: now)
            .monospacedDigit()
            .frame(width: Layout.popoverWidth - Layout.contentPadding * 2)
            .environment(\.colorScheme, .light)
            .background(Color.white)
    }

    private func size(resets: Bool) throws -> CGSize {
        try #require(ImageRenderer(content: try row(resets: resets)).nsImage).size
    }

    /// The countdown is really drawn: the row with a reset is exactly one
    /// caption line taller than the row without one.
    @Test
    func aKnownResetAddsTheCountdownLineToTheRow() throws {
        let withReset = try size(resets: true)
        let without = try size(resets: false)

        let line = Typography.size(10)
        let grown = withReset.height - without.height
        #expect(
            grown > 0,
            "the overview row is the same height with and without a reset, so no countdown was drawn")
        #expect(
            grown < line * 2,
            "the countdown added \(grown)pt, which is more than the one caption line it should be")
    }

    /// And the row without one is a clean two-line block, not a placeholder.
    ///
    /// Both rows are drawn into the same tall frame and the headline column is
    /// read for ink. The row with a reset puts glyphs on a third line; the row
    /// without one must leave that band completely empty - no dash, no bracket,
    /// no blank-but-reserved line.
    @Test
    func aProviderWithNoKnownResetDrawsNoPlaceholder() throws {
        let subject = try provider(resets: false)
        #expect(subject.headline?.resetsAt == nil, "the fixture is supposed to have no reset")
        #expect(
            QuotaFormatting.resetLine(from: subject.headline?.resetsAt, now: now) == nil,
            "a provider with no reset time must produce no countdown string at all")

        let withReset = try headlineColumnInk(resets: true)
        let without = try headlineColumnInk(resets: false)

        #expect(without.last > 0, "nothing was drawn in the headline column, so this proves nothing")
        #expect(
            withReset.last > without.last,
            "the countdown row drew no lower than the row without one, so the countdown is missing")

        // The band the countdown occupies, in the row that has one.
        let band = (without.last + 2)...withReset.last
        #expect(
            try !headlineColumnHasInk(resets: false, rows: band),
            "a row with no known reset put something in the countdown band \(band)")
        #expect(
            try headlineColumnHasInk(resets: true, rows: band),
            "the band is empty in the row that does have a reset, so the test is measuring nothing")
    }

    /// Neither row may widen the panel, and the countdown must fit the reserved
    /// headline column rather than truncate inside it.
    @Test
    func theCountdownFitsItsColumnAndLeavesThePanelWidthAlone() throws {
        #expect(try size(resets: true).width == Layout.popoverWidth - Layout.contentPadding * 2)
        #expect(try size(resets: false).width == Layout.popoverWidth - Layout.contentPadding * 2)

        // Every shape the countdown can take, including the longest.
        let font = NSFont.systemFont(ofSize: Typography.size(10))
        let cases = [
            Date(timeIntervalSince1970: 1_800_000_000 + 59 * 60),
            Date(timeIntervalSince1970: 1_800_000_000 + 23 * 3600 + 59 * 60),
            Date(timeIntervalSince1970: 1_800_000_000 + 12 * 86_400 + 23 * 3600),
            Date(timeIntervalSince1970: 1_800_000_000 - 60),
        ]
        for date in cases {
            let text = QuotaFormatting.resetDescription(date, now: now)
            let width = (text as NSString).size(withAttributes: [.font: font]).width
            #expect(
                width <= Layout.headlineColumn,
                "\"\(text)\" is \(width)pt wide and truncates in the \(Layout.headlineColumn)pt column")
        }
    }

    // MARK: - Reading the headline column

    /// Rasterises the row into a fixed, generously tall frame and looks only at
    /// the reserved headline column on the right, where the countdown lives.
    private func bitmap(resets: Bool) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(
            content: OverviewProviderRow(provider: try provider(resets: resets), now: now)
                .monospacedDigit()
                .frame(
                    width: Layout.popoverWidth - Layout.contentPadding * 2,
                    height: 160,
                    alignment: .top)
                .environment(\.colorScheme, .light)
                .background(Color.white))
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        let data = try #require(image.tiffRepresentation)
        return try #require(NSBitmapImageRep(data: data))
    }

    private func columnRange(_ bitmap: NSBitmapImageRep) -> Range<Int> {
        let rowWidth = Layout.popoverWidth - Layout.contentPadding * 2
        let left = Int((rowWidth - Layout.headlineColumn) * 2)
        return max(0, left)..<bitmap.pixelsWide
    }

    private func hasInk(_ bitmap: NSBitmapImageRep, column: Int, row: Int) -> Bool {
        guard let color = bitmap.colorAt(x: column, y: row) else { return false }
        let luminance = 0.2126 * color.redComponent
            + 0.7152 * color.greenComponent
            + 0.0722 * color.blueComponent
        // Well below any antialiasing fringe, so only real glyph ink counts.
        return luminance < 0.6
    }

    private func headlineColumnInk(resets: Bool) throws -> (first: Int, last: Int) {
        let bitmap = try bitmap(resets: resets)
        let columns = columnRange(bitmap)
        var first = Int.max
        var last = -1
        for y in 0..<bitmap.pixelsHigh where columns.contains(where: { hasInk(bitmap, column: $0, row: y) }) {
            first = min(first, y)
            last = max(last, y)
        }
        return (first, last)
    }

    private func headlineColumnHasInk(resets: Bool, rows: ClosedRange<Int>) throws -> Bool {
        let bitmap = try bitmap(resets: resets)
        let columns = columnRange(bitmap)
        return rows.clamped(to: 0...(bitmap.pixelsHigh - 1)).contains { y in
            columns.contains { hasInk(bitmap, column: $0, row: y) }
        }
    }
}

/// The countdown has one implementation, shared by the provider pages and the
/// overview rows. Its contract is the part both callers depend on: a sentence
/// they can print as-is, or nothing at all.
///
/// It lives in QuotaBarCore but is tested here, because the Core test target
/// has no Foundation overlay for swift-testing and so cannot name a `Date`.
struct ResetLineTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000) // 2027-01-15T08:00Z

    @Test
    func aKnownResetReadsAsASentence() {
        #expect(QuotaFormatting.resetLine(from: "2027-01-15T08:45:00.000Z", now: now)
            == "Resets in 45m")
        #expect(
            QuotaFormatting.resetLine(from: "2027-01-15T12:54:00Z", now: now) == "Resets in 4h 54m",
            "a stamp without fractional seconds has to parse too")
    }

    /// Nil, never a dash or an empty pair of brackets: the overview rows have no
    /// room to spend a line on a value nobody reported.
    @Test
    func noResetTimeProducesNoLine() {
        #expect(QuotaFormatting.resetLine(from: nil, now: now) == nil)
        #expect(QuotaFormatting.resetLine(from: "", now: now) == nil)
        #expect(QuotaFormatting.resetLine(from: "not a date", now: now) == nil)
    }

    /// A window already past its reset still says something, because the
    /// provider did report a time and the row should not go blank on it.
    @Test
    func anElapsedResetStillReportsItself() {
        #expect(QuotaFormatting.resetLine(from: "2027-01-15T07:00:00.000Z", now: now) == "Reset due")
    }
}
