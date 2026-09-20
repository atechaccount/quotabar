import Foundation

/// How a provider currently reads, in the five states the Preferences legend and
/// the provider pages both use. Keeping the vocabulary in one place is what stops
/// "not signed in" in one screen from becoming "auth_required" in the next.
public enum ProviderAvailability: Sendable, Equatable {
    /// Fresh quota and an account identity.
    case connected
    /// Fresh quota, but quota-axi found no account identity to attribute it to.
    case measurable
    case stale
    /// The source program a provider needs is missing from this machine.
    case cliUnavailable
    /// quota-axi reached the provider but cannot measure the named windows yet.
    case unresolvedWindows(count: Int)
    /// No usable credentials were found.
    case signInRequired
    /// Anything quota-axi reports that QuotaBar has no better word for.
    case other(String)

    public var label: String {
        switch self {
        case .connected: "Connected"
        case .measurable: "Measurable"
        case .stale: "Stale"
        case .cliUnavailable: "CLI unavailable"
        case let .unresolvedWindows(count):
            count == 1 ? "1 unresolved window" : "\(count) unresolved windows"
        case .signInRequired: "Sign-in required"
        case let .other(text): text
        }
    }

    /// Only a provider quota-axi can actually measure belongs in the switcher and
    /// the Overview on first launch.
    public var isMeasurable: Bool {
        switch self {
        case .connected, .measurable, .stale: true
        default: false
        }
    }

    public enum Tone: Sendable, Equatable {
        case good
        case neutral
        case warning
        case critical
    }

    public var tone: Tone {
        switch self {
        case .connected, .measurable: .good
        case .stale: .warning
        case .signInRequired: .neutral
        case .cliUnavailable: .warning
        case .unresolvedWindows: .critical
        case .other: .neutral
        }
    }
}

public extension QuotaProvider {
    /// Precedence matters: a missing CLI is reported before a missing sign-in,
    /// because installing the tool is the step that unblocks it.
    var availability: ProviderAvailability {
        if usageState == .stale { return .stale }
        if isFresh {
            return account?.email?.nilIfEmpty == nil ? .measurable : .connected
        }
        let status = state?.status ?? ""
        if status == "unavailable" || (state?.error ?? "").hasSuffix("_cli_unavailable") {
            return .cliUnavailable
        }
        let unresolved = quotaSemantics?.unresolvedWindowIds ?? []
        if !unresolved.isEmpty {
            return .unresolvedWindows(count: unresolved.count)
        }
        if status == "auth_required" { return .signInRequired }
        return .other(ProviderPresentation.humanizeCode(status.isEmpty ? "unknown" : status))
    }

    var brand: ProviderBrand { BrandColors.brand(for: provider) }

    /// The one-line context under a provider's name in the Overview: plan and
    /// account when they exist, otherwise the source and an honest statement that
    /// there is no identity to show.
    var overviewContext: String {
        var parts: [String] = []
        if let plan = plan?.nilIfEmpty { parts.append(ProviderPresentation.humanizePlan(plan)) }
        if let email = account?.email?.nilIfEmpty {
            parts.append(email)
        } else if let organization = account?.organization?.nilIfEmpty {
            parts.append(organization)
        }
        if parts.isEmpty {
            parts.append(ProviderPresentation.humanizeSource(source))
            parts.append("No account identity")
        }
        return parts.joined(separator: " · ")
    }

    /// The account block on a signed-in provider page.
    var accountIdentity: String {
        account?.email?.nilIfEmpty
            ?? account?.organization?.nilIfEmpty
            ?? account?.accountId?.nilIfEmpty
            ?? "No account identity"
    }

    var planDescription: String? {
        plan?.nilIfEmpty.map { "\(ProviderPresentation.humanizePlan($0)) plan" }
    }

    /// What QuotaBar tells the user to do about an unreadable provider. It never
    /// claims QuotaBar itself can fix it.
    var unavailableGuidance: String {
        switch availability {
        case .cliUnavailable:
            return "quota-axi could not run the command-line tool \(displayName) needs. "
                + "Install it, then refresh QuotaBar."
        case let .unresolvedWindows(count):
            let windows = count == 1 ? "window" : "windows"
            return "quota-axi reached \(displayName) but cannot measure \(count) expected "
                + "quota \(windows) yet."
        case .signInRequired, .other:
            return "quota-axi could not find a usable \(displayName) sign-in. "
                + "Sign in through \(displayName), then refresh QuotaBar."
        case .connected, .measurable, .stale:
            return "\(displayName) is reporting quota normally."
        }
    }

    var unavailableHeadline: String {
        switch availability {
        case .unresolvedWindows: "Quota windows unresolved"
        default: "Usage unknown"
        }
    }

