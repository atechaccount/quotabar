import Foundation

/// Ports `providers/codex.js` from quota-axi 0.1.51, for the single-account
/// case QuotaBar actually uses (no `--provider` account expansion). See
/// `docs/native-quota-porting.md` for the file map.
///
/// **No token refresh at all.** Unlike Claude, Codex has no delegated-refresh
/// path in quota-axi: the stored `auth.json` access token's JWT `exp` claim is
/// read only as advisory ordering metadata (`extractCredentialState`); the
/// live endpoint is always the one that decides authentication
/// (`attemptCodexCandidate`), and a rejected token simply falls through to a
/// read-only `codex ... app-server` probe of the same on-disk session - it
/// never rotates or exchanges anything.
///
/// Not ported, deliberately:
/// - The Pi credential broker's OAuth-entry parsing (`pi-codex-credential.js`):
///   only its "is there a Pi auth file at all" existence check is kept, so a
///   machine with no `~/.pi/agent/auth.json` reports exactly the
///   `credentials_missing` skip quota-axi would. QuotaBar's three providers
///   are read directly; a user routing Codex through the separate Pi agent
///   ecosystem is out of scope for this port.
/// - Multi-account discovery (`discoverCodexAccounts`): quota-axi's own
///   multi-Pi-lane reconciliation. QuotaBar has always read one Codex account.
enum NQCodexReader {
    private static let endpoints = [
        URL(string: "https://chatgpt.com/backend-api/wham/usage")!,
        URL(string: "https://chatgpt.com/backend-api/codex/usage")!,
    ]
    private static let apiTimeout: TimeInterval = 15
    private static let cliTimeoutMs = 15_000
    private static let rpcTimeoutMs = 8_000
    private static let piCodexSource = "pi:openai-codex"

    struct Credentials {
        let accessToken: String
        let accountId: String?
    }

    enum RejectionKind: Error { case rejected, rateLimited(retryAfter: String?) }

    static func fetchQuota(readOnly: Bool, environment: [String: String] = ProcessInfo.processInfo.environment) async -> QuotaProvider {
        var attempts: [NQAttempt] = []
        var accountIds: [String] = []
        var nativeAccountId: String?
        var finalError = "Codex quota unavailable"
        var errorIsDefault = true

        let credentialState = readCredentialState(environment: environment)
        var oauthCandidates: [NQCredentialSelection.Candidate<Credentials>] = []
        switch credentialState {
        case let .available(credentials):
            if let id = credentials.accountId { nativeAccountId = id; accountIds.append(id) }
            oauthCandidates.append(.init(source: "oauth", localState: .valid, credentials: credentials))
        case let .expired(credentials):
            if let id = credentials.accountId { nativeAccountId = id; accountIds.append(id) }
            oauthCandidates.append(.init(source: "oauth", localState: .expired, credentials: credentials))
        case .missing:
            attempts.append(NQAttempt(source: "oauth", status: "skipped", error: "credentials_missing"))
            finalError = "Codex sign-in required"
            errorIsDefault = false
        case .invalid:
            attempts.append(NQAttempt(source: "oauth", status: "skipped", error: "credentials_invalid", credentialPresent: true))
            finalError = "Codex sign-in required"
            errorIsDefault = false
        }

        let oauthSelection = await NQCredentialSelection.select(candidates: oauthCandidates) { candidate in
            await attemptCodexCandidate(candidate.credentials)
        }
        appendSelectionAttempts(&attempts, results(of: oauthSelection))
        switch oauthSelection {
        case let .quota(_, quota, _):
            return codexSuccessReport(quota, source: "oauth", attempts: attempts, storedAccountId: nativeAccountId, environment: environment)
        case let .transient(error, retryAfter, _):
            return await codexFailureReport(error, retryAfter: retryAfter, attempts: attempts, accountIds: accountIds, environment: environment)
        case .allRejected:
            finalError = "Codex sign-in required"
            errorIsDefault = false
        default:
            break
        }

        // Rule (codex.js): the Pi broker is consulted as a secondary credential
        // source before falling back to the CLI. QuotaBar has no Pi lane, so
        // this only ever contributes a `credentials_missing` skip when
        // `~/.pi/agent/auth.json` (or `$PI_CODING_AGENT_DIR/auth.json`) is
        // absent, matching the common case exactly.
        if !piAuthFileExists(environment: environment) {
            attempts.append(NQAttempt(source: piCodexSource, status: "skipped", error: "credentials_missing"))
        } else if errorIsDefault {
            finalError = "Codex sign-in required"
            errorIsDefault = false
        }

        attempts.append(NQAttempt(source: "cli-rpc", status: "failed"))
        do {
            let quota = try await probeCodexCli(environment: environment)
            attempts[attempts.count - 1] = NQAttempt(source: "cli-rpc", status: "success")
            return codexSuccessReport(quota, source: "cli-rpc", attempts: attempts, storedAccountId: nativeAccountId, environment: environment)
        } catch let error as CliError {
            let message = error.message
            attempts[attempts.count - 1] = NQAttempt(source: "cli-rpc", status: "failed", error: message)
            if errorIsDefault || !error.isUnavailable {
                finalError = message
            }
        } catch {
            attempts[attempts.count - 1] = NQAttempt(source: "cli-rpc", status: "failed", error: "Codex quota unavailable")
        }
        return await codexFailureReport(finalError, retryAfter: nil, attempts: attempts, accountIds: accountIds, environment: environment)
    }

