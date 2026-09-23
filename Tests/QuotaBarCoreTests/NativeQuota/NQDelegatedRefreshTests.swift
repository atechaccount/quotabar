import Testing
@testable import QuotaBarCore

/// Covers the refresh-decision rules ported from `providers/delegated-
/// refresh.js` and the `isLiveClaudeCodeProcess` concurrency guard from
/// `providers/claude.js`. These are the rules that keep the native Claude
/// reader from ever racing or rotating a token a live Claude Code session
/// still uses.
struct NQDelegatedRefreshTests {
    @Test
    func testUnavailableCommandIsSkippedRatherThanFailed() async {
        let delegate = NQDelegatedRefresh.Delegate(
            source: "claude-cli-refresh", command: "definitely-not-a-real-command-\(Int.random(in: 0 ..< Int.max))",
            args: [], waitBudgetMs: 200)
        let outcome = await NQDelegatedRefresh.run(delegate)
        guard case .unavailable(let error) = outcome else {
            Issue.record("expected unavailable")
            return
        }
        #expect(error == NQDelegatedRefresh.commandNotFound)
        let attempt = NQDelegatedRefresh.attempt(delegate, outcome: outcome)
        #expect(attempt.status == "skipped")
        #expect(attempt.error == NQDelegatedRefresh.commandNotFound)
    }

    @Test
    func testASuccessfulRunReportsExitStatusZeroAsSuccess() async {
        let delegate = NQDelegatedRefresh.Delegate(source: "claude-cli-refresh", command: "/usr/bin/true", args: [], waitBudgetMs: 2000)
        let outcome = await NQDelegatedRefresh.run(delegate)
        guard case .ran(let exitCode) = outcome else {
            Issue.record("expected the command to run")
            return
        }
        #expect(exitCode == 0)
        #expect(NQDelegatedRefresh.attempt(delegate, outcome: outcome).status == "success")
    }

    @Test
    func testANonZeroExitIsReportedAsFailedNeverAsSuccess() async {
        let delegate = NQDelegatedRefresh.Delegate(source: "claude-cli-refresh", command: "/usr/bin/false", args: [], waitBudgetMs: 2000)
        let outcome = await NQDelegatedRefresh.run(delegate)
        let attempt = NQDelegatedRefresh.attempt(delegate, outcome: outcome)
        #expect(attempt.status == "failed")
        #expect(attempt.error == NQDelegatedRefresh.exitStatusError)
    }

    @Test
    func testATimedOutDelegateIsUnconfirmedRatherThanKilled() async {
        // /bin/sleep outlives the wait budget; the rule under test is that
        // quota-axi never sends it a signal and simply stops waiting.
        let delegate = NQDelegatedRefresh.Delegate(source: "claude-cli-refresh", command: "/bin/sleep", args: ["5"], waitBudgetMs: 100)
        let outcome = await NQDelegatedRefresh.run(delegate)
        guard case .unconfirmed(let error) = outcome else {
            Issue.record("expected the wait to give up before the process exits")
            return
        }
        #expect(error == NQDelegatedRefresh.timedOut)
    }

    // MARK: - isLiveClaudeCodeProcess

    @Test
    func testRecognizesTheInstalledClaudeExecutableAsArgvZero() {
        #expect(NQClaudeProcessGuard.isLiveClaudeCodeProcess("claude"))
        #expect(NQClaudeProcessGuard.isLiveClaudeCodeProcess("/usr/local/bin/claude --resume"))
        #expect(NQClaudeProcessGuard.isLiveClaudeCodeProcess("node /opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/cli.js"))
    }

    @Test
    func testDoesNotMistakeAnUnrelatedCommandMentioningClaudeForALiveSession() {
        #expect(!NQClaudeProcessGuard.isLiveClaudeCodeProcess("grep claude /var/log/system.log"))
        #expect(!NQClaudeProcessGuard.isLiveClaudeCodeProcess("vim claude-notes.md"))
    }
}
