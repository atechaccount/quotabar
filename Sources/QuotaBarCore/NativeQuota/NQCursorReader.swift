import Foundation

/// Ports `providers/cursor.js` from quota-axi 0.1.51.
///
/// **No token refresh at all**, matching upstream exactly: neither the editor
/// (`state.vscdb`) nor the CLI (Keychain `cursor-access-token`) path ever
/// exchanges or rotates a token. A 401/403 from Cursor's dashboard API falls
/// back from the editor credential to the CLI credential (a different store
/// that may still be valid); if both are rejected, quota-axi (and this port)
/// report sign-in required or fall back to an eligible stale snapshot.
///
/// Cursor is **not signed in on this development machine**, so the live path
/// below is verified only by fixture-based unit tests
/// (`NativeCursorReaderTests`), not by a side-by-side live comparison. See the
/// task report for how to complete that verification once Cursor is
/// available.
enum NQCursorReader {
    private static let apiURL = URL(string: "https://api2.cursor.sh")!
    private static let apiTimeout: TimeInterval = 15
    private static let sqliteTimeout: TimeInterval = 5

    struct Credentials {
        var accessToken: String
        var email: String?
        var membershipType: String?
    }

    private enum CredentialResolution {
        case available(Credentials, source: String)
        case unavailable(primaryError: String)
    }

    static func fetchQuota(readOnly: Bool, environment: [String: String] = ProcessInfo.processInfo.environment) async -> QuotaProvider {
        var attempts: [NQAttempt] = []
        var retryAfter: String?
        var finalError = "Cursor quota unavailable"

        let resolution = await resolveCredentials(environment: environment, attempts: &attempts)
        switch resolution {
        case let .available(credentials, source):
            let quotaSource = (source == "state-vscdb") ? "api" : source
            attempts.append(NQAttempt(source: quotaSource, status: "failed"))
            do {
                let quota = try await fetchCursorUsage(credentials)
                attempts[attempts.count - 1] = NQAttempt(source: quotaSource, status: "success")
                return cursorSuccess(quota, attempts: attempts, environment: environment)
            } catch let error as CursorFetchError {
                finalError = error.message
                attempts[attempts.count - 1] = NQAttempt(source: quotaSource, status: "failed", error: finalError)
                if case .authRejected = error, source == "state-vscdb" {
                    attempts[attempts.count - 1] = NQAttempt(source: "state-vscdb", status: "failed", error: finalError)
                    let cliState = await NQCursorCliCredential.readCredentialState(environment: environment)
                    switch cliState {
                    case let .available(accessToken, identity):
                        attempts.append(NQAttempt(source: NQCursorCliCredential.cliSource, status: "failed"))
                        do {
                            let credentials = Credentials(accessToken: accessToken, email: identity.email, membershipType: nil)
                            let quota = try await fetchCursorUsage(credentials)
                            attempts[attempts.count - 1] = NQAttempt(source: NQCursorCliCredential.cliSource, status: "success")
                            return cursorSuccess(quota, attempts: attempts, environment: environment)
                        } catch let cliError as CursorFetchError {
                            finalError = cliError.message
                            attempts[attempts.count - 1] = NQAttempt(source: NQCursorCliCredential.cliSource, status: "failed", error: finalError)
                            if case let .rateLimited(after) = cliError { retryAfter = after }
                        } catch {
                            finalError = "Cursor quota unavailable"
                        }
                    default:
                        let (skipError, present) = cursorCliSkip(cliState)
                        attempts.append(NQAttempt(
                            source: NQCursorCliCredential.cliSource, status: "skipped", error: skipError,
                            credentialPresent: present ? true : nil))
                    }
                } else if case let .rateLimited(after) = error {
                    retryAfter = after
                }
            } catch {
                finalError = "Cursor quota unavailable"
            }
        case let .unavailable(primaryError):
            finalError = primaryError == "credentials_missing" ? "Cursor sign-in required" : primaryError
        }

        if let cached = NQCache.readCachedProvider("cursor", environment: environment) {
            let draft = NQCommon.staleFromCache(
                cached, error: finalError, sourcesTried: NQCommon.sourceNames(attempts), attempts: attempts)
            return NQCommon.finalize(draft, generatedAt: NQTime.nowIso())
        }
        let draft = NQCommon.failedDraft(
            provider: "cursor", label: "Cursor",
            status: retryAfter != nil ? "rate_limited" : NQCommon.statusFromError(finalError), error: finalError,
            retryAfter: retryAfter, attempts: attempts)
        return NQCommon.finalize(draft, generatedAt: NQTime.nowIso())
    }

