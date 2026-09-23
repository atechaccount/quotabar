import AppKit
import Testing
@testable import QuotaBarCore

struct NQCodexReaderTests {
    @Test
    func testNormalizeUsagePairsPrimaryAndSecondaryWindows() throws {
        let raw: [String: Any] = [
            "rate_limit": [
                "primary_window": ["used_percent": 25.0, "limit_window_seconds": 18_000.0],
                "secondary_window": ["used_percent": 60.0, "limit_window_seconds": 604_800.0],
            ],
            "plan_type": "plus",
            "email": "dev@example.com",
            "account_id": "acct_1",
        ]
        let usage = try #require(NQCodexReader.normalizeCodexUsage(raw))
        #expect(usage.plan == "plus")
        #expect(usage.account?.email == "dev@example.com")
        #expect(usage.account?.accountId == "acct_1")
        let session = usage.windows.first { $0.id == "five_hour" }
        #expect(session?.percentRemaining == 75)
        let weekly = usage.windows.first { $0.id == "weekly" }
        #expect(weekly?.percentRemaining == 40)
    }

    @Test
    func testNormalizeUsageNamesAnUnfamiliarWindowDurationRatherThanDropping() throws {
        let raw: [String: Any] = [
            "rate_limit": [
                "primary_window": ["used_percent": 10.0, "limit_window_seconds": 3600.0],
            ],
        ]
        let usage = try #require(NQCodexReader.normalizeCodexUsage(raw))
        #expect(usage.windows.first?.id == "window:1h")
        #expect(usage.windows.first?.kind == "unknown")
    }

    @Test
    func testNormalizeUsageCollectsNamedModelLimitsFromTheAppServerShape() throws {
        let raw: [String: Any] = [
            "rate_limit": ["primary_window": ["used_percent": 5.0, "limit_window_seconds": 18_000.0]],
            "rateLimitsByLimitId": [
                "gpt5": ["limitName": "GPT-5", "primary_window": ["used_percent": 40.0, "limit_window_seconds": 18_000.0]],
            ],
        ]
        let usage = try #require(NQCodexReader.normalizeCodexUsage(raw))
        let model = usage.windows.first { $0.id == "model:gpt5:5h" }
        #expect(model?.label == "GPT-5 session")
        #expect(model?.percentRemaining == 60)
    }

    @Test
    func testNormalizeUsageReturnsNilWithoutAnyRecognizedWindow() {
        #expect(NQCodexReader.normalizeCodexUsage([:]) == nil)
    }

    @Test
    func testReadCredentialStateTreatsAnExpiredJwtAsAdvisoryNotFatal() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let authFile = directory.appendingPathComponent("auth.json")

        let expiredToken = makeJwt(claims: ["exp": Int(Date().addingTimeInterval(-3600).timeIntervalSince1970)])
        let auth = ["tokens": ["access_token": expiredToken, "account_id": "acct_9"]]
        try JSONSerialization.data(withJSONObject: auth).write(to: authFile)

        let state = NQCodexReader.readCredentialState(environment: ["CODEX_HOME": directory.path])
        guard case let .expired(credentials) = state else {
            Issue.record("expected an expired-but-readable credential")
            return
        }
        #expect(credentials.accessToken == expiredToken)
        #expect(credentials.accountId == "acct_9")
    }

    @Test
    func testReadCredentialStateIsMissingWithoutAnAuthFile() {
        let state = NQCodexReader.readCredentialState(environment: ["CODEX_HOME": "/nonexistent-\(UUID().uuidString)"])
        guard case .missing = state else {
            Issue.record("expected missing")
            return
        }
    }

    @Test
    func testReadCredentialStateDecodesAccountIdFromTheIdTokenWhenAbsentFromTokens() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let authFile = directory.appendingPathComponent("auth.json")

        let future = Int(Date().addingTimeInterval(3600).timeIntervalSince1970)
        let accessToken = makeJwt(claims: ["exp": future])
        let idToken = makeJwt(claims: ["https://api.openai.com/auth/account_id": "acct_from_id"])
        let auth = ["tokens": ["access_token": accessToken, "id_token": idToken]]
        try JSONSerialization.data(withJSONObject: auth).write(to: authFile)

        let state = NQCodexReader.readCredentialState(environment: ["CODEX_HOME": directory.path])
        guard case let .available(credentials) = state else {
            Issue.record("expected an available credential")
            return
        }
        #expect(credentials.accountId == "acct_from_id")
    }

    // MARK: - Helpers

    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// An unsigned JWT-shaped token: header/payload/signature, with only the
    /// payload carrying real content. Reading it never validates the signature,
    /// matching quota-axi's own `decodeJwtPayload`.
    private func makeJwt(claims: [String: Any]) -> String {
        let header = base64url(try! JSONSerialization.data(withJSONObject: ["alg": "none"]))
        let payload = base64url(try! JSONSerialization.data(withJSONObject: claims))
        return "\(header).\(payload).sig"
    }

    private func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
