import Foundation

/// Ports `providers/claude.js` from quota-axi 0.1.51. Every numbered rule below
/// mirrors a specific guard in that file so a future upgrade can diff against
/// it function by function; see `docs/native-quota-porting.md` for the
/// file-to-file map.
///
/// Not ported, deliberately:
/// - `--allow-claude-inference` / `fetchClaudeNativeQuota` (claude-native-quota.js):
///   QuotaBar never passes that flag, so the branch is unreachable. The
///   `envProfileScopeDenied` classification it depends on is still ported
///   faithfully, just without the inference fallback at the end of it.
/// - `--profile-only`: QuotaBar never sets `CLAUDE_CONFIG_DIR` in profile-only
///   mode, so `fetchProfileOnlyQuota` never runs.
enum NQClaudeReader {
    private static let apiURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let profileURL = URL(string: "https://api.anthropic.com/api/oauth/profile")!
    private static let oauthBeta = "oauth-2025-04-20"
    private static let userAgent = "claude-code/2.1.202"
    private static let apiTimeout: TimeInterval = 15
    private static let keychainPromptTimeout: TimeInterval = 60
    private static let keychainPresenceTimeout: TimeInterval = 5
    private static let defaultKeychainAccount = "claude-code-user"
    private static let fiveHoursMs: Double = 5 * 60 * 60 * 1000
    private static let sevenDaysMs: Double = 7 * 24 * 60 * 60 * 1000
    private static let fiveHoursSeconds: Double = 18_000
    private static let sevenDaysSeconds: Double = 604_800

    /// `CLAUDE_CLI_REFRESH_DELEGATE`: `claude doctor` is the smallest observed
    /// non-interactive command that makes Claude Code renew its own expired
    /// OAuth session. It starts no session and spends no quota; only Anthropic
    /// definitively rejecting the refresh token clears it. See the long
    /// comment on this constant in claude.js for the full rationale.
    private static let refreshDelegate = NQDelegatedRefresh.Delegate(
        source: "claude-cli-refresh", command: "claude", args: ["doctor"], waitBudgetMs: 45_000)

    struct Failure {
        var code: String
        var status: String
        var definitiveAuth = false
        var staleEligible = false
        var authStatus: String?
        var envProfileScopeDenied = false
    }

    struct AttemptPass {
        var report: QuotaProvider?
        var failure: Failure?
        var refreshableExpiredRejected = false
        var keychainWithheld = false
        var definitiveFailureIsEnvOnly = false
    }

    static func fetchQuota(readOnly: Bool, environment: [String: String] = ProcessInfo.processInfo.environment) async -> QuotaProvider {
        let credentialContextId = NQClaudeProfile.credentialContextId(environment: environment)
        var attempts: [NQAttempt] = []
        var pass = await attemptClaudeQuota(readOnly: readOnly, environment: environment, attempts: &attempts)
        if let report = pass.report { return report }

        // Rule: delegate only on soft expiry of a store this reader can read
        // back, never when Keychain access was withheld (claude.js
        // `shouldDelegateClaudeRefresh`). `readOnly` (`--no-credential-refresh`)
        // disables delegation entirely, exactly like `options.refreshCredentials`.
        if !readOnly, pass.refreshableExpiredRejected, !pass.keychainWithheld {
            if let blocker = await NQClaudeProcessGuard.liveRefreshBlocker() {
                attempts.append(NQAttempt(source: refreshDelegate.source, status: "skipped", error: blocker))
            } else {
                let outcome = await NQDelegatedRefresh.run(refreshDelegate)
                attempts.append(NQDelegatedRefresh.attempt(refreshDelegate, outcome: outcome))
                if case .ran = outcome {
                    let retry = await attemptClaudeQuota(readOnly: readOnly, environment: environment, attempts: &attempts)
                    if let report = retry.report { return report }
                    pass = retry
                } else if case .unconfirmed = outcome {
                    // Rule: the vendor outran the wait; quota-axi never turns that
                    // into a sign-out verdict (`unconfirmedRefreshFailure`).
                    pass.failure = Failure(
                        code: "claude_refresh_unconfirmed", status: "unavailable", staleEligible: true)
                }
            }
        }

        let failure = pass.failure ?? Failure(code: "Claude quota unavailable", status: "error", staleEligible: true)
        // Rule: the env token names one specific account; its own definitive
        // rejection must never fall back to a stored account's stale cache.
        let envSelected = NQClaudeProfile.envOauthToken(environment: environment) != nil
        return await failureReport(
            failure, attempts: attempts, credentialContextId: credentialContextId, envSelected: envSelected,
            definitiveFailureIsEnvOnly: pass.definitiveFailureIsEnvOnly, environment: environment)
    }

