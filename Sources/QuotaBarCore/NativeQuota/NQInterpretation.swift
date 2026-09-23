import Foundation

/// Ports the subset of quota-axi's `src/interpretation.js` needed for the
/// three providers QuotaBar reads natively: `claudeSemantics`, `codexSemantics`,
/// `cursorSemantics`, their shared `availability`/`boundConflict` machinery, and
/// `staleSemantics`. Only the fields QuotaBarCore's `QuotaSemantics` /
/// `EffectiveAvailability` decode are computed (`scope`, `status`,
/// `effectivePercentRemaining`, `description`, `unresolvedWindowIds`); the
/// pace/runway/selection detail quota-axi also publishes is dropped, exactly as
/// `QuotaParser`'s lossy decode already drops it from bundled quota-axi's own
/// JSON.
enum NQInterpretation {
    static func semantics(for provider: String, windows: [QuotaWindow], generatedAt: String) -> QuotaSemantics {
        switch provider {
        case "claude": return claudeSemantics(windows, generatedAt)
        case "codex": return codexSemantics(windows, generatedAt)
        case "cursor": return cursorSemantics(windows, generatedAt)
        default: return unknownSemantics(windows, "quota-axi does not know whether this provider's reported windows are independent or jointly bounding.")
        }
    }

    /// Mirrors `staleSemantics`: a stale reading's raw windows cannot support a
    /// live effective-remaining verdict, so every scope becomes `"unknown"`
    /// while its identity (`scope`) is kept.
    static func staleSemantics(_ semantics: QuotaSemantics) -> QuotaSemantics {
        QuotaSemantics(
            status: semantics.status == "partial" ? "partial" : "unknown",
            description: "The raw quota windows are stale diagnostic data, so effective remaining is unknown until the provider refreshes successfully.",
            effectiveAvailability: (semantics.effectiveAvailability ?? []).map {
                EffectiveAvailability(scope: $0.scope, status: "unknown", effectivePercentRemaining: nil)
            },
            unresolvedWindowIds: semantics.unresolvedWindowIds)
    }

    // MARK: - Claude

    private static func claudeSemantics(_ windows: [QuotaWindow], _ generatedAt: String) -> QuotaSemantics {
        let account = windows.filter { ["five_hour", "seven_day"].contains($0.id ?? "") }
        let models = windows.filter { $0.kind == "model" }
        let unresolved = windows.filter {
            !["five_hour", "seven_day", "extra_usage"].contains($0.id ?? "") && $0.kind != "model"
        }
        if !unresolved.isEmpty {
            return partialSemantics(unresolved, "Claude account windows bound every model and model windows add another bound, but unfamiliar windows prevent a definitive effective percentage.")
        }
        var effectiveAvailability: [EffectiveAvailability] = []
        if !account.isEmpty {
            effectiveAvailability.append(availability("all_models", account))
        }
        for model in models {
            effectiveAvailability.append(availability(model.id ?? "model", account + [model]))
        }
        return knownSemantics(effectiveAvailability, "Claude account windows bound every model. A model-specific window is an additional bound, so that model's effective remaining percentage is the minimum across the named windows.")
    }

    // MARK: - Codex

    private static func codexSemantics(_ windows: [QuotaWindow], _ generatedAt: String) -> QuotaSemantics {
        let account = windows.filter(isCodexAccountWindow)
        let codeReview = windows.filter {
            let id = $0.id ?? ""
            return id.hasPrefix("code_review_five_hour") || id.hasPrefix("code_review_weekly")
                || id.hasPrefix("code_review_window:")
        }
        let modelWindows = windows.filter { $0.kind == "model" }
        var modelScopes: [(scope: String, windows: [QuotaWindow])] = []
        for window in modelWindows {
            let scope = codexModelScope(window.id ?? "")
            if let index = modelScopes.firstIndex(where: { $0.scope == scope }) {
                modelScopes[index].windows.append(window)
            } else {
                modelScopes.append((scope, [window]))
            }
        }
        let recognizedIds = Set((account + codeReview + modelWindows).compactMap(\.id))
        let unresolved = windows.filter { !recognizedIds.contains($0.id ?? "\u{0}") }
        if !unresolved.isEmpty {
            return partialSemantics(unresolved, "Codex base account windows are applied as a bound to every model scope, including scopes that have named model windows of their own, and a named model window is an additional, separately metered budget the vendor reports alongside the base limit. A base window at zero while that model's own windows all still report allowance is published as a bound conflict rather than as the model's exhaustion. Unfamiliar windows prevent a definitive effective percentage.")
        }
        var effectiveAvailability: [EffectiveAvailability] = []
        if !account.isEmpty {
            effectiveAvailability.append(availability("all_models", account))
        }
        if !codeReview.isEmpty {
            effectiveAvailability.append(availability("code_review", codeReview))
        }
        for (scope, scoped) in modelScopes {
            effectiveAvailability.append(availability(scope, account + scoped, ownWindows: scoped))
        }
        return knownSemantics(effectiveAvailability, "Codex base account windows are applied as a bound to every model scope, including scopes that have named model windows of their own, so that model's effective remaining percentage is the minimum across the named windows. A named model window is an additional, separately metered budget the vendor reports alongside the base limit, so a base window at zero while that model's own windows all still report allowance is a contradiction between the two readings and is published as a bound conflict rather than as the model's exhaustion. Code-review windows describe a separate workload and are not included in model availability.")
    }

