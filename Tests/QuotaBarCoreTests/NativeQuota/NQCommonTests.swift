import Testing
@testable import QuotaBarCore

struct NQCommonTests {
    @Test
    func testClampPercentRoundsAndClamps() {
        #expect(NQTime.clampPercent(50.4) == 50)
        #expect(NQTime.clampPercent(50.6) == 51)
        #expect(NQTime.clampPercent(-5) == 0)
        #expect(NQTime.clampPercent(150) == 100)
        #expect(NQTime.clampPercent(.nan) == 0)
    }

    @Test
    func testPercentRemainingMirrorsUsed() {
        #expect(NQTime.percentRemaining(30) == 70)
        #expect(NQTime.percentRemaining(nil) == nil)
        #expect(NQTime.percentRemaining(0) == 100)
        #expect(NQTime.percentRemaining(100) == 0)
    }

    @Test
    func testStatusFromErrorClassifiesKnownShapes() {
        #expect(NQCommon.statusFromError("keychain_prompt_required") == "auth_required")
        #expect(NQCommon.statusFromError("credentials_expired") == "auth_required")
        #expect(NQCommon.statusFromError("Claude sign-in required") == "auth_required")
        #expect(NQCommon.statusFromError("Codex quota endpoint rate limited") == "rate_limited")
        #expect(NQCommon.statusFromError("Codex quota unavailable (503)") == "error")
    }

    @Test
    func testSourceNamesDeduplicatesPreservingOrder() {
        let attempts = [
            NQAttempt(source: "oauth", status: "failed"),
            NQAttempt(source: "keychain", status: "skipped"),
            NQAttempt(source: "oauth", status: "success"),
        ]
        #expect(NQCommon.sourceNames(attempts) == ["oauth", "keychain"])
    }

    @Test
    func testWindowBuilderDerivesPercentRemaining() {
        let window = NQCommon.window(id: "five_hour", label: "session", kind: "session", percentUsed: 40)
        #expect(window.percentUsed == 40)
        #expect(window.percentRemaining == 60)
    }

    @Test
    func testFinalizeAttachesQuotaSemanticsFromInterpretation() {
        let windows = [
            NQCommon.window(id: "five_hour", label: "session", kind: "session", percentUsed: 10),
            NQCommon.window(id: "seven_day", label: "week", kind: "weekly", percentUsed: 40),
        ]
        let draft = NQCommon.successDraft(
            provider: "claude", label: "Claude", source: "oauth", windows: windows, refreshedAt: "2026-01-01T00:00:00Z",
            attempts: [NQAttempt(source: "oauth", status: "success")])
        let provider = NQCommon.finalize(draft, generatedAt: "2026-01-01T00:00:00Z")

        #expect(provider.state?.status == "fresh")
        #expect(provider.state?.stale == false)
        #expect(provider.quotaSemantics?.status == "known")
        let allModels = provider.quotaSemantics?.effectiveAvailability?.first { $0.scope == "all_models" }
        #expect(allModels?.effectivePercentRemaining == 60)
    }

    @Test
    func testFinalizeMarksStaleReadingsUnknownRatherThanReusingTheOldNumber() {
        let windows = [NQCommon.window(id: "five_hour", label: "session", kind: "session", percentUsed: 10)]
        var draft = NQCommon.successDraft(
            provider: "claude", label: "Claude", source: "cache", windows: windows, refreshedAt: nil, attempts: [])
        draft.status = "stale"
        draft.stale = true
        let provider = NQCommon.finalize(draft, generatedAt: "2026-01-01T00:00:00Z")

        #expect(provider.quotaSemantics?.effectiveAvailability?.first?.status == "unknown")
        #expect(provider.quotaSemantics?.effectiveAvailability?.first?.effectivePercentRemaining == nil)
        // The window itself still carries its own last-known percentage, which is
        // what the headline actually reads for a stale-but-recent snapshot.
        #expect(provider.windows?.first?.percentRemaining == 90)
    }
}
