import Foundation

public struct QuotaSnapshot: Decodable, Sendable {
    public let generatedAt: String?
    public let schemaVersion: Int?
    public let providers: [QuotaProvider]

    enum CodingKeys: String, CodingKey {
        case generatedAt
        case schemaVersion
        case providers
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = values.lossy(String.self, forKey: .generatedAt)
        schemaVersion = values.lossy(Int.self, forKey: .schemaVersion)
        providers = values.lossy([QuotaProvider].self, forKey: .providers) ?? []
    }
}

public struct QuotaProvider: Decodable, Identifiable, Sendable {
    public let provider: String
    public let label: String?
    public let source: String?
    public let plan: String?
    public let account: ProviderAccount?
    public let windows: [QuotaWindow]?
    public let credits: ProviderCredits?
    public let attempts: [ProviderAttempt]?
    public let state: ProviderState?
    public let quotaSemantics: QuotaSemantics?

    public var id: String { provider }
    public var displayName: String { label?.nilIfEmpty ?? provider }
    public var isFresh: Bool { state?.status == "fresh" }

    public var allWindows: [QuotaWindow] { windows ?? [] }

    /// The short rolling window. On entry-tier plans this is the one that actually
    /// constrains day-to-day work, so it is the headline everywhere in the UI.
    public var sessionWindow: QuotaWindow? {
        allWindows.first { $0.isSession }
    }

    public var weeklyWindow: QuotaWindow? {
        allWindows.first { $0.isWeekly }
    }

    /// Session first, then the narrowest effective-availability scope, then the
    /// lowest window. Always carries the label of whatever it measured, so the
    /// number on screen is never an unattributed percentage.
    public var headline: QuotaHeadline? {
        guard isFresh else { return nil }

        if let session = sessionWindow, let remaining = session.percentRemaining {
            return QuotaHeadline(
                percentRemaining: remaining,
                windowLabel: session.displayLabel,
                resetsAt: session.resetsAt,
                isSession: true)
        }

        let scopes = (quotaSemantics?.effectiveAvailability ?? [])
            .filter { $0.effectivePercentRemaining != nil }
        if let lowest = scopes.min(by: {
            ($0.effectivePercentRemaining ?? 101) < ($1.effectivePercentRemaining ?? 101)
        }), let remaining = lowest.effectivePercentRemaining {
            let matching = allWindows.first { $0.matchesScope(lowest.scope) }
            return QuotaHeadline(
                percentRemaining: remaining,
                windowLabel: matching?.displayLabel ?? QuotaHeadline.humanize(lowest.scope),
                resetsAt: matching?.resetsAt ?? soonestResetRaw,
                isSession: false)
        }

        if let lowest = allWindows
            .filter({ $0.percentRemaining != nil })
            .min(by: { ($0.percentRemaining ?? 101) < ($1.percentRemaining ?? 101) }),
            let remaining = lowest.percentRemaining
        {
            return QuotaHeadline(
                percentRemaining: remaining,
                windowLabel: lowest.displayLabel,
                resetsAt: lowest.resetsAt,
                isSession: lowest.isSession)
        }

        return nil
    }

    public var headlineRemaining: Double? { headline?.percentRemaining }

    private var soonestResetRaw: String? {
        allWindows.compactMap(\.resetsAt).min()
    }

    enum CodingKeys: String, CodingKey {
        case provider
        case label
        case source
        case plan
        case account
        case windows
        case credits
        case attempts
        case state
        case quotaSemantics
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        provider = try values.decode(String.self, forKey: .provider)
        label = values.lossy(String.self, forKey: .label)
        source = values.lossy(String.self, forKey: .source)
        plan = values.lossy(String.self, forKey: .plan)
        account = values.lossy(ProviderAccount.self, forKey: .account)
        windows = values.lossy([QuotaWindow].self, forKey: .windows)
        credits = values.lossy(ProviderCredits.self, forKey: .credits)
        attempts = values.lossy([ProviderAttempt].self, forKey: .attempts)
        state = values.lossy(ProviderState.self, forKey: .state)
        quotaSemantics = values.lossy(QuotaSemantics.self, forKey: .quotaSemantics)
    }
}

public struct QuotaHeadline: Sendable, Equatable {
    public let percentRemaining: Double
    /// Which window or scope the percentage measures, so the UI can always say so.
    public let windowLabel: String
    public let resetsAt: String?
    public let isSession: Bool

    public init(percentRemaining: Double, windowLabel: String, resetsAt: String?, isSession: Bool) {
        self.percentRemaining = percentRemaining
        self.windowLabel = windowLabel
        self.resetsAt = resetsAt
        self.isSession = isSession
    }

    static func humanize(_ scope: String?) -> String {
        guard let scope, !scope.isEmpty else { return "overall" }
        return scope
            .split(separator: "_")
            .map { $0 == "gpt" ? "GPT" : $0.capitalized }
            .joined(separator: "/")
    }
}

public struct QuotaWindow: Decodable, Identifiable, Sendable {
    public let id: String?
    public let label: String?
    public let kind: String?
    public let percentUsed: Double?
    public let percentRemaining: Double?
    public let resetsAt: String?
    public let windowSeconds: Double?