    /// Mirrors `resolveCredentials`: the non-prompting editor store first, then
    /// the platform CLI credential when the editor token is absent, unreadable,
    /// or was never tried.
    private static func resolveCredentials(environment: [String: String], attempts: inout [NQAttempt]) async -> CredentialResolution {
        let editorState = await readEditorCredentialState(environment: environment)
        switch editorState {
        case let .available(credentials):
            return .available(credentials, source: "state-vscdb")
        case let .missing(source, path):
            attempts.append(NQAttempt(source: source, status: "skipped", error: "credentials_\(missingLabel(path))"))
        case let .skipped(source, error, present):
            attempts.append(NQAttempt(source: source, status: "skipped", error: error, credentialPresent: present ? true : nil))
        }
        let editorMissingError = editorErrorCode(editorState)

        let cliState = await NQCursorCliCredential.readCredentialState(environment: environment)
        if case let .available(accessToken, identity) = cliState {
            return .available(Credentials(accessToken: accessToken, email: identity.email, membershipType: nil), source: NQCursorCliCredential.cliSource)
        }
        let (skipError, present) = cursorCliSkip(cliState)
        attempts.append(NQAttempt(source: NQCursorCliCredential.cliSource, status: "skipped", error: skipError, credentialPresent: present ? true : nil))
        // Prefer naming a source that still holds a credential (a Keychain value
        // waiting on the prompt) over a "missing" editor store, so the reported
        // error carries its actual remedy - mirrors `primaryUnavailable`.
        if present { return .unavailable(primaryError: skipError) }
        return .unavailable(primaryError: editorMissingError)
    }

    private enum EditorCredentialState {
        case available(Credentials)
        case missing(source: String, path: String)
        case skipped(source: String, error: String, credentialPresent: Bool)
    }

    private static func editorErrorCode(_ state: EditorCredentialState) -> String {
        switch state {
        case .available: return ""
        case .missing: return "credentials_missing"
        case let .skipped(_, error, _): return error
        }
    }

    private static func missingLabel(_ path: String) -> String { "missing" }

    private static func readEditorCredentialState(environment: [String: String]) async -> EditorCredentialState {
        let path = stateDbPath(environment: environment)
        guard NQProcess.commandExists("sqlite3") else {
            return .skipped(source: "state-vscdb", error: "sqlite3_unavailable", credentialPresent: true)
        }
        guard let accessToken = try? await readStateValue(key: "cursorAuth/accessToken", path: path), !accessToken.isEmpty else {
            return .missing(source: "state-vscdb", path: path)
        }
        let email = try? await readStateValue(key: "cursorAuth/cachedEmail", path: path)
        let membershipType = try? await readStateValue(key: "cursorAuth/stripeMembershipType", path: path)
        return .available(Credentials(accessToken: accessToken, email: email, membershipType: membershipType))
    }

    private static func readStateValue(key: String, path: String) async throws -> String? {
        let escaped = key.replacingOccurrences(of: "'", with: "''")
        let output = try await NQProcess.execFileText(
            "sqlite3", ["-readonly", path, "select value from ItemTable where key = '\(escaped)' limit 1;"],
            timeout: sqliteTimeout)
        let value = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if let data = value.data(using: .utf8), let parsed = try? JSONSerialization.jsonObject(with: data) as? String,
           !parsed.isEmpty
        {
            return parsed
        }
        return value
    }