    // MARK: - Credential discovery

    enum CredentialSource: Equatable { case env, oauthFile, keychain }

    struct Credential {
        let source: CredentialSource
        let accessToken: String
        let plan: String?
        let expiresAtMs: Double?
    }

    enum CredentialState {
        case available(Credential)
        case expired(Credential, refreshable: Bool)
        case missing(source: String)
        case invalid(source: String, credentialPresent: Bool)
        /// Keychain-only: presence known but the value was not read (no marker,
        /// and QuotaBar never sets `--allow-keychain-prompt`).
        case skipped(source: String, error: String, credentialPresent: Bool, degraded: Bool?)
    }

    private static func attemptClaudeQuota(
        readOnly: Bool, environment: [String: String], attempts: inout [NQAttempt]
    ) async -> AttemptPass {
        let states = await readCredentialStates(environment: environment)

        for state in states {
            switch state {
            case .available, .expired: continue
            case let .missing(source):
                attempts.append(NQAttempt(source: source, status: "skipped", error: "credentials_missing"))
            case let .invalid(source, present):
                attempts.append(NQAttempt(
                    source: source, status: "skipped", error: "credentials_invalid",
                    credentialPresent: present ? true : nil))
            case let .skipped(source, error, present, degraded):
                attempts.append(NQAttempt(
                    source: source, status: "skipped", error: error,
                    credentialPresent: present ? true : nil, degraded: degraded))
            }
        }

        var candidates: [(state: CredentialState, credential: Credential, refreshable: Bool)] = []
        for state in states {
            switch state {
            case let .available(credential): candidates.append((state, credential, false))
            case let .expired(credential, refreshable): candidates.append((state, credential, refreshable))
            default: continue
            }
        }
        // Rule: env resolves before any stored credential (Claude Code's own
        // precedence); on darwin, Keychain is preferred among stored sources;
        // otherwise newest `expiresAt` wins.
        candidates.sort { lhs, rhs in
            if lhs.credential.source == .env, rhs.credential.source != .env { return true }
            if rhs.credential.source == .env, lhs.credential.source != .env { return false }
            if lhs.credential.source == .keychain, rhs.credential.source != .keychain { return true }
            if rhs.credential.source == .keychain, lhs.credential.source != .keychain { return false }
            return (lhs.credential.expiresAtMs ?? 0) > (rhs.credential.expiresAtMs ?? 0)
        }

        var definitiveFailure: Failure?
        var definitiveFailureIsEnv = false
        var transientFailure: Failure?
        var transientFailureIsEnv = false
        var confirmedExpiryFailure: Failure?

        if !candidates.isEmpty {
            candidateLoop: for (state, credential, refreshable) in candidates {
                attempts.append(NQAttempt(source: sourceName(credential.source), status: "failed"))
                do {
                    let quota = try await fetchOauthUsage(credential, environment: environment)
                    attempts[attempts.count - 1] = NQAttempt(source: sourceName(credential.source), status: "success")
                    let identity = await fetchOauthProfile(credential, environment: environment)
                    attempts.append(oauthProfileAttempt(identity.error))
                    let draft = NQCommon.successDraft(
                        provider: "claude", label: "Claude", source: "oauth", plan: quota.plan,
                        account: identity.account, windows: quota.windows, refreshedAt: quota.refreshedAt,
                        attempts: attempts)
                    NQCache.writeCachedProviders(
                        [draft], credentialContext: ["claude": NQClaudeProfile.credentialContextId(environment: environment)])
                    return AttemptPass(report: NQCommon.finalize(draft, generatedAt: NQTime.nowIso()))
                } catch let error as Failure {
                    var failure = error
                    let isExpiredState: Bool = { if case .expired = state { return true }; return false }()
                    let softRefreshable = failure.definitiveAuth && isExpiredState && refreshable
                    if softRefreshable {
                        failure = Failure(
                            code: "Claude access token expired", status: "unavailable", staleEligible: true,
                            authStatus: "expired_refreshable")
                    }
                    attempts[attempts.count - 1] = NQAttempt(
                        source: sourceName(credential.source), status: "failed", error: failure.code)

                    if credential.source == .env, failure.envProfileScopeDenied {
                        // Rule: `allowClaudeInference` is never set by QuotaBar, so
                        // the native-inference fallback in claude.js is dead code
                        // here; the env token's own failure simply stands.
                        transientFailure = failure
                        transientFailureIsEnv = true
                        break candidateLoop
                    }

                    if softRefreshable || failure.definitiveAuth {
                        if definitiveFailure == nil {
                            definitiveFailure = failure
                            definitiveFailureIsEnv = credential.source == .env
                        }
                        if credential.source == .env { break candidateLoop }
                    } else {
                        var expiryConfirmed = false
                        if isExpiredState, failure.status == "rate_limited" {
                            expiryConfirmed = await confirmClaudeStoredExpiry(credential, environment: environment, attempts: &attempts)
                        }
                        if expiryConfirmed {
                            if confirmedExpiryFailure == nil, definitiveFailure == nil {
                                confirmedExpiryFailure = Failure(
                                    code: "Claude credential expired", status: "unavailable", staleEligible: true,
                                    authStatus: refreshable ? "expired_refreshable" : nil)
                                transientFailure = confirmedExpiryFailure
                                transientFailureIsEnv = credential.source == .env
                            }
                        } else {
                            transientFailure = failure
                            transientFailureIsEnv = credential.source == .env
                        }
                        if !expiryConfirmed, credential.source != .env { break candidateLoop }
                    }
                } catch {
                    let failure = Failure(code: "Claude quota unavailable", status: "error", staleEligible: true)
                    attempts[attempts.count - 1] = NQAttempt(
                        source: sourceName(credential.source), status: "failed", error: failure.code)
                    transientFailure = failure
                    transientFailureIsEnv = credential.source == .env
                    if credential.source != .env { break candidateLoop }
                }
            }
        } else {
            if let skippedState = states.first(where: { if case .skipped = $0 { return true }; return false }),
               case let .skipped(_, error, _, _) = skippedState
            {
                transientFailure = Failure(code: error, status: "error", staleEligible: true)
            } else {
                let invalid = states.contains { if case .invalid = $0 { return true }; return false }
                definitiveFailure = Failure(
                    code: invalid ? "credentials_invalid" : "credentials_missing", status: "auth_required",
                    definitiveAuth: true)
            }
        }

        let keychainFailure = states.first { state in
            if case let .skipped(source, error, _, _) = state, source == "keychain" {
                return [
                    "keychain_access_denied", "keychain_prompt_required", "keychain_prompt_timeout",
                    "keychain_presence_check_failed", "keychain_unreachable",
                ].contains(error)
            }
            return false
        }

        var failure = confirmedExpiryFailure
            ?? (transientFailureIsEnv ? definitiveFailure : nil)
            ?? transientFailure
            ?? definitiveFailure
            ?? Failure(code: "Claude quota unavailable", status: "error", staleEligible: true)

        if keychainFailure != nil,
           (failure.definitiveAuth || failure.authStatus == "expired_refreshable"),
           !definitiveFailureIsEnv,
           case let .skipped(_, error, _, _)? = keychainFailure
        {
            failure = Failure(code: error, status: NQCommon.statusFromError(error), staleEligible: true)
        }

        return AttemptPass(
            report: nil, failure: failure,
            refreshableExpiredRejected: isSame(failure, definitiveFailure) && failure.authStatus == "expired_refreshable",
            keychainWithheld: states.contains { if case .skipped(let source, _, _, _) = $0 { return source == "keychain" }; return false },
            definitiveFailureIsEnvOnly: isSame(failure, definitiveFailure) && definitiveFailureIsEnv)
    }

