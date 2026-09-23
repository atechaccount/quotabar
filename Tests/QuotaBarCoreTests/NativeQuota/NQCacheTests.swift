import AppKit
import Testing
@testable import QuotaBarCore

/// `NQCache` reads and writes the same `~/.cache/quota-axi/quotas.json` file
/// quota-axi itself uses. Every call here passes its own `environment` with a
/// per-test `XDG_CACHE_HOME`, rather than mutating the real process
/// environment, so these tests stay parallel-safe and never touch the real
/// cache on this machine.
struct NQCacheTests {
    @Test
    func testWriteThenReadRoundTripsAFreshProvider() {
        let environment = sandboxEnvironment()
        let draft = NQCommon.successDraft(
            provider: "cursor", label: "Cursor", source: "api",
            windows: [NQCommon.window(id: "included_usage", label: "included usage", kind: "monthly", percentUsed: 10)],
            refreshedAt: "2026-01-01T00:00:00Z", attempts: [NQAttempt(source: "api", status: "success")])
        NQCache.writeCachedProviders([draft], credentialContext: [:], environment: environment)

        let cached = NQCache.readCachedProvider("cursor", environment: environment)
        #expect(cached?.label == "Cursor")
        #expect(cached?.windows.first?.percentRemaining == 90)
    }

    @Test
    func testOnlyFreshDraftsAreCacheable() {
        let environment = sandboxEnvironment()
        let draft = NQCommon.failedDraft(provider: "cursor", label: "Cursor", status: "auth_required", error: "nope", attempts: [])
        NQCache.writeCachedProviders([draft], credentialContext: [:], environment: environment)
        #expect(NQCache.readCachedProvider("cursor", environment: environment) == nil)
    }

    @Test
    func testClaudeStaleReuseRequiresTheSameCredentialContext() {
        let environment = sandboxEnvironment()
        let draft = NQCommon.successDraft(
            provider: "claude", label: "Claude", source: "oauth",
            windows: [NQCommon.window(id: "five_hour", label: "session", kind: "session", percentUsed: 10)],
            refreshedAt: "2026-01-01T00:00:00Z", attempts: [])
        NQCache.writeCachedProviders([draft], credentialContext: ["claude": String(repeating: "a", count: 64)], environment: environment)

        #expect(NQCache.readCachedClaudeProvider(contextId: String(repeating: "a", count: 64), environment: environment) != nil)
        #expect(NQCache.readCachedClaudeProvider(contextId: String(repeating: "b", count: 64), environment: environment) == nil)
    }

    @Test
    func testCodexStaleReuseIsWithheldOnlyOnProvenAccountMismatch() throws {
        let environment = sandboxEnvironment()
        let draft = NQCommon.successDraft(
            provider: "codex", label: "Codex", source: "oauth",
            windows: [NQCommon.window(id: "five_hour", label: "session", kind: "session", percentUsed: 10)],
            refreshedAt: "2026-01-01T00:00:00Z", attempts: [])
        let contextId = try #require(NQCache.codexAccountContextId("acct_1"))
        NQCache.writeCachedProviders([draft], credentialContext: ["codex": contextId], environment: environment)

        // No account names tried at all: served as before (optional stamp).
        #expect(NQCache.readCachedCodexProvider(accountIds: [], environment: environment) != nil)
        // The same account tried again: served.
        #expect(NQCache.readCachedCodexProvider(accountIds: ["acct_1"], environment: environment) != nil)
        // A different account's credentials answered: withheld.
        #expect(NQCache.readCachedCodexProvider(accountIds: ["acct_2"], environment: environment) == nil)
    }

    @Test
    func testWritingOneProviderNeverDisturbsAnother() {
        let environment = sandboxEnvironment()
        let claude = NQCommon.successDraft(
            provider: "claude", label: "Claude", source: "oauth",
            windows: [NQCommon.window(id: "five_hour", label: "session", kind: "session", percentUsed: 1)],
            refreshedAt: "2026-01-01T00:00:00Z", attempts: [])
        NQCache.writeCachedProviders([claude], credentialContext: [:], environment: environment)

        let codex = NQCommon.successDraft(
            provider: "codex", label: "Codex", source: "oauth",
            windows: [NQCommon.window(id: "five_hour", label: "session", kind: "session", percentUsed: 2)],
            refreshedAt: "2026-01-01T00:00:00Z", attempts: [])
        NQCache.writeCachedProviders([codex], credentialContext: [:], environment: environment)

        #expect(NQCache.readCachedProvider("claude", environment: environment) != nil)
        #expect(NQCache.readCachedProvider("codex", environment: environment) != nil)
    }

    @Test
    func testDeleteCachedProviderRemovesOnlyTheDefaultAccountSlot() {
        let environment = sandboxEnvironment()
        let draft = NQCommon.successDraft(
            provider: "claude", label: "Claude", source: "oauth",
            windows: [NQCommon.window(id: "five_hour", label: "session", kind: "session", percentUsed: 1)],
            refreshedAt: "2026-01-01T00:00:00Z", attempts: [])
        NQCache.writeCachedProviders([draft], credentialContext: [:], environment: environment)
        #expect(NQCache.readCachedProvider("claude", environment: environment) != nil)

        NQCache.deleteCachedProvider("claude", environment: environment)
        #expect(NQCache.readCachedProvider("claude", environment: environment) == nil)
    }

    // MARK: - Sandbox

    private func sandboxEnvironment() -> [String: String] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("\(Int.random(in: 0 ..< Int.max))")
        return ["XDG_CACHE_HOME": directory.path]
    }
}
