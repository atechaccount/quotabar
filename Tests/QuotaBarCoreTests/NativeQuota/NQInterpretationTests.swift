import Testing
@testable import QuotaBarCore

struct NQInterpretationTests {
    private let generatedAt = "2026-01-01T00:00:00Z"

    @Test
    func testClaudeAccountWindowsBoundEveryModel() {
        let windows = [
            NQCommon.window(id: "five_hour", label: "session", kind: "session", percentUsed: 10),
            NQCommon.window(id: "seven_day", label: "week", kind: "weekly", percentUsed: 40),
            NQCommon.window(id: "model:opus", label: "Opus week", kind: "model", percentUsed: 80),
        ]
        let semantics = NQInterpretation.semantics(for: "claude", windows: windows, generatedAt: generatedAt)
        #expect(semantics.status == "known")
        let all = semantics.effectiveAvailability?.first { $0.scope == "all_models" }
        #expect(all?.effectivePercentRemaining == 60)
        let opus = semantics.effectiveAvailability?.first { $0.scope == "model:opus" }
        // Minimum across the account windows (60) and the model window (20).
        #expect(opus?.effectivePercentRemaining == 20)
    }

    @Test
    func testClaudeUnfamiliarWindowMarksPartial() {
        let windows = [
            NQCommon.window(id: "five_hour", label: "session", kind: "session", percentUsed: 10),
            NQCommon.window(id: "mystery", label: "mystery", kind: "unknown", percentUsed: 5),
        ]
        let semantics = NQInterpretation.semantics(for: "claude", windows: windows, generatedAt: generatedAt)
        #expect(semantics.status == "partial")
        #expect(semantics.unresolvedWindowIds == ["mystery"])
    }

    @Test
    func testCodexModelScopeMinimumAcrossAccountAndModel() {
        let windows = [
            NQCommon.window(id: "five_hour", label: "session", kind: "session", percentUsed: 20),
            NQCommon.window(id: "weekly", label: "week", kind: "weekly", percentUsed: 10),
            NQCommon.window(id: "model:gpt5:5h", label: "GPT-5 session", kind: "model", percentUsed: 90),
        ]
        let semantics = NQInterpretation.semantics(for: "codex", windows: windows, generatedAt: generatedAt)
        let gpt5 = semantics.effectiveAvailability?.first { $0.scope == "model:gpt5" }
        // Account minimum (80) versus the model's own remaining (10) -> 10.
        #expect(gpt5?.effectivePercentRemaining == 10)
    }

    @Test
    func testCodexBoundConflictReportsUnknownRatherThanInheritedZero() {
        // The account window is fully exhausted (0 remaining) but the model's own
        // window still reports headroom - a contradiction, not exhaustion.
        let windows = [
            NQCommon.window(id: "five_hour", label: "session", kind: "session", percentUsed: 100),
            NQCommon.window(id: "model:gpt5:5h", label: "GPT-5 session", kind: "model", percentUsed: 10),
        ]
        let semantics = NQInterpretation.semantics(for: "codex", windows: windows, generatedAt: generatedAt)
        let gpt5 = semantics.effectiveAvailability?.first { $0.scope == "model:gpt5" }
        #expect(gpt5?.status == "unknown")
        #expect(gpt5?.effectivePercentRemaining == nil)
    }

    @Test
    func testCodexCodeReviewWindowsAreASeparateScope() {
        let windows = [
            NQCommon.window(id: "five_hour", label: "session", kind: "session", percentUsed: 10),
            NQCommon.window(id: "weekly", label: "week", kind: "weekly", percentUsed: 10),
            NQCommon.window(id: "code_review_five_hour", label: "code review session", kind: "session", percentUsed: 50),
        ]
        let semantics = NQInterpretation.semantics(for: "codex", windows: windows, generatedAt: generatedAt)
        let codeReview = semantics.effectiveAvailability?.first { $0.scope == "code_review" }
        #expect(codeReview?.effectivePercentRemaining == 50)
        let allModels = semantics.effectiveAvailability?.first { $0.scope == "all_models" }
        #expect(allModels?.effectivePercentRemaining == 90)
    }

    @Test
    func testCursorJointlyBoundsIdeWindowsSeparatelyFromGrokBot() {
        let windows = [
            NQCommon.window(id: "included_usage", label: "included usage", kind: "monthly", percentUsed: 20),
            NQCommon.window(id: "auto_usage", label: "auto usage", kind: "monthly", percentUsed: 90),
            NQCommon.window(id: "grok_bot", label: "Grok Bot", kind: "weekly", percentUsed: 5),
        ]
        let semantics = NQInterpretation.semantics(for: "cursor", windows: windows, generatedAt: generatedAt)
        let allModels = semantics.effectiveAvailability?.first { $0.scope == "all_models" }
        #expect(allModels?.effectivePercentRemaining == 10)
        let grokBot = semantics.effectiveAvailability?.first { $0.scope == "grok_bot" }
        #expect(grokBot?.effectivePercentRemaining == 95)
    }

    @Test
    func testCursorUnfamiliarWindowStaysUnresolvedButKeepsKnownScopes() {
        let windows = [
            NQCommon.window(id: "included_usage", label: "included usage", kind: "monthly", percentUsed: 20),
            NQCommon.window(id: "surprise", label: "surprise", kind: "unknown", percentUsed: 1),
        ]
        let semantics = NQInterpretation.semantics(for: "cursor", windows: windows, generatedAt: generatedAt)
        #expect(semantics.status == "partial")
        #expect(semantics.unresolvedWindowIds == ["surprise"])
        #expect(semantics.effectiveAvailability?.first { $0.scope == "all_models" }?.effectivePercentRemaining == 80)
    }

    @Test
    func testStaleSemanticsDropsTheNumberButKeepsScopeIdentity() {
        let windows = [NQCommon.window(id: "five_hour", label: "session", kind: "session", percentUsed: 10)]
        let fresh = NQInterpretation.semantics(for: "claude", windows: windows, generatedAt: generatedAt)
        let stale = NQInterpretation.staleSemantics(fresh)
        #expect(stale.status == "unknown")
        #expect(stale.effectiveAvailability?.first?.scope == "all_models")
        #expect(stale.effectiveAvailability?.first?.effectivePercentRemaining == nil)
    }
}
