import Testing
@testable import QuotaBarCore

struct ExtraUsageTests {
    private func provider(_ window: String) throws -> QuotaProvider {
        let json = """
        {"providers":[{"provider":"claude","state":{"status":"fresh"},"windows":[
          {"id":"five_hour","kind":"session","percentRemaining":83},\(window)]}]}
        """
        return try #require(QuotaParser.decode(json).providers.first)
    }

    @Test
    func parsesExtraUsageWithoutMakingItAQuotaMeter() throws {
        let claude = try provider(#"{"id":"extra_usage","label":"extra usage","kind":"credits","spentUsd":4.2,"limitUsd":20,"percentUsed":21,"percentRemaining":79}"#)
        #expect(claude.extraUsageWindow?.spentUsd == 4.2)
        #expect(claude.extraUsageWindow?.limitUsd == 20)
        #expect(claude.extraUsageWindow?.percentUsed == 21)
        #expect(claude.usageWindows.count == 1)
        #expect(claude.headline?.percentRemaining == 83)
        #expect(QuotaFormatting.extraUsageLine(
            spentUsd: claude.extraUsageWindow?.spentUsd,
            limitUsd: claude.extraUsageWindow?.limitUsd) == "$4.20 spent - $15.80 left of $20.00")
    }

    @Test
    func formatsZeroAndMissingFieldsWithoutGuessing() throws {
        let zero = try provider(#"{"id":"extra_usage","kind":"credits","spentUsd":0,"limitUsd":50}"#)
        let noCap = try provider(#"{"id":"extra_usage","kind":"credits","spentUsd":4.2}"#)
        let noSpend = try provider(#"{"id":"extra_usage","kind":"credits","limitUsd":50}"#)
        #expect(QuotaFormatting.extraUsageLine(spentUsd: zero.extraUsageWindow?.spentUsd, limitUsd: zero.extraUsageWindow?.limitUsd) == "$0.00 spent - $50.00 left of $50.00")
        #expect(QuotaFormatting.extraUsageLine(spentUsd: noCap.extraUsageWindow?.spentUsd, limitUsd: noCap.extraUsageWindow?.limitUsd) == "$4.20 spent - no cap")
        #expect(QuotaFormatting.extraUsageSpent(noSpend.extraUsageWindow?.spentUsd) == nil)
        #expect(QuotaFormatting.extraUsageLine(spentUsd: noSpend.extraUsageWindow?.spentUsd, limitUsd: noSpend.extraUsageWindow?.limitUsd) == nil)
        #expect(QuotaFormatting.extraUsageSpent(.nan) == nil)
    }

    @Test
    func readoutShowsSpendOnlyForClaudeWhenReported() throws {
        let on = try QuotaParser.decode("""
        {"providers":[{"provider":"claude","label":"Claude","state":{"status":"fresh"},
        "windows":[{"kind":"session","percentRemaining":83},
        {"id":"extra_usage","kind":"credits","spentUsd":4.2,"limitUsd":20}]}]}
        """)
        let off = try QuotaParser.decode("""
        {"providers":[{"provider":"claude","label":"Claude","state":{"status":"fresh"},
        "windows":[{"kind":"session","percentRemaining":83}]}]}
        """)
        let shown = MenuBarReadoutResolver.resolve(
            snapshot: on, mode: .focusedProvider, focusedProvider: "claude", isVisible: { _ in true })
        let hidden = MenuBarReadoutResolver.resolve(
            snapshot: off, mode: .focusedProvider, focusedProvider: "claude", isVisible: { _ in true })
        #expect(shown.extraUsageSpent == "$4.20")
        #expect(shown.accessibilityDescription.contains("$4.20 extra usage spent"))
        #expect(hidden.extraUsageSpent == nil)
        #expect(hidden.accessibilityDescription == "QuotaBar, Claude session 83% remaining")
    }

    @Test
    func zeroSessionChoosesPlainPercentDotOrExactSpend() throws {
        func readout(_ percent: Double, _ extra: String = "") throws -> MenuBarReadout {
            let snapshot = try QuotaParser.decode("""
            {"providers":[{"provider":"claude","state":{"status":"fresh"},"windows":[
            {"kind":"session","percentRemaining":\(percent)}\(extra)]}]}
            """)
            return MenuBarReadoutResolver.resolve(
                snapshot: snapshot, mode: .focusedProvider,
                focusedProvider: "claude", isVisible: { _ in true })
        }

        let off = try readout(0)
        let zero = try readout(0, ",{\"id\":\"extra_usage\",\"kind\":\"credits\",\"spentUsd\":0}")
        let spent = try readout(0, ",{\"id\":\"extra_usage\",\"kind\":\"credits\",\"spentUsd\":4.69}")
        let large = try readout(0, ",{\"id\":\"extra_usage\",\"kind\":\"credits\",\"spentUsd\":99}")
        let aboveZero = try readout(85, ",{\"id\":\"extra_usage\",\"kind\":\"credits\",\"spentUsd\":4.69}")
        let visibleZero = try readout(0.49, ",{\"id\":\"extra_usage\",\"kind\":\"credits\",\"spentUsd\":4.69}")
        let visibleOne = try readout(0.5, ",{\"id\":\"extra_usage\",\"kind\":\"credits\",\"spentUsd\":4.69}")

        #expect(off.extraUsageDollarReadout == nil && !off.showsExtraUsageDot)
        #expect(zero.extraUsageDollarReadout == nil && zero.showsExtraUsageDot)
        #expect(spent.extraUsageDollarReadout == "$4.69" && !spent.showsExtraUsageDot)
        #expect(large.extraUsageDollarReadout == "$99.00" && !large.showsExtraUsageDot)
        #expect(aboveZero.extraUsageDollarReadout == nil && !aboveZero.showsExtraUsageDot)
        #expect(visibleZero.extraUsageDollarReadout == "$4.69")
        #expect(visibleOne.extraUsageDollarReadout == nil)
    }
}