    private static func isSame(_ a: Failure, _ b: Failure?) -> Bool {
        guard let b else { return false }
        return a.code == b.code && a.status == b.status && a.authStatus == b.authStatus
    }

    private static func sourceName(_ source: CredentialSource) -> String {
        switch source {
        case .env: return "env"
        case .oauthFile: return "oauth-file"
        case .keychain: return "keychain"
        }
    }

    private static func readCredentialStates(environment: [String: String]) async -> [CredentialState] {
        var states: [CredentialState] = []

        if let token = NQClaudeProfile.envOauthToken(environment: environment) {
            states.append(.available(Credential(source: .env, accessToken: token, plan: nil, expiresAtMs: nil)))
        } else if let raw = environment[NQClaudeProfile.oauthTokenEnvKey], !raw.trimmingCharacters(in: .whitespaces).isEmpty {
            states.append(.invalid(source: "env", credentialPresent: true))
        }

        let locations = NQClaudeProfile.locations(environment: environment)
        let credentialFile = (locations.secureStorageSelected)
            ? nil
            : ((locations.configDir as NSString).appendingPathComponent(".credentials.json"))
        if let credentialFile {
            states.append(extractCredentialState(path: credentialFile, source: .oauthFile))
        }

        let account = keychainAccount(environment: environment)
        switch await NQClaudeKeychainLookup.find(account: account, locations: locations, timeout: keychainPresenceTimeout) {
        case .missing:
            states.append(.missing(source: "keychain"))
            return states
        case .unknown:
            states.append(await readSkippedKeychain(account: account, locations: locations, keychainPath: nil))
        case let .present(item):
            let markerPath = NQPaths.claudeKeychainAccessMarkerPath(account: account, service: item.service, environment: environment)
            if NQPaths.hasKeychainAccessMarker(markerPath) {
                states.append(await readKeychainCredentialState(
                    account: account, service: item.service, keychainPath: item.keychainPath, markerPath: markerPath))
            } else {
                states.append(await readSkippedKeychain(account: account, locations: locations, keychainPath: item.keychainPath))
            }
        }
        return states
    }