    private static func stateDbPath(environment: [String: String]) -> String {
        if let override = environment["CURSOR_STATE_DB"], !override.isEmpty { return override }
        return (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
    }

    private static func cursorCliSkip(_ state: NQCursorCliCredential.State) -> (error: String, present: Bool) {
        switch state {
        case .available: return ("", false)
        case .missing: return ("credentials_missing", false)
        case .invalid: return ("credentials_invalid", true)
        case let .skipped(error, present): return (error, present)
        }
    }

    // MARK: - HTTP

    private enum CursorFetchError: Error {
        case authRejected
        case rateLimited(retryAfter: String?)
        case other(message: String)

        var message: String {
            switch self {
            case .authRejected: return "Cursor sign-in required"
            case .rateLimited: return "Cursor quota endpoint rate limited"
            case let .other(message): return message
            }
        }
    }

    private static func fetchCursorUsage(_ credentials: Credentials) async throws -> (plan: String?, account: ProviderAccount?, windows: [QuotaWindow]) {
        async let usage = postDashboardRpc(credentials.accessToken, "GetCurrentPeriodUsage")
        async let plan = try? postDashboardRpc(credentials.accessToken, "GetPlanInfo")
        async let sand = try? postDashboardRpc(credentials.accessToken, "GetSandUsageStatus")
        let usageValue = try await usage
        let quota = normalizeCursorUsage(usageValue, planInfo: await plan, credentials: credentials, sandUsage: await sand)
        guard let quota else { throw CursorFetchError.other(message: "Cursor quota unavailable") }
        return quota
    }

    private static func postDashboardRpc(_ accessToken: String, _ method: String) async throws -> [String: Any] {
        var request = URLRequest(
            url: apiURL.appendingPathComponent("aiserver.v1.DashboardService/\(method)"), timeoutInterval: apiTimeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "authorization")
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("1", forHTTPHeaderField: "connect-protocol-version")
        request.httpBody = Data("{}".utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CursorFetchError.other(message: "Cursor quota unavailable") }
        if http.statusCode == 401 || http.statusCode == 403 { throw CursorFetchError.authRejected }
        if http.statusCode == 429 {
            throw CursorFetchError.rateLimited(retryAfter: NQTime.retryAfterToIso(http.value(forHTTPHeaderField: "retry-after")))
        }
        guard (200 ... 299).contains(http.statusCode) else {
            throw CursorFetchError.other(message: "Cursor quota unavailable (\(http.statusCode))")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return json
    }

    // MARK: - Normalization

    static func normalizeCursorUsage(
        _ usage: [String: Any], planInfo: [String: Any]?, credentials: Credentials, sandUsage: [String: Any]?
    ) -> (plan: String?, account: ProviderAccount?, windows: [QuotaWindow])? {
        let plan = (planInfo?["planInfo"] as? [String: Any])
        let planName = (plan?["planName"] as? String)?.nqNilIfEmpty ?? (plan?["price"] as? String)?.nqNilIfEmpty
            ?? credentials.membershipType

        // `billingCycleStart`/`startsAt` is dropped: QuotaBarCore's `QuotaWindow`
        // never decodes a `startsAt` field, matching what it already ignores
        // from bundled quota-axi's own `--full` JSON.
        let reset = parseEpochMillisOrIso(usage["billingCycleEnd"]) ?? parseEpochMillisOrIso(plan?["billingCycleEnd"])
        let planUsage = usage["planUsage"] as? [String: Any]

        var windows: [QuotaWindow] = []
        if let total = numberValue(planUsage?["totalPercentUsed"]) {
            windows.append(NQCommon.window(
                id: "included_usage", label: "included usage", kind: "monthly", percentUsed: NQTime.clampPercent(total),
                resetsAt: reset))
        }
        if let auto = numberValue(planUsage?["autoPercentUsed"]) {
            windows.append(NQCommon.window(
                id: "auto_usage", label: "auto usage", kind: "monthly", percentUsed: NQTime.clampPercent(auto),
                resetsAt: reset))
        }
        if let api = numberValue(planUsage?["apiPercentUsed"]) {
            windows.append(NQCommon.window(
                id: "api_usage", label: "API usage", kind: "monthly", percentUsed: NQTime.clampPercent(api),
                resetsAt: reset))
        }

        let spend = usage["spendLimitUsage"] as? [String: Any]
        let individualLimit = numberValue(spend?["individualLimit"])
        let individualRemaining = numberValue(spend?["individualRemaining"])
        let individualUsed = numberValue(spend?["individualUsed"])
            ?? (individualLimit != nil && individualRemaining != nil ? individualLimit! - individualRemaining! : nil)
        if let individualLimit, individualLimit > 0 {
            let percentUsed = individualUsed.map { NQTime.clampPercent(($0 / individualLimit) * 100) }
            windows.append(NQCommon.window(
                id: "spend_limit", label: "spend limit", kind: "credits", percentUsed: percentUsed,
                spentUsd: individualUsed.map { $0 / 100 }, limitUsd: individualLimit / 100, resetsAt: reset))
        }

        if let grokBot = grokBotWindow(sandUsage) { windows.append(grokBot) }
        guard !windows.isEmpty else { return nil }

        let account = ProviderAccount(accountId: nil, email: credentials.email?.nqNilIfEmpty, organization: nil, identityStatus: nil)
        return (planName, account, windows)
    }

    static func grokBotWindow(_ sandUsage: [String: Any]?) -> QuotaWindow? {
        guard let data = sandUsage else { return nil }
        let pooled = (data["usesPooledEnterpriseAllowance"] as? Bool) ?? (data["uses_pooled_enterprise_allowance"] as? Bool)
        if pooled == true { return nil }
        guard let percent = numberValue(data["usagePercent"] ?? data["usage_percent"]) else { return nil }
        let resetsAt = parseEpochMillisOrIso(data["nextResetTimestampUtc"] ?? data["next_reset_timestamp_utc"])
        return NQCommon.window(
            id: "grok_bot", label: "Grok Bot", kind: "weekly", percentUsed: NQTime.clampPercent(percent),
            resetsAt: resetsAt)
    }

    private static func parseEpochMillisOrIso(_ value: Any?) -> String? {
        if let number = numberValue(value) {
            let seconds = number > 10_000_000_000 ? number / 1000 : number
            return ISO8601DateFormatter.nqFractional.string(from: Date(timeIntervalSince1970: seconds))
        }
        guard let string = value as? String, !string.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        if let asNumber = Double(string) { return parseEpochMillisOrIso(asNumber) }
        guard let date = ISO8601DateFormatter.nqFractional.date(from: string) ?? ISO8601DateFormatter.nqPlain.date(from: string)
        else { return nil }
        return ISO8601DateFormatter.nqFractional.string(from: date)
    }

    private static func numberValue(_ value: Any?) -> Double? {
        if let number = value as? Double { return number }
        if let number = value as? Int { return Double(number) }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static func cursorSuccess(
        _ quota: (plan: String?, account: ProviderAccount?, windows: [QuotaWindow]), attempts: [NQAttempt],
        environment: [String: String]
    ) -> QuotaProvider {
        let draft = NQCommon.successDraft(
            provider: "cursor", label: "Cursor", source: "api", plan: quota.plan, account: quota.account,
            windows: quota.windows, refreshedAt: NQTime.nowIso(), attempts: attempts)
        NQCache.writeCachedProviders([draft], credentialContext: [:], environment: environment)
        return NQCommon.finalize(draft, generatedAt: NQTime.nowIso())
    }
}

private extension String {
    var nqNilIfEmpty: String? { isEmpty ? nil : self }
}