    /// Kept for the compact menu-bar accessibility text.
    var unavailableDescription: String {
        state?.status == "auth_required" ? "not signed in" : "unavailable"
    }

    /// Every source quota-axi actually tried, and what came back. This is the
    /// whole diagnostics table on an unavailable provider page.
    var sourceDiagnostics: [ProviderSourceDiagnostic] {
        let reported = attempts ?? []
        if !reported.isEmpty {
            return reported.map {
                ProviderSourceDiagnostic(
                    sourceID: $0.source ?? "unknown",
                    title: ProviderPresentation.humanizeSourceID($0.source),
                    outcome: ProviderPresentation.humanizeOutcome(status: $0.status, error: $0.error))
            }
        }
        return (state?.sourcesTried ?? []).map {
            ProviderSourceDiagnostic(
                sourceID: $0,
                title: ProviderPresentation.humanizeSourceID($0),
                outcome: ProviderPresentation.humanizeOutcome(status: nil, error: state?.error))
        }
    }
}

public extension QuotaWindow {
    /// The window's name as a heading. quota-axi labels windows in running
    /// prose (`session`, `week`), which reads wrong as a title next to a
    /// number. Only the case changes - the word itself is never rewritten.
    var titleLabel: String {
        ProviderPresentation.humanizeCode(displayLabel)
    }
}

public struct ProviderSourceDiagnostic: Sendable, Equatable, Identifiable {
    public let sourceID: String
    public let title: String
    public let outcome: String

    public var id: String { sourceID }

    public init(sourceID: String, title: String, outcome: String) {
        self.sourceID = sourceID
        self.title = title
        self.outcome = outcome
    }
}

/// Turns quota-axi's machine vocabulary into the words the mockups use. Anything
/// unrecognized is humanized rather than hidden, so a new quota-axi source or
/// error code still reads as something rather than disappearing.
public enum ProviderPresentation {
    private static let sourceTitles: [String: String] = [
        "oauth": "OAuth sign-in",
        "oauth-file": "OAuth credentials file",
        "oauth-profile": "OAuth profile",
        "keychain": "System keychain",
        "cli-keychain": "CLI keychain",
        "state-vscdb": "Application state database",
        "apps-json": "Application credentials file",
        "auth-json": "Auth credentials file",
        "cli": "Provider command-line tool",
        "bl-cli": "bl command-line tool",
        "commandcode-cli": "Command Code command-line tool",
        "kimi-code-cli": "Kimi Code command-line tool",
    ]

    private static let sourcePrefixes: [(prefix: String, describe: (String) -> String)] = [
        ("env:", { "Environment variable \($0)" }),
        ("pi:", { "pi credential store (\($0))" }),
        ("omp:", { "omp credential store (\($0))" }),
        ("gh:", { "GitHub CLI (\($0))" }),
        ("opencode:", { "OpenCode credentials (\($0))" }),
    ]

    public static func humanizeSourceID(_ source: String?) -> String {
        guard let source = source?.nilIfEmpty else { return "Unknown source" }
        if let known = sourceTitles[source] { return known }
        for entry in sourcePrefixes where source.hasPrefix(entry.prefix) {
            return entry.describe(String(source.dropFirst(entry.prefix.count)))
        }
        return humanizeCode(source)
    }

    /// The short right-hand column of the diagnostics table.
    public static func humanizeOutcome(status: String?, error: String?) -> String {
        if let error = error?.nilIfEmpty {
            if error.contains("credential") || error.contains("sign-in") || error.contains("sign_in") {
                return "No credentials"
            }
            if error.hasSuffix("_cli_unavailable") || error.contains("not_installed") {
                return "Not installed"
            }
            return humanizeCode(error)
        }
        switch status {
        case "success": return "Succeeded"
        case "skipped": return "Skipped"
        case .some(let other) where !other.isEmpty: return humanizeCode(other)
        default: return "No result"
        }
    }

    public static func humanizeSource(_ source: String?) -> String {
        guard let source = source?.nilIfEmpty, source != "unavailable" else { return "No source" }
        switch source {
        case "oauth": return "OAuth"
        case "cli": return "CLI"
        case "api": return "API"
        default: return humanizeCode(source)
        }
    }

    /// quota-axi reports plans lowercased (`pro`, `plus`).
    public static func humanizePlan(_ plan: String) -> String {
        plan.prefix(1).uppercased() + plan.dropFirst()
    }

    /// `bl_cli_unavailable` -> `Bl cli unavailable`, without inventing meaning.
    public static func humanizeCode(_ code: String) -> String {
        let spaced = code
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        guard let first = spaced.first else { return code }
        return first.uppercased() + spaced.dropFirst()
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