    private static func results<Success>(of outcome: NQCredentialSelection.SelectionOutcome<Success>) -> [NQCredentialSelection.CandidateResult] {
        switch outcome {
        case let .quota(_, _, results): return results
        case let .liveNoQuota(_, _, _, results): return results
        case let .transient(_, _, results): return results
        case let .allRejected(results): return results
        case let .noCandidates(results): return results
        }
    }

    private static func appendSelectionAttempts(_ attempts: inout [NQAttempt], _ results: [NQCredentialSelection.CandidateResult]) {
        for result in results where result.outcome != "not_tried" {
            if result.outcome == "quota" {
                attempts.append(NQAttempt(source: result.source, status: "success"))
            } else {
                attempts.append(NQAttempt(source: result.source, status: "failed", error: result.error))
            }
        }
    }

    private static func attemptCodexCandidate(_ credentials: Credentials) async -> NQCredentialSelection.AttemptOutcome<(plan: String?, account: ProviderAccount?, windows: [QuotaWindow], credits: ProviderCredits?, refreshedAt: String)> {
        do {
            let quota = try await fetchOauthUsage(credentials)
            return .quota(quota)
        } catch let RejectionKind.rateLimited(retryAfter) {
            return .transient(error: "Codex quota endpoint rate limited", retryAfter: retryAfter)
        } catch RejectionKind.rejected {
            return .rejected(error: "Codex sign-in required")
        } catch {
            return .transient(error: errorMessage(error), retryAfter: nil)
        }
    }

    // MARK: - Credential reading (no refresh)

    enum CredentialState {
        case available(Credentials)
        case expired(Credentials)
        case missing
        case invalid
    }

    private static func codexAuthFilePath(environment: [String: String]) -> String {
        if let home = environment["CODEX_HOME"], !home.isEmpty {
            return (home as NSString).appendingPathComponent("auth.json")
        }
        return (NSHomeDirectory() as NSString).appendingPathComponent(".codex/auth.json")
    }

    static func readCredentialState(environment: [String: String]) -> CredentialState {
        guard let data = FileManager.default.contents(atPath: codexAuthFilePath(environment: environment)) else {
            return .missing
        }
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = raw["tokens"] as? [String: Any],
              let accessToken = (tokens["access_token"] as? String) ?? (tokens["accessToken"] as? String),
              !accessToken.isEmpty
        else { return .invalid }

        let idToken = (tokens["id_token"] as? String) ?? (tokens["idToken"] as? String)
        let idPayload = idToken.flatMap(decodeJwtPayload)
        let accessPayload = decodeJwtPayload(accessToken)
        let decoded = idPayload ?? accessPayload
        let accountId = (tokens["account_id"] as? String) ?? (tokens["accountId"] as? String)
            ?? (decoded?["https://api.openai.com/auth/account_id"] as? String)
            ?? (decoded?["account_id"] as? String)
        let credentials = Credentials(accessToken: accessToken, accountId: accountId?.nqNilIfEmpty)

        if let exp = accessPayload?["exp"] as? Double, exp <= Date().timeIntervalSince1970 {
            return .expired(credentials)
        }
        if let exp = accessPayload?["exp"] as? Int, Double(exp) <= Date().timeIntervalSince1970 {
            return .expired(credentials)
        }
        return .available(credentials)
    }

