import AppKit
import Testing
@testable import QuotaBarCore

struct NQClaudeReaderTests {
    @Test
    func testNormalizeApiUsagePrefersScopedLimitsOverFixedFields() throws {
        let raw: [String: Any] = [
            "limits": [
                ["group": "session", "percent": 30.0],
                ["group": "weekly", "percent": 55.0],
                ["scope": ["model": ["id": "opus", "display_name": "Opus"]], "percent": 70.0, "resets_at": "2026-02-01T00:00:00Z"],
            ],
            // Present but must be ignored once `limits` yields any window.
            "five_hour": ["utilization": 99.0],
        ]
        let usage = NQClaudeReader.normalizeClaudeApiUsage(raw, plan: "pro")
        let windows = try #require(usage?.windows)
        #expect(windows.count == 3)
        let session = windows.first { $0.id == "five_hour" }
        #expect(session?.percentUsed == 30)
        #expect(session?.percentRemaining == 70)
        let week = windows.first { $0.id == "seven_day" }
        #expect(week?.percentRemaining == 45)
        let opus = windows.first { $0.id == "model:opus" }
        #expect(opus?.percentRemaining == 30)
        #expect(opus?.resetsAt == "2026-02-01T00:00:00Z")
    }

    @Test
    func testNormalizeApiUsageFallsBackToFixedFieldsWithoutLimits() throws {
        let raw: [String: Any] = [
            "five_hour": ["utilization": 10.0, "resets_at": "2026-01-01T00:00:00Z"],
            "seven_day": ["utilization": 20.0],
        ]
        let usage = NQClaudeReader.normalizeClaudeApiUsage(raw, plan: nil)
        let windows = try #require(usage?.windows)
        #expect(windows.compactMap(\.id).sorted() == ["five_hour", "seven_day"])
        #expect(windows.first { $0.id == "five_hour" }?.windowSeconds == 18_000)
    }

    @Test
    func testExtraUsageWindowOnlyAppearsWhenEnabled() {
        let disabled = NQClaudeReader.normalizeClaudeApiUsage(["five_hour": ["utilization": 1.0], "extra_usage": ["is_enabled": false]], plan: nil)
        #expect(disabled?.windows.contains { $0.id == "extra_usage" } == false)

        let enabled = NQClaudeReader.normalizeClaudeApiUsage([
            "five_hour": ["utilization": 1.0],
            "extra_usage": ["is_enabled": true, "used_credits": 469.0, "monthly_limit": 10000.0, "decimal_places": 2.0],
        ], plan: nil)
        let extra = enabled?.windows.first { $0.id == "extra_usage" }
        #expect(extra?.spentUsd == 4.69)
        #expect(extra?.limitUsd == 100)
        #expect(extra?.percentUsed == 5)
    }

    @Test
    func testNormalizeProfileRequiresAnAccountUuid() {
        #expect(NQClaudeReader.normalizeClaudeProfile(["account": ["email": "x@example.com"]]) == nil)
        let account = NQClaudeReader.normalizeClaudeProfile([
            "account": ["uuid": "abc-123", "email": "x@example.com"],
            "organization": ["name": "Acme"],
        ])
        #expect(account?.accountId == "abc-123")
        #expect(account?.email == "x@example.com")
        #expect(account?.organization == "Acme")
        #expect(account?.identityStatus == "verified")
    }

    @Test
    func testExtractCredentialStateReadsTheClaudeCodeWrapperShape() {
        let json = #"{"claudeAiOauth":{"accessToken":"tok","subscriptionType":"pro"}}"#
        guard case let .available(credential) = NQClaudeReader.extractCredentialState(jsonText: json, source: .oauthFile) else {
            Issue.record("expected an available credential")
            return
        }
        #expect(credential.accessToken == "tok")
        #expect(credential.plan == "pro")
    }

    @Test
    func testExtractCredentialStateClassifiesExpiryAndRefreshability() {
        let past = Date().addingTimeInterval(-3600).timeIntervalSince1970 * 1000
        let expiredWithRefresh = #"{"accessToken":"tok","expiresAt":\#(past),"refreshToken":"r"}"#
        guard case let .expired(_, refreshable) = NQClaudeReader.extractCredentialState(jsonText: expiredWithRefresh, source: .keychain) else {
            Issue.record("expected an expired credential")
            return
        }
        #expect(refreshable)

        let future = Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000
        let stillValid = #"{"accessToken":"tok","expiresAt":\#(future)}"#
        guard case .available = NQClaudeReader.extractCredentialState(jsonText: stillValid, source: .keychain) else {
            Issue.record("expected an available credential")
            return
        }
    }

    @Test
    func testExtractCredentialStateRejectsAMissingAccessToken() {
        guard case let .invalid(source, present) = NQClaudeReader.extractCredentialState(jsonText: "{}", source: .oauthFile) else {
            Issue.record("expected an invalid credential")
            return
        }
        #expect(source == "oauth-file")
        #expect(!present)
    }
}