    private static func readSkippedKeychain(account: String, locations: NQClaudeProfile.Locations, keychainPath: String?) async -> CredentialState {
        if keychainPath != nil {
            return .skipped(source: "keychain", error: "keychain_prompt_required", credentialPresent: true, degraded: nil)
        }
        switch await NQSecurity.findGenericPasswordPresence(account: account, service: locations.keychainService, timeout: keychainPresenceTimeout) {
        case .present:
            return .skipped(source: "keychain", error: "keychain_prompt_required", credentialPresent: true, degraded: nil)
        case .missing:
            return .missing(source: "keychain")
        case .unknown:
            return .skipped(source: "keychain", error: "keychain_presence_check_failed", credentialPresent: false, degraded: true)
        }
    }

    private static func readKeychainCredentialState(account: String, service: String, keychainPath: String, markerPath: String) async -> CredentialState {
        do {
            let blob = try await NQSecurity.findGenericPasswordValue(
                account: account, service: service, keychainPath: keychainPath, timeout: keychainPromptTimeout)
            NQPaths.writeKeychainAccessMarkerBestEffort(markerPath)
            return extractCredentialState(jsonText: blob, source: .keychain)
        } catch let error as NQProcess.ExecError {
            if error.killed {
                return .skipped(source: "keychain", error: "keychain_prompt_timeout", credentialPresent: true, degraded: nil)
            }
            if NQSecurity.isItemNotFound(error) {
                return .skipped(source: "keychain", error: "keychain_unreachable", credentialPresent: true, degraded: nil)
            }
            return .skipped(source: "keychain", error: "keychain_access_denied", credentialPresent: true, degraded: nil)
        } catch {
            return .skipped(source: "keychain", error: "keychain_access_denied", credentialPresent: true, degraded: nil)
        }
    }