    private static func isCodexAccountWindow(_ window: QuotaWindow) -> Bool {
        let id = window.id ?? ""
        if id.hasPrefix("window:") { return true }
        return id.range(of: "^(?:five_hour|weekly)(?:_\\d+)?$", options: .regularExpression) != nil
    }

    private static func codexModelScope(_ id: String) -> String {
        var result = id
        result = result.replacingOccurrences(of: "_\\d+$", with: "", options: .regularExpression)
        result = result.replacingOccurrences(
            of: ":(?:5h|7d|window:[^:]+)$", with: "", options: .regularExpression)
        return result
    }

    // MARK: - Cursor

    private static let cursorIdeWindowIds: Set<String> = ["included_usage", "auto_usage", "api_usage", "spend_limit"]

    private static func cursorSemantics(_ windows: [QuotaWindow], _ generatedAt: String) -> QuotaSemantics {
        let ide = windows.filter { cursorIdeWindowIds.contains($0.id ?? "") }
        let grokBot = windows.filter { $0.id == "grok_bot" }
        let unresolved = windows.filter { !cursorIdeWindowIds.contains($0.id ?? "") && $0.id != "grok_bot" }
        var effectiveAvailability: [EffectiveAvailability] = []
        if !ide.isEmpty { effectiveAvailability.append(availability("all_models", ide)) }
        if !grokBot.isEmpty { effectiveAvailability.append(availability("grok_bot", grokBot)) }
        if !unresolved.isEmpty {
            return QuotaSemantics(
                status: "partial",
                description: "Cursor's included, auto, API usage, and spend-limit windows jointly bound every model, so effective remaining is the minimum across those named windows. The Grok Bot weekly window is an independent resource. Unfamiliar windows are not folded into either bound, so they stay unresolved.",
                effectiveAvailability: effectiveAvailability,
                unresolvedWindowIds: unresolved.map { $0.id ?? "" })
        }
        return knownSemantics(effectiveAvailability, "Cursor's included, auto, API usage, and spend-limit windows jointly bound every model, so effective remaining is the minimum across those named windows. The Grok Bot weekly window is an independent resource.")
    }

    // MARK: - Shared

    /// Mirrors `availability`, including the `boundConflict` guard: an inherited
    /// window reporting zero while every window metered for this scope alone
    /// still reports allowance is a contradiction, published as `"unknown"`
    /// rather than as this scope's exhaustion.
    private static func availability(_ scope: String, _ windows: [QuotaWindow], ownWindows: [QuotaWindow]? = nil) -> EffectiveAvailability {
        if let ownWindows, boundConflict(windows, ownWindows) {
            return EffectiveAvailability(scope: scope, status: "unknown", effectivePercentRemaining: nil)
        }
        let remaining = windows.map(\.percentRemaining)
        if remaining.isEmpty || remaining.contains(where: { $0 == nil }) {
            return EffectiveAvailability(scope: scope, status: "unknown", effectivePercentRemaining: nil)
        }
        let values = remaining.compactMap { $0 }
        return EffectiveAvailability(scope: scope, status: "known", effectivePercentRemaining: values.min())
    }

    private static func boundConflict(_ windows: [QuotaWindow], _ ownWindows: [QuotaWindow]) -> Bool {
        guard !ownWindows.isEmpty else { return false }
        let ownIds = Set(ownWindows.compactMap(\.id))
        let live = ownWindows.allSatisfy { ($0.percentRemaining ?? 0) > 0 && $0.percentRemaining != nil }
        guard live else { return false }
        return windows.contains { !ownIds.contains($0.id ?? "\u{0}") && $0.percentRemaining == 0 }
    }

    private static func knownSemantics(_ effectiveAvailability: [EffectiveAvailability], _ description: String) -> QuotaSemantics {
        QuotaSemantics(
            status: effectiveAvailability.isEmpty ? "unknown" : "known",
            description: effectiveAvailability.isEmpty
                ? "No quota windows are available, so no effective remaining percentage can be computed."
                : description,
            effectiveAvailability: effectiveAvailability,
            unresolvedWindowIds: nil)
    }

    private static func partialSemantics(_ unresolved: [QuotaWindow], _ description: String) -> QuotaSemantics {
        QuotaSemantics(
            status: "partial", description: description, effectiveAvailability: [],
            unresolvedWindowIds: unresolved.map { $0.id ?? "" })
    }

    private static func unknownSemantics(_ windows: [QuotaWindow], _ description: String) -> QuotaSemantics {
        QuotaSemantics(
            status: "unknown",
            description: windows.isEmpty
                ? "No quota windows are available, so no effective remaining percentage can be computed."
                : description,
            effectiveAvailability: [],
            unresolvedWindowIds: windows.map { $0.id ?? "" })
    }
}
