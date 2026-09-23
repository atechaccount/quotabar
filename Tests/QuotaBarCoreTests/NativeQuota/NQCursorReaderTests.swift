import AppKit
import Testing
@testable import QuotaBarCore

/// Fixture-based tests for the Cursor reader. Cursor is **not signed in on
/// this development machine** (no `state.vscdb`, no CLI login), so unlike
/// Claude and Codex this provider cannot be verified against a live account
/// here. These tests instead exercise the pure normalization logic against
/// captured-shape fixtures, and the credential-resolution decision tree
/// end-to-end against a sandboxed `HOME` with no Cursor installed - the exact
/// "not signed in" case this port must report correctly. See the task report
/// for what live verification would still need to cover.
struct NQCursorReaderTests {
    @Test
    func testNormalizeUsageBuildsTheFourIdeWindows() throws {
        let usage: [String: Any] = [
            "billingCycleEnd": 1_800_000_000,
            "planUsage": ["totalPercentUsed": 20, "autoPercentUsed": 55, "apiPercentUsed": 5],
            "spendLimitUsage": ["individualLimit": 2000, "individualUsed": 500],
        ]
        let planInfo: [String: Any] = ["planInfo": ["planName": "Pro"]]
        let credentials = NQCursorReader.Credentials(accessToken: "tok", email: "dev@example.com", membershipType: nil)

        let result = try #require(NQCursorReader.normalizeCursorUsage(usage, planInfo: planInfo, credentials: credentials, sandUsage: nil))
        #expect(result.plan == "Pro")
        #expect(result.account?.email == "dev@example.com")
        #expect(result.windows.first { $0.id == "included_usage" }?.percentRemaining == 80)
        #expect(result.windows.first { $0.id == "auto_usage" }?.percentRemaining == 45)
        #expect(result.windows.first { $0.id == "api_usage" }?.percentRemaining == 95)
        let spend = result.windows.first { $0.id == "spend_limit" }
        #expect(spend?.spentUsd == 5)
        #expect(spend?.limitUsd == 20)
        #expect(spend?.percentRemaining == 75)
    }

    @Test
    func testNormalizeUsageFallsBackToMembershipTypeWithoutAPlanName() throws {
        let usage: [String: Any] = ["planUsage": ["totalPercentUsed": 1]]
        let credentials = NQCursorReader.Credentials(accessToken: "tok", email: nil, membershipType: "free")
        let result = try #require(NQCursorReader.normalizeCursorUsage(usage, planInfo: nil, credentials: credentials, sandUsage: nil))
        #expect(result.plan == "free")
    }

    @Test
    func testNormalizeUsageReturnsNilWithoutAnyWindow() {
        #expect(NQCursorReader.normalizeCursorUsage([:], planInfo: nil, credentials: .init(accessToken: "t", email: nil, membershipType: nil), sandUsage: nil) == nil)
    }

    @Test
    func testGrokBotWindowIsSkippedUnderAPooledEnterpriseAllowance() {
        #expect(NQCursorReader.grokBotWindow(["usesPooledEnterpriseAllowance": true, "usagePercent": 10]) == nil)
    }

    @Test
    func testGrokBotWindowReportsRemainingFromUsagePercent() throws {
        let window = try #require(NQCursorReader.grokBotWindow(["usagePercent": 30]))
        #expect(window.percentRemaining == 70)
        #expect(window.kind == "weekly")
    }

    @Test
    func testCliIdentityIsMissingWithoutAConfigFile() {
        guard case .missing = NQCursorCliCredential.readIdentity(environment: ["CURSOR_CLI_CONFIG": "/nonexistent-\(UUID().uuidString)"]) else {
            Issue.record("expected missing")
            return
        }
    }

    @Test
    func testCliIdentityReadsEmailAndUserIdFromAuthInfo() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let config = ["authInfo": ["email": "dev@example.com", "userId": "user_1"]]
        try JSONSerialization.data(withJSONObject: config).write(to: file)

        guard case let .present(identity) = NQCursorCliCredential.readIdentity(environment: ["CURSOR_CLI_CONFIG": file.path]) else {
            Issue.record("expected a present identity")
            return
        }
        #expect(identity.email == "dev@example.com")
        #expect(identity.userId == "user_1")
    }

    /// The realistic case on a machine where Cursor was never installed at
    /// all: no editor state database, no CLI login. quota-axi reports
    /// "Cursor sign-in required" without ever attempting a network request,
    /// and this port must do the same.
    @Test
    func testFetchQuotaReportsSignInRequiredWithNeitherStorePresent() async {
        let sandboxHome = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: sandboxHome, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandboxHome) }

        let environment: [String: String] = [
            "HOME": sandboxHome.path,
            // Real PATH so `sqlite3` (a system binary) resolves and the editor
            // store genuinely reports "no such file" rather than "tool missing" -
            // both lead to the same outcome, but this exercises the actual path.
            "PATH": "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin",
            "XDG_CACHE_HOME": sandboxHome.appendingPathComponent(".cache").path,
            "CURSOR_STATE_DB": sandboxHome.appendingPathComponent("no-such-state.vscdb").path,
            "CURSOR_CLI_CONFIG": sandboxHome.appendingPathComponent("no-such-cli-config.json").path,
        ]
        let provider = await NQCursorReader.fetchQuota(readOnly: true, environment: environment)
        #expect(provider.provider == "cursor")
        #expect(provider.state?.status == "auth_required")
        #expect(provider.state?.error == "Cursor sign-in required")
        #expect(provider.windows?.isEmpty ?? true)
        // Both credential stores were consulted and both reported absent.
        let sources = Set((provider.attempts ?? []).map { $0.source ?? "" })
        #expect(sources.contains("state-vscdb"))
        #expect(sources.contains(NQCursorCliCredential.cliSource))
    }
}
