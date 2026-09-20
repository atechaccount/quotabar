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

    public var headlineRemaining: Double? {
        guard isFresh else { return nil }
        let effective = quotaSemantics?.effectiveAvailability?
            .compactMap(\.effectivePercentRemaining)
        if let effective, !effective.isEmpty {
            return effective.min()
        }
        return windows?.compactMap(\.percentRemaining).min()
    }

    public var unavailableDescription: String {
        state?.status == "auth_required" ? "not signed in" : "unavailable"
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

public struct QuotaWindow: Decodable, Identifiable, Sendable {
    public let id: String?
    public let label: String?
    public let kind: String?
    public let percentUsed: Double?
    public let percentRemaining: Double?
    public let resetsAt: String?
    public let windowSeconds: Double?

    public var stableID: String { id ?? label ?? UUID().uuidString }

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

    enum CodingKeys: String, CodingKey {
        case status
        case description
        case effectiveAvailability
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        status = values.lossy(String.self, forKey: .status)
        description = values.lossy(String.self, forKey: .description)
        effectiveAvailability = values.lossy([EffectiveAvailability].self, forKey: .effectiveAvailability)
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

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