    private static func keychainAccount(environment: [String: String]) -> String {
        let candidate = environment["USER"] ?? NSUserName()
        let safe = candidate.range(of: "^[a-zA-Z0-9._-]+$", options: .regularExpression) != nil
        return safe ? candidate : defaultKeychainAccount
    }

    private static func extractCredentialState(path: String, source: CredentialSource) -> CredentialState {
        guard let data = FileManager.default.contents(atPath: path) else {
            return .missing(source: sourceName(source))
        }
        guard let text = String(data: data, encoding: .utf8) else {
            return .invalid(source: sourceName(source), credentialPresent: false)
        }
        return extractCredentialState(jsonText: text, source: source)
    }

    static func extractCredentialState(jsonText: String, source: CredentialSource) -> CredentialState {
        guard let data = jsonText.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return .invalid(source: sourceName(source), credentialPresent: false) }
        let oauth = (raw["claudeAiOauth"] as? [String: Any]) ?? raw
        guard let accessToken = (oauth["accessToken"] as? String) ?? (oauth["access_token"] as? String),
              !accessToken.isEmpty
        else { return .invalid(source: sourceName(source), credentialPresent: false) }
        let expiresAtMs = expiresAtMillis(oauth["expiresAt"])
        let plan = (oauth["subscriptionType"] as? String) ?? (raw["subscriptionType"] as? String)
        let credential = Credential(source: source, accessToken: accessToken, plan: plan, expiresAtMs: expiresAtMs)
        if let expiresAtMs, expiresAtMs <= Date().timeIntervalSince1970 * 1000 {
            let refreshable = oauth["refreshToken"] != nil || oauth["refresh_token"] != nil
            return .expired(credential, refreshable: refreshable)
        }
        return .available(credential)
    }

    private static func expiresAtMillis(_ value: Any?) -> Double? {
        if let number = value as? Double { return number }
        if let number = value as? Int { return Double(number) }
        if let string = value as? String {
            if let number = Double(string) { return number }
            return NQTime.parseEpochOrIso(string).flatMap { ISO8601DateFormatter.nqFractional.date(from: $0)?.timeIntervalSince1970.rounded() }
                .map { $0 * 1000 }
        }
        return nil
    }

    // MARK: - HTTP

    private struct OauthUsage {
        var plan: String?
        var windows: [QuotaWindow]
        var refreshedAt: String
    }

    private struct IdentityResult {
        var account: ProviderAccount?
        var error: String?
    }

    private static func fetchOauthUsage(_ credential: Credential, environment: [String: String]) async throws -> (plan: String?, windows: [QuotaWindow], refreshedAt: String) {
        var request = URLRequest(url: apiURL, timeoutInterval: apiTimeout)
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "authorization")
        request.setValue(oauthBeta, forHTTPHeaderField: "anthropic-beta")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        try await rejectUnusableUsageResponse(response, data: data, envSelected: credential.source == .env)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let quota = normalizeClaudeApiUsage(json, plan: credential.plan)
        else { throw Failure(code: "Claude quota unavailable", status: "error", staleEligible: true) }
        return quota
    }

    private static func fetchOauthProfile(_ credential: Credential, environment: [String: String]) async -> IdentityResult {
        var request = URLRequest(url: profileURL, timeoutInterval: apiTimeout)
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "authorization")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("application/json", forHTTPHeaderField: "accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                return IdentityResult(account: ["identityStatus": "unverified"].asAccount, error: "identity_profile_http_\(code)")
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let account = normalizeClaudeProfile(json)
            else {
                return IdentityResult(account: ["identityStatus": "unverified"].asAccount, error: "identity_profile_unrecognized")
            }
            return IdentityResult(account: account, error: nil)
        } catch {
            return IdentityResult(account: ["identityStatus": "unverified"].asAccount, error: "identity_profile_unavailable")
        }
    }

    private static func confirmClaudeStoredExpiry(_ credential: Credential, environment: [String: String], attempts: inout [NQAttempt]) async -> Bool {
        let identity = await fetchOauthProfile(credential, environment: environment)
        attempts.append(oauthProfileAttempt(identity.error))
        return identity.error == "identity_profile_http_401"
    }

    private static func oauthProfileAttempt(_ error: String?) -> NQAttempt {
        if let error { return NQAttempt(source: "oauth-profile", status: "failed", error: error, degraded: false) }
        return NQAttempt(source: "oauth-profile", status: "success")
    }

    /// Mirrors `rejectUnusableUsageResponse`. 401 is the definitive auth
    /// verdict; 403 can be a WAF/network-policy denial and is not, except for
    /// the one named env-token scope-denial shape.
    private static func rejectUnusableUsageResponse(_ response: URLResponse, data: Data, envSelected: Bool) async throws {
        guard let http = response as? HTTPURLResponse else {
            throw Failure(code: "Claude quota unavailable", status: "error", staleEligible: true)
        }
        if http.statusCode == 401 {
            throw Failure(code: "Claude sign-in required", status: "auth_required", definitiveAuth: true)
        }
        if http.statusCode == 429 {
            throw Failure(code: "Claude quota endpoint rate limited", status: "rate_limited", staleEligible: true)
        }
        if http.statusCode == 403, envSelected, isClaudeEnvProfileScopeDenial(data) {
            throw Failure(
                code: "claude_env_usage_scope_unavailable", status: "unavailable", envProfileScopeDenied: true)
        }
        if !(200 ... 299).contains(http.statusCode) {
            throw Failure(code: "Claude quota unavailable (\(http.statusCode))", status: "error", staleEligible: true)
        }
    }

    /// Mirrors `isClaudeEnvProfileScopeDenial`: recognizes only the exact
    /// `user:profile` scope-denial shape; anything else is simply not that.
    private static func isClaudeEnvProfileScopeDenial(_ data: Data) -> Bool {
        guard data.count <= 16 * 1024,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let errorObject = json["error"] as? [String: Any],
              let type = errorObject["type"] as? String, type == "permission_error",
              let message = errorObject["message"] as? String
        else { return false }
        let trimmed = message.trimmingCharacters(in: .whitespaces)
        return trimmed.range(
            of: "^OAuth token does not meet scope requirement user:profile\\.?$",
            options: [.regularExpression, .caseInsensitive]) != nil
    }

    // MARK: - Normalization

    static func normalizeClaudeApiUsage(_ raw: [String: Any], plan: String?) -> (plan: String?, windows: [QuotaWindow], refreshedAt: String)? {
        let scoped = normalizeScopedLimits(raw["limits"] as? [Any])
        var windows = scoped
        if windows.isEmpty {
            windows = [
                normalizeWindow(raw["five_hour"] as? [String: Any], id: "five_hour", label: "session", kind: "session"),
                normalizeWindow(raw["seven_day"] as? [String: Any], id: "seven_day", label: "week", kind: "weekly"),
                normalizeWindow(raw["seven_day_opus"] as? [String: Any], id: "seven_day_opus", label: "opus week", kind: "model"),
            ].compactMap { $0 }
        }
        if let extraUsage = normalizeExtraUsage(raw["extra_usage"] as? [String: Any]) {
            windows.append(extraUsage)
        }
        guard !windows.isEmpty else { return nil }
        return (plan, windows, NQTime.nowIso())
    }

    private static func normalizeScopedLimits(_ raw: [Any]?) -> [QuotaWindow] {
        guard let raw else { return [] }
        return raw.compactMap { $0 as? [String: Any] }.compactMap(normalizeScopedLimitEntry)
    }

    private static func normalizeScopedLimitEntry(_ entry: [String: Any]) -> QuotaWindow? {
        guard let percent = entry["percent"] as? Double else { return nil }
        let resetsAt = (entry["resets_at"] as? String)?.nqNilIfEmpty
        let scope = entry["scope"] as? [String: Any]
        let model = scope?["model"] as? [String: Any]
        if let modelName = (model?["display_name"] as? String)?.nqNilIfEmpty {
            let modelKey = (model?["id"] as? String)?.nqNilIfEmpty ?? slugify(modelName)
            return NQCommon.window(
                id: "model:\(modelKey)", label: "\(modelName) week", kind: "model",
                percentUsed: NQTime.clampPercent(percent), resetsAt: resetsAt, windowSeconds: sevenDaysSeconds)
        }
        if let group = entry["group"] as? String {
            if group == "session" {
                return NQCommon.window(
                    id: "five_hour", label: "session", kind: "session", percentUsed: NQTime.clampPercent(percent),
                    resetsAt: resetsAt, windowSeconds: fiveHoursSeconds)
            }
            if group == "weekly" {
                return NQCommon.window(
                    id: "seven_day", label: "week", kind: "weekly", percentUsed: NQTime.clampPercent(percent),
                    resetsAt: resetsAt, windowSeconds: sevenDaysSeconds)
            }
        }
        let kind = (entry["kind"] as? String)?.nqNilIfEmpty
        return NQCommon.window(
            id: kind ?? "limit", label: kind ?? "limit", kind: "unknown", percentUsed: NQTime.clampPercent(percent),
            resetsAt: resetsAt)
    }

    private static func slugify(_ value: String) -> String {
        let lower = value.trimmingCharacters(in: .whitespaces).lowercased()
        let slug = lower.replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
        return slug.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    private static func normalizeWindow(_ raw: [String: Any]?, id: String, label: String, kind: String) -> QuotaWindow? {
        guard let raw, let used = raw["utilization"] as? Double else { return nil }
        let windowSeconds = trustedWindowSeconds(id: id, kind: kind)
        let resetsAt = (raw["resets_at"] as? String)?.nqNilIfEmpty ?? (raw["reset_at"] as? String)?.nqNilIfEmpty
        return NQCommon.window(
            id: id, label: label, kind: kind, percentUsed: NQTime.clampPercent(used), resetsAt: resetsAt,
            windowSeconds: windowSeconds)
    }

    private static func trustedWindowSeconds(id: String, kind: String) -> Double? {
        if id == "five_hour" || kind == "session" { return fiveHoursSeconds }
        if id == "seven_day" || id == "seven_day_opus" || kind == "weekly" || kind == "model" { return sevenDaysSeconds }
        return nil
    }

    private static func normalizeExtraUsage(_ raw: [String: Any]?) -> QuotaWindow? {
        guard let raw, (raw["is_enabled"] as? Bool) == true else { return nil }
        let decimalPlaces = (raw["decimal_places"] as? Double) ?? 2
        let divisor = pow(10, decimalPlaces)
        let spentUsd = (raw["used_credits"] as? Double).map { $0 / divisor }
        let limitUsd = (raw["monthly_limit"] as? Double).map { $0 / divisor }
        let percentUsed: Double?
        if let utilization = raw["utilization"] as? Double {
            percentUsed = NQTime.clampPercent(utilization)
        } else if let spentUsd, let limitUsd, limitUsd > 0 {
            percentUsed = NQTime.clampPercent((spentUsd / limitUsd) * 100)
        } else {
            percentUsed = nil
        }
        return NQCommon.window(
            id: "extra_usage", label: "extra usage", kind: "credits", percentUsed: percentUsed, spentUsd: spentUsd,
            limitUsd: limitUsd)
    }

    static func normalizeClaudeProfile(_ raw: [String: Any]) -> ProviderAccount? {
        let account = raw["account"] as? [String: Any]
        guard let accountId = (account?["uuid"] as? String)?.nqNilIfEmpty else { return nil }
        let organization = raw["organization"] as? [String: Any]
        let emailCandidates: [String?] = [
            account?["email"] as? String, account?["email_address"] as? String,
            account?["emailAddress"] as? String, raw["email_address"] as? String,
            raw["emailAddress"] as? String, raw["email"] as? String,
        ]
        let email: String? = emailCandidates.compactMap { $0?.nqNilIfEmpty }.first
        let orgCandidates: [String?] = [
            organization?["name"] as? String, raw["organization_name"] as? String,
            raw["organizationName"] as? String,
        ]
        let org: String? = orgCandidates.compactMap { $0?.nqNilIfEmpty }.first
        return ProviderAccount(accountId: accountId, email: email, organization: org, identityStatus: "verified")
    }

    // MARK: - Failure -> report

    private static func failureReport(
        _ failure: Failure, attempts: [NQAttempt], credentialContextId: String, envSelected: Bool,
        definitiveFailureIsEnvOnly: Bool, environment: [String: String]
    ) async -> QuotaProvider {
        if failure.definitiveAuth, !definitiveFailureIsEnvOnly {
            NQCache.deleteCachedProvider("claude", environment: environment)
        }
        if failure.staleEligible, !envSelected,
           let cached = NQCache.readCachedClaudeProvider(contextId: credentialContextId, environment: environment),
           let stale = staleClaudeReport(cached, failure: failure, attempts: attempts)
        {
            return stale
        }
        // `state.authStatus` (claude.js) has no counterpart in QuotaBarCore's
        // `ProviderState`, which never decodes it from bundled quota-axi's JSON
        // either - `failure.authStatus` only steers the decisions above.
        let draft = NQCommon.failedDraft(
            provider: "claude", label: "Claude", status: failure.status, error: failure.code, attempts: attempts)
        return NQCommon.finalize(draft, generatedAt: NQTime.nowIso())
    }

    /// Mirrors `staleClaudeReport`: only a fresh, previously-oauth-sourced cache
    /// entry within 7 days is eligible, and each window is dropped once its own
    /// reset (or, absent one, its class-based max age) has passed.
    private static func staleClaudeReport(_ cached: NQCache.CachedSnapshot, failure: Failure, attempts: [NQAttempt]) -> QuotaProvider? {
        guard cached.provider == "claude", cached.source == "oauth", let refreshedAtText = cached.refreshedAt,
              let refreshedAt = ISO8601DateFormatter.nqFractional.date(from: refreshedAtText)
                ?? ISO8601DateFormatter.nqPlain.date(from: refreshedAtText)
        else { return nil }
        let now = Date()
        guard refreshedAt <= now else { return nil }
        let ageMs = now.timeIntervalSince(refreshedAt) * 1000
        guard ageMs < sevenDaysMs else { return nil }

        let windows = cached.windows.filter { window in
            if let resetsAtText = window.resetsAt,
               let resetsAt = ISO8601DateFormatter.nqFractional.date(from: resetsAtText) ?? ISO8601DateFormatter.nqPlain.date(from: resetsAtText)
            {
                return resetsAt > now
            }
            guard let maxAge = resetlessWindowMaxAge(window) else { return false }
            return ageMs < maxAge
        }
        guard !windows.isEmpty else { return nil }

        var sourcesTried = NQCommon.sourceNames(attempts)
        if !sourcesTried.contains("cache") { sourcesTried.append("cache") }
        let draft = NQDraft(
            provider: "claude", label: "Claude", source: "cache", plan: cached.plan, account: nil,
            windows: windows, credits: nil, attempts: attempts, status: "stale", stale: true,
            refreshedAt: cached.refreshedAt, error: failure.code, retryAfter: nil,
            sourcesTriedOverride: sourcesTried)
        return NQCommon.finalize(draft, generatedAt: NQTime.nowIso())
    }

    private static func resetlessWindowMaxAge(_ window: QuotaWindow) -> Double? {
        if window.kind == "weekly" || window.kind == "model" { return sevenDaysMs }
        if window.kind == "session" || window.kind == "monthly" || window.kind == "credits" { return fiveHoursMs }
        return nil
    }
}

extension NQClaudeReader.Failure: Error {}

private extension Dictionary where Key == String, Value == String {
    var asAccount: ProviderAccount {
        ProviderAccount(accountId: nil, email: nil, organization: nil, identityStatus: self["identityStatus"])
    }
}

private extension String {
    var nqNilIfEmpty: String? { isEmpty ? nil : self }
}