    public var stableID: String { id ?? label ?? kind ?? "window" }

    public var displayLabel: String {
        label?.nilIfEmpty ?? kind?.nilIfEmpty ?? id?.nilIfEmpty ?? "window"
    }

    /// quota-axi labels short rolling windows inconsistently across providers, so
    /// classification leans on `kind`, then the window id, then its duration.
    public var isSession: Bool {
        if let kind, !kind.isEmpty { return kind == "session" }
        if let id, id.contains("hour") || id.contains("session") { return true }
        if let windowSeconds { return windowSeconds <= 86_400 }
        return false
    }

    public var isWeekly: Bool {
        if let kind, !kind.isEmpty { return kind == "weekly" }
        if let id, id.contains("week") { return true }
        if let windowSeconds { return windowSeconds >= 518_400 }
        return false
    }

    /// Antigravity-style providers name an effective-availability scope after the
    /// window it summarizes (`gemini` -> `gemini_weekly`).
    func matchesScope(_ scope: String?) -> Bool {
        guard let scope, !scope.isEmpty, scope != "all_models" else { return false }
        guard let id else { return false }
        return id == scope || id.hasPrefix(scope + "_") || id.hasSuffix("_" + scope)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case kind
        case percentUsed
        case percentRemaining
        case resetsAt
        case windowSeconds
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = values.lossy(String.self, forKey: .id)
        label = values.lossy(String.self, forKey: .label)
        kind = values.lossy(String.self, forKey: .kind)
        percentUsed = values.lossy(Double.self, forKey: .percentUsed)
        percentRemaining = values.lossy(Double.self, forKey: .percentRemaining)
        resetsAt = values.lossy(String.self, forKey: .resetsAt)
        windowSeconds = values.lossy(Double.self, forKey: .windowSeconds)
    }
}

public struct ProviderAccount: Decodable, Sendable {
    public let accountId: String?
    public let email: String?
    public let organization: String?
    public let identityStatus: String?

    enum CodingKeys: String, CodingKey {
        case accountId
        case email
        case organization
        case identityStatus
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        accountId = values.lossy(String.self, forKey: .accountId)
        email = values.lossy(String.self, forKey: .email)
        organization = values.lossy(String.self, forKey: .organization)
        identityStatus = values.lossy(String.self, forKey: .identityStatus)
    }
}

public struct ProviderCredits: Decodable, Sendable {
    public let remaining: Double?
    public let unlimited: Bool?
    public let unit: String?

    enum CodingKeys: String, CodingKey {
        case remaining
        case unlimited
        case unit
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        remaining = values.lossy(Double.self, forKey: .remaining)
        unlimited = values.lossy(Bool.self, forKey: .unlimited)
        unit = values.lossy(String.self, forKey: .unit)
    }
}

public struct ProviderAttempt: Decodable, Sendable {
    public let source: String?
    public let status: String?
    public let error: String?

    enum CodingKeys: String, CodingKey {
        case source
        case status
        case error
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        source = values.lossy(String.self, forKey: .source)
        status = values.lossy(String.self, forKey: .status)
        error = values.lossy(String.self, forKey: .error)
    }
}

public struct ProviderState: Decodable, Sendable {
    public let status: String?
    public let stale: Bool?
    public let refreshedAt: String?
    public let error: String?
    public let sourcesTried: [String]?

    enum CodingKeys: String, CodingKey {
        case status
        case stale
        case refreshedAt
        case error
        case sourcesTried
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        status = values.lossy(String.self, forKey: .status)
        stale = values.lossy(Bool.self, forKey: .stale)
        refreshedAt = values.lossy(String.self, forKey: .refreshedAt)
        error = values.lossy(String.self, forKey: .error)
        sourcesTried = values.lossy([String].self, forKey: .sourcesTried)
    }
}

public struct QuotaSemantics: Decodable, Sendable {
    public let status: String?
    public let description: String?
    public let effectiveAvailability: [EffectiveAvailability]?
    /// Windows quota-axi expects the plan to have but cannot measure yet. The
    /// provider page says so instead of pretending the quota is simply missing.
    public let unresolvedWindowIds: [String]?

    enum CodingKeys: String, CodingKey {
        case status
        case description
        case effectiveAvailability
        case unresolvedWindowIds
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        status = values.lossy(String.self, forKey: .status)
        description = values.lossy(String.self, forKey: .description)
        effectiveAvailability = values.lossy([EffectiveAvailability].self, forKey: .effectiveAvailability)
        unresolvedWindowIds = values.lossy([String].self, forKey: .unresolvedWindowIds)
    }
}

public struct EffectiveAvailability: Decodable, Sendable {
    public let scope: String?
    public let status: String?
    public let effectivePercentRemaining: Double?

    enum CodingKeys: String, CodingKey {
        case scope
        case status
        case effectivePercentRemaining
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        scope = values.lossy(String.self, forKey: .scope)
        status = values.lossy(String.self, forKey: .status)
        effectivePercentRemaining = values.lossy(Double.self, forKey: .effectivePercentRemaining)
    }
}

private extension KeyedDecodingContainer {
    func lossy<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        try? decodeIfPresent(type, forKey: key)
    }
}
