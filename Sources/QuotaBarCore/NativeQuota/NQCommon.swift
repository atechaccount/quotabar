import Foundation

/// One credential/source attempt, tracked internally with the bookkeeping
/// fields quota-axi's decision logic needs (`credentialPresent`, `degraded`)
/// that never reach the published `ProviderAttempt` (mirrors
/// `providers/common.js` and `lib/source-attempts.js`).
struct NQAttempt {
    var source: String
    var status: String
    var error: String?
    var credentialPresent: Bool?
    var degraded: Bool?

    init(source: String, status: String, error: String? = nil, credentialPresent: Bool? = nil, degraded: Bool? = nil) {
        self.source = source
        self.status = status
        self.error = error
        self.credentialPresent = credentialPresent
        self.degraded = degraded
    }

    var asProviderAttempt: ProviderAttempt {
        ProviderAttempt(source: source, status: status, error: error)
    }
}

/// A provider report before `quotaSemantics` is attached. Mirrors the plain
/// object shape `successProvider`/`failedProvider`/`staleFromCache` build in
/// `providers/common.js`, ahead of `withQuotaSemantics` in `interpretation.js`.
struct NQDraft {
    var provider: String
    var label: String?
    var source: String?
    var plan: String?
    var account: ProviderAccount?
    var windows: [QuotaWindow]
    var credits: ProviderCredits?
    var attempts: [NQAttempt]
    var status: String
    var stale: Bool
    var refreshedAt: String?
    var error: String?
    var retryAfter: String?
    /// Overrides the `sourcesTried` normally derived from `attempts`, for the
    /// `staleFromCache` case where `"cache"` is folded in without being an
    /// attempt of its own.
    var sourcesTriedOverride: [String]?

    init(
        provider: String, label: String?, source: String?, plan: String?, account: ProviderAccount?,
        windows: [QuotaWindow], credits: ProviderCredits?, attempts: [NQAttempt], status: String, stale: Bool,
        refreshedAt: String?, error: String?, retryAfter: String?, sourcesTriedOverride: [String]? = nil)
    {
        self.provider = provider
        self.label = label
        self.source = source
        self.plan = plan
        self.account = account
        self.windows = windows
        self.credits = credits
        self.attempts = attempts
        self.status = status
        self.stale = stale
        self.refreshedAt = refreshedAt
        self.error = error
        self.retryAfter = retryAfter
        self.sourcesTriedOverride = sourcesTriedOverride
    }
}

enum NQCommon {
    /// Mirrors `withRemaining`: builds a window and derives `percentRemaining`
    /// from `percentUsed`.
    static func window(
        id: String, label: String, kind: String, percentUsed: Double?, spentUsd: Double? = nil,
        limitUsd: Double? = nil, resetsAt: String? = nil, windowSeconds: Double? = nil
    ) -> QuotaWindow {
        QuotaWindow(
            id: id, label: label, kind: kind, percentUsed: percentUsed,
            percentRemaining: NQTime.percentRemaining(percentUsed), spentUsd: spentUsd,
            limitUsd: limitUsd, resetsAt: resetsAt, windowSeconds: windowSeconds)
    }

    /// Mirrors `statusFromError` in `providers/common.js`.
    static func statusFromError(_ error: String) -> String {
        if error == "keychain_prompt_required" || error == "credentials_expired"
            || error.range(of: "sign-in|required|reauth|access token expired", options: .regularExpression) != nil
        {
            return "auth_required"
        }
        if error.range(of: "rate.?limit", options: .regularExpression) != nil {
            return "rate_limited"
        }
        return "error"
    }

    /// Mirrors `sourceNames`: attempted sources, deduplicated, in first-seen order.
    static func sourceNames(_ attempts: [NQAttempt]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for attempt in attempts where seen.insert(attempt.source).inserted {
            result.append(attempt.source)
        }
        return result
    }

    static func successDraft(
        provider: String, label: String, source: String, plan: String? = nil,
        account: ProviderAccount? = nil, windows: [QuotaWindow], credits: ProviderCredits? = nil,
        refreshedAt: String?, attempts: [NQAttempt]
    ) -> NQDraft {
        NQDraft(
            provider: provider, label: label, source: source, plan: plan, account: account,
            windows: windows, credits: credits, attempts: attempts, status: "fresh", stale: false,
            refreshedAt: refreshedAt, error: nil, retryAfter: nil)
    }

    static func failedDraft(
        provider: String, label: String, source: String? = nil, status: String, error: String,
        retryAfter: String? = nil, attempts: [NQAttempt]
    ) -> NQDraft {
        NQDraft(
            provider: provider, label: label, source: source ?? "unavailable", plan: nil,
            account: nil, windows: [], credits: nil, attempts: attempts, status: status, stale: false,
            refreshedAt: nil, error: error, retryAfter: retryAfter)
    }

    /// Mirrors `staleFromCache`: the cached snapshot's provider/label/plan/
    /// windows/credits stand in, `source` becomes `"cache"`, and `state`
    /// reports the fresh attempt's own error with `"cache"` folded into
    /// `sourcesTried`.
    static func staleFromCache(
        _ cached: NQCache.CachedSnapshot, error: String, sourcesTried: [String], attempts: [NQAttempt]
    ) -> NQDraft {
        var tried = sourcesTried
        if !tried.contains("cache") { tried.append("cache") }
        return NQDraft(
            provider: cached.provider, label: cached.label, source: "cache", plan: cached.plan,
            account: nil, windows: cached.windows, credits: cached.credits, attempts: attempts,
            status: "stale", stale: true, refreshedAt: cached.refreshedAt, error: error,
            retryAfter: nil, sourcesTriedOverride: tried)
    }

    /// Turns a draft into the published `QuotaProvider`, attaching
    /// `quotaSemantics` the way `withQuotaSemantics` does in `interpretation.js`.
    static func finalize(_ draft: NQDraft, generatedAt: String) -> QuotaProvider {
        let semantics = NQInterpretation.semantics(for: draft.provider, windows: draft.windows, generatedAt: generatedAt)
        let finalSemantics = draft.stale ? NQInterpretation.staleSemantics(semantics) : semantics
        return QuotaProvider(
            provider: draft.provider, label: draft.label, source: draft.source, plan: draft.plan,
            account: draft.account, windows: draft.windows, credits: draft.credits,
            attempts: draft.attempts.map(\.asProviderAttempt),
            state: ProviderState(
                status: draft.status, stale: draft.stale, refreshedAt: draft.refreshedAt,
                error: draft.error, sourcesTried: draft.sourcesTriedOverride ?? sourceNames(draft.attempts)),
            quotaSemantics: finalSemantics)
    }
}