    private static func decodeJwtPayload(_ token: String) -> [String: Any]? {
        let segments = token.split(separator: ".")
        guard segments.count >= 2 else { return nil }
        var base64 = String(segments[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json
    }

    private static func piAuthFileExists(environment: [String: String]) -> Bool {
        let base = environment["PI_CODING_AGENT_DIR"]?.nqNilIfEmpty
        let directory: String
        if let base {
            if base == "~" {
                directory = NSHomeDirectory()
            } else if base.hasPrefix("~/") {
                directory = (NSHomeDirectory() as NSString).appendingPathComponent(String(base.dropFirst(2)))
            } else {
                directory = base
            }
        } else {
            directory = (NSHomeDirectory() as NSString).appendingPathComponent(".pi/agent")
        }
        return FileManager.default.fileExists(atPath: (directory as NSString).appendingPathComponent("auth.json"))
    }

    // MARK: - HTTP

    private static func fetchOauthUsage(_ credentials: Credentials) async throws -> (plan: String?, account: ProviderAccount?, windows: [QuotaWindow], credits: ProviderCredits?, refreshedAt: String) {
        var rejected = false
        var lastError: Error?
        for endpoint in endpoints {
            var request = URLRequest(url: endpoint, timeoutInterval: apiTimeout)
            request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "authorization")
            request.setValue("application/json", forHTTPHeaderField: "accept")
            if let accountId = credentials.accountId {
                request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
            }
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    lastError = NSError(domain: "codex", code: -1); continue
                }
                if http.statusCode == 401 || http.statusCode == 403 { rejected = true; continue }
                if http.statusCode == 429 {
                    throw RejectionKind.rateLimited(retryAfter: NQTime.retryAfterToIso(http.value(forHTTPHeaderField: "retry-after")))
                }
                guard (200 ... 299).contains(http.statusCode) else {
                    lastError = NSError(domain: "codex", code: http.statusCode); continue
                }
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let quota = normalizeCodexUsage(json)
                else { lastError = NSError(domain: "codex", code: -2); continue }
                return quota
            } catch let rejection as RejectionKind {
                throw rejection
            } catch {
                lastError = error
            }
        }
        if let lastError { throw lastError }
        if rejected { throw RejectionKind.rejected }
        throw NSError(domain: "codex", code: -3)
    }

    private static func errorMessage(_ error: Error) -> String {
        if let urlError = error as? URLError, urlError.code == .timedOut {
            return "Codex quota request timed out"
        }
        return "Codex quota unavailable"
    }

    // MARK: - CLI fallback (read-only app-server probe; never rotates a token)

    struct CliError: Error {
        let message: String
        var isUnavailable = false
    }

    private static func probeCodexCli(environment: [String: String]) async throws -> (plan: String?, account: ProviderAccount?, windows: [QuotaWindow], credits: ProviderCredits?, refreshedAt: String) {
        guard let executable = resolveCodexBinary(environment: environment) else {
            throw CliError(message: "Codex quota unavailable", isUnavailable: true)
        }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let result = try runCodexAppServer(executable: executable)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func resolveCodexBinary(environment: [String: String]) -> String? {
        if let configured = environment["QUOTA_AXI_CODEX_BINARY"] {
            let trimmed = configured.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, trimmed.hasPrefix("/") else { return nil }
            return NQProcess.findCommandPath(trimmed, environment: environment)
        }
        return NQProcess.findCommandPath("codex", environment: environment)
    }

    private static func runCodexAppServer(executable: String) throws -> (plan: String?, account: ProviderAccount?, windows: [QuotaWindow], credits: ProviderCredits?, refreshedAt: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["-s", "read-only", "-a", "never", "app-server"]
        var environment = ProcessInfo.processInfo.environment
        environment["NO_COLOR"] = "1"
        environment["TERM"] = "dumb"
        process.environment = environment
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let buffer = NQLineBuffer()
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { buffer.append(data) }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData }

        defer {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            process.terminate()
            let deadline = DispatchTime.now() + .milliseconds(500)
            while process.isRunning && DispatchTime.now() < deadline { usleep(10_000) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }

        do {
            try process.run()
        } catch {
            throw CliError(message: "Codex quota unavailable", isUnavailable: true)
        }

        var nextId = 1
        func send(_ method: String, _ params: [String: Any] = [:]) throws -> Int {
            let id = nextId
            nextId += 1
            let payload: [String: Any] = ["id": id, "method": method, "params": params]
            guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
                throw CliError(message: "Codex quota unavailable")
            }
            stdinPipe.fileHandleForWriting.write(data)
            stdinPipe.fileHandleForWriting.write("\n".data(using: .utf8)!)
            return id
        }
        func awaitResponse(id: Int, timeoutMs: Int) throws -> Any? {
            let deadline = DispatchTime.now() + .milliseconds(timeoutMs)
            while DispatchTime.now() < deadline {
                while let line = buffer.popLine() {
                    guard let data = line.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let messageId = json["id"] as? Int, messageId == id
                    else { continue }
                    if let error = json["error"] { return error }
                    if let result = json["result"] { return result }
                    return json["params"] ?? NSNull()
                }
                if !process.isRunning { throw CliError(message: "Codex quota unavailable") }
                usleep(15_000)
            }
            throw CliError(message: "Codex quota unavailable")
        }

        let initId = try send("initialize", ["clientInfo": ["name": "QuotaBar", "version": "1"]])
        _ = try awaitResponse(id: initId, timeoutMs: cliTimeoutMs)

        let accountId = try send("account/read")
        let account = try? awaitResponse(id: accountId, timeoutMs: rpcTimeoutMs)
        if isSignedOutAccountRead(account) {
            throw CliError(message: "Codex quota unavailable")
        }

        let limitsId = try send("account/rateLimits/read")
        let limits = try awaitResponse(id: limitsId, timeoutMs: rpcTimeoutMs)

        let merged = mergeAccountAndLimits(account: account as? [String: Any], limits: limits as? [String: Any])
        guard let quota = normalizeCodexUsage(merged) else {
            throw CliError(message: "Codex quota unavailable")
        }
        return quota
    }

    private static func isSignedOutAccountRead(_ value: Any?) -> Bool {
        guard let data = value as? [String: Any], data.keys.contains("account") else { return false }
        if data["account"] is NSNull { return true }
        guard let account = data["account"] as? [String: Any], let type = account["type"] as? String else {
            return false
        }
        return type != "chatgpt"
    }

    private static func mergeAccountAndLimits(account: [String: Any]?, limits: [String: Any]?) -> [String: Any] {
        let accountData = account ?? [:]
        let accountRecord = (accountData["account"] as? [String: Any]) ?? accountData
        var merged = limits ?? [:]
        merged["email"] = accountRecord["email"] ?? merged["email"]
        merged["account_id"] = accountRecord["account_id"] ?? accountRecord["accountId"] ?? merged["account_id"]
        merged["plan_type"] = accountRecord["plan_type"] ?? accountRecord["planType"] ?? merged["plan_type"]
        return merged
    }

    // MARK: - Normalization

    static func normalizeCodexUsage(_ raw: [String: Any]) -> (plan: String?, account: ProviderAccount?, windows: [QuotaWindow], credits: ProviderCredits?, refreshedAt: String)? {
        let rateLimit = (raw["rate_limit"] as? [String: Any]) ?? (raw["rateLimits"] as? [String: Any])
            ?? (raw["rate_limits"] as? [String: Any]) ?? raw
        var windows = windowPair(
            from: rateLimit, primaryId: "five_hour", primaryLabel: "session", primaryKind: "session",
            secondaryId: "weekly", secondaryLabel: "week", secondaryKind: "weekly")
        windows += windowPair(
            from: raw["code_review_rate_limit"] as? [String: Any], primaryId: "code_review_five_hour",
            primaryLabel: "code review session", primaryKind: "session", secondaryId: "code_review_weekly",
            secondaryLabel: "code review week", secondaryKind: "weekly")
        windows += collectNamedRateLimitWindows(raw)
        windows = deduplicateWindowIds(windows)
        guard !windows.isEmpty else { return nil }

        let account = ProviderAccount(
            accountId: (raw["account_id"] as? String)?.nqNilIfEmpty ?? (raw["accountId"] as? String)?.nqNilIfEmpty,
            email: (raw["email"] as? String)?.nqNilIfEmpty, organization: nil, identityStatus: nil)
        let plan = (raw["plan_type"] as? String)?.nqNilIfEmpty ?? (raw["planType"] as? String)?.nqNilIfEmpty
        let credits = normalizeCredits((raw["credits"] as? [String: Any]) ?? (rateLimit["credits"] as? [String: Any]))
        return (plan, account, windows, credits, NQTime.nowIso())
    }

    private static func windowPair(
        from container: [String: Any]?, primaryId: String, primaryLabel: String, primaryKind: String,
        secondaryId: String, secondaryLabel: String, secondaryKind: String
    ) -> [QuotaWindow] {
        guard let container else { return [] }
        let unfamiliarPrefix = primaryId == "five_hour" ? "window" : "code_review_window"
        let primary = (container["primary_window"] as? [String: Any]) ?? (container["primary"] as? [String: Any])
        let secondary = (container["secondary_window"] as? [String: Any]) ?? (container["secondary"] as? [String: Any])
        var windows: [QuotaWindow] = []
        if let window = normalizeWindow(primary, fallbackId: primaryId, fallbackLabel: primaryLabel, fallbackKind: primaryKind, unfamiliarPrefix: unfamiliarPrefix, unfamiliarLabelSuffix: nil) {
            windows.append(window)
        }
        if let window = normalizeWindow(secondary, fallbackId: secondaryId, fallbackLabel: secondaryLabel, fallbackKind: secondaryKind, unfamiliarPrefix: unfamiliarPrefix, unfamiliarLabelSuffix: nil) {
            windows.append(window)
        }
        return windows
    }

    private static func collectNamedRateLimitWindows(_ raw: [String: Any]) -> [QuotaWindow] {
        var windows: [QuotaWindow] = []
        for entry in (raw["additional_rate_limits"] as? [Any] ?? []) {
            guard let item = entry as? [String: Any] else { continue }
            let id = (item["metered_feature"] as? String)?.nqNilIfEmpty ?? (item["limit_name"] as? String)?.nqNilIfEmpty
            let label = (item["limit_name"] as? String)?.nqNilIfEmpty ?? id
            guard let id, let label, let container = item["rate_limit"] as? [String: Any] else { continue }
            windows += namedLimitWindows(id: id, label: label, container: container)
        }
        if let byLimitId = raw["rateLimitsByLimitId"] as? [String: Any] {
            for (limitId, value) in byLimitId {
                guard let item = value as? [String: Any],
                      let label = (item["limitName"] as? String)?.nqNilIfEmpty ?? (item["limit_name"] as? String)?.nqNilIfEmpty
                else { continue }
                windows += namedLimitWindows(id: limitId, label: label, container: item)
            }
        }
        return windows
    }

    private static func namedLimitWindows(id: String, label: String, container: [String: Any]) -> [QuotaWindow] {
        let primary = (container["primary_window"] as? [String: Any]) ?? (container["primary"] as? [String: Any])
        let secondary = (container["secondary_window"] as? [String: Any]) ?? (container["secondary"] as? [String: Any])
        var windows: [QuotaWindow] = []
        if let window = normalizeWindow(
            primary, fallbackId: "model:\(id):5h", fallbackLabel: "\(label) session", fallbackKind: "model",
            unfamiliarPrefix: "model:\(id):window", unfamiliarLabelSuffix: label)
        {
            windows.append(window)
        }
        if let window = normalizeWindow(
            secondary, fallbackId: "model:\(id):7d", fallbackLabel: "\(label) week", fallbackKind: "model",
            unfamiliarPrefix: "model:\(id):window", unfamiliarLabelSuffix: label)
        {
            windows.append(window)
        }
        return windows
    }

    private static func normalizeWindow(
        _ raw: [String: Any]?, fallbackId: String, fallbackLabel: String, fallbackKind: String,
        unfamiliarPrefix: String, unfamiliarLabelSuffix: String?
    ) -> QuotaWindow? {
        guard let raw else { return nil }
        let used = (raw["used_percent"] as? Double) ?? (raw["usedPercent"] as? Double)
        guard let used else { return nil }
        let windowSeconds = (raw["limit_window_seconds"] as? Double)
            ?? (raw["windowDurationMins"] as? Double).map { $0 * 60 }
        let resetFromSeconds = (raw["reset_after_seconds"] as? Double)
            .map { NQTime.parseEpochOrIso(Date().timeIntervalSince1970 + $0) }
        let resetsAt = NQTime.parseEpochOrIso(raw["reset_at"] as? String)
            ?? NQTime.parseEpochOrIso(raw["resetsAt"] as? String)
            ?? (resetFromSeconds ?? nil)

        var id = fallbackId
        var label = fallbackLabel
        var kind = fallbackKind
        if let windowSeconds, windowSeconds != 18_000, windowSeconds != 604_800 {
            let duration = readableWindowDuration(windowSeconds)
            id = "\(unfamiliarPrefix):\(duration)"
            label = unfamiliarLabelSuffix.map { "\($0) \(duration) window" } ?? "\(duration) window"
            kind = unfamiliarPrefix.hasPrefix("model:") ? "model" : "unknown"
        }
        return NQCommon.window(
            id: id, label: label, kind: kind, percentUsed: NQTime.clampPercent(used), resetsAt: resetsAt,
            windowSeconds: windowSeconds)
    }

    private static func readableWindowDuration(_ windowSeconds: Double) -> String {
        let hours = windowSeconds / 3600
        if hours == hours.rounded() { return "\(Int(hours))h" }
        return "\((hours * 100).rounded() / 100)h"
    }

    private static func deduplicateWindowIds(_ windows: [QuotaWindow]) -> [QuotaWindow] {
        var counts: [String: Int] = [:]
        return windows.map { window in
            let id = window.id ?? "window"
            let count = (counts[id] ?? 0) + 1
            counts[id] = count
            guard count > 1 else { return window }
            return QuotaWindow(
                id: "\(id)_\(count)", label: window.label, kind: window.kind, percentUsed: window.percentUsed,
                percentRemaining: window.percentRemaining, spentUsd: window.spentUsd, limitUsd: window.limitUsd,
                resetsAt: window.resetsAt, windowSeconds: window.windowSeconds)
        }
    }

    private static func normalizeCredits(_ raw: [String: Any]?) -> ProviderCredits? {
        guard let raw else { return nil }
        let balance = raw["balance"] as? Double
        let unlimited = raw["unlimited"] as? Bool
        guard balance != nil || unlimited != nil else { return nil }
        return ProviderCredits(remaining: balance, unlimited: unlimited, unit: "credits")
    }

    // MARK: - Report assembly

    private static func codexSuccessReport(
        _ quota: (plan: String?, account: ProviderAccount?, windows: [QuotaWindow], credits: ProviderCredits?, refreshedAt: String),
        source: String, attempts: [NQAttempt], storedAccountId: String?, environment: [String: String]
    ) -> QuotaProvider {
        var credentialContext: [String: String] = [:]
        if let storedAccountId, let contextId = NQCache.codexAccountContextId(storedAccountId) {
            credentialContext["codex"] = contextId
        }
        let draft = NQCommon.successDraft(
            provider: "codex", label: "Codex", source: source, plan: quota.plan, account: quota.account,
            windows: quota.windows, credits: quota.credits, refreshedAt: quota.refreshedAt, attempts: attempts)
        NQCache.writeCachedProviders([draft], credentialContext: credentialContext, environment: environment)
        return NQCommon.finalize(draft, generatedAt: NQTime.nowIso())
    }

    private static func codexFailureReport(
        _ error: String, retryAfter: String?, attempts: [NQAttempt], accountIds: [String], environment: [String: String]
    ) async -> QuotaProvider {
        if let cached = NQCache.readCachedCodexProvider(accountIds: accountIds, environment: environment) {
            let draft = NQCommon.staleFromCache(
                cached, error: error, sourcesTried: NQCommon.sourceNames(attempts), attempts: attempts)
            return NQCommon.finalize(draft, generatedAt: NQTime.nowIso())
        }
        let draft = NQCommon.failedDraft(
            provider: "codex", label: "Codex", status: retryAfter != nil ? "rate_limited" : NQCommon.statusFromError(error),
            error: error, retryAfter: retryAfter, attempts: attempts)
        return NQCommon.finalize(draft, generatedAt: NQTime.nowIso())
    }
}

/// Thread-safe newline-delimited buffer fed by a `FileHandle.readabilityHandler`.
final class NQLineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = Data()
    private var lines: [String] = []

    func append(_ data: Data) {
        lock.withLock {
            pending.append(data)
            while let newline = pending.firstIndex(of: 0x0a) {
                let lineData = pending[pending.startIndex..<newline]
                if let line = String(data: lineData, encoding: .utf8), !line.trimmingCharacters(in: .whitespaces).isEmpty {
                    lines.append(line)
                }
                pending.removeSubrange(pending.startIndex...newline)
            }
        }
    }

    func popLine() -> String? {
        lock.withLock {
            guard !lines.isEmpty else { return nil }
            return lines.removeFirst()
        }
    }
}

private extension String {
    var nqNilIfEmpty: String? { isEmpty ? nil : self }
}
