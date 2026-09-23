import Foundation

/// Ports the read/write paths of `src/cache.js` that matter for a stale-eligible
/// fallback: `readCachedProvider`, `readCachedClaudeProvider`,
/// `readCachedCodexProvider`, `writeCachedProviders`, `deleteCachedProvider`.
/// Scoped to claude/codex/cursor only, but reads and writes the *same*
/// `~/.cache/quota-axi/quotas.json` file quota-axi itself uses, so a snapshot
/// the bundled runtime wrote (or will write, if it ever runs as a fallback) is
/// available to the native reader and vice versa. Entries for any other
/// provider, or for a non-default `accountKey`, are read back untouched and
/// never removed.
enum NQCache {
    struct CachedSnapshot {
        let provider: String
        let label: String
        let source: String
        let plan: String?
        let windows: [QuotaWindow]
        let credits: ProviderCredits?
        let refreshedAt: String?
        let sourcesTried: [String]
    }

    private static let schemaVersion = 3
    private static let validProviders: Set<String> = ["claude", "codex", "cursor"]
    private static let validStatuses: Set<String> = [
        "fresh", "stale", "unavailable", "auth_required", "rate_limited", "error",
    ]
    private static let validKinds: Set<String> = ["session", "weekly", "monthly", "model", "credits", "unknown"]
    private static let credentialContextPattern = "^[a-f0-9]{64}$"

    static func readCachedProvider(
        _ provider: String, environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> CachedSnapshot? {
        readEntries(environment: environment).first { $0.provider == provider && $0.accountKey == nil }?.snapshot
    }

    /// Claude stale quota may only be reused when the cache record proves it
    /// was captured for the same locally selected credential context.
    static func readCachedClaudeProvider(
        contextId: String, environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> CachedSnapshot? {
        guard contextId.range(of: credentialContextPattern, options: .regularExpression) != nil else { return nil }
        return readEntries(environment: environment).first {
            $0.provider == "claude" && $0.accountKey == nil && $0.credentialContext == contextId
        }?.snapshot
    }

    /// Codex stale quota, withheld when the snapshot was stamped with a stored
    /// ChatGPT account id none of the failed reading's tried credentials name.
    /// An unstamped snapshot, or a reading that names no account either, is
    /// served as before (Codex stamps are optional).
    static func readCachedCodexProvider(
        accountIds: [String], environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> CachedSnapshot? {
        guard let entry = readEntries(environment: environment).first(where: { $0.provider == "codex" && $0.accountKey == nil })
        else { return nil }
        guard let contextId = entry.credentialContext, !accountIds.isEmpty else { return entry.snapshot }
        return accountIds.contains(where: { codexAccountContextId($0) == contextId }) ? entry.snapshot : nil
    }

    static func codexAccountContextId(_ accountId: String) -> String? {
        guard !accountId.isEmpty else { return nil }
        let json = (try? JSONSerialization.data(withJSONObject: ["codex-account-v1", accountId])) ?? Data()
        return NQPaths.sha256Hex(String(data: json, encoding: .utf8) ?? "")
    }

    static func deleteCachedProvider(_ provider: String, environment: [String: String] = ProcessInfo.processInfo.environment) {
        let remaining = rawEntries(environment: environment).filter { entry in
            (entry["provider"] as? String) != provider || (entry["accountKey"] as? String) != nil
        }
        writeRawEntries(remaining, environment: environment)
    }

    /// Writes fresh drafts into the cache, preserving every other entry
    /// (other providers, or non-default account keys) untouched. Only
    /// `status == "fresh"` drafts with at least one window are cacheable,
    /// mirroring `toCacheProvider`.
    static func writeCachedProviders(
        _ drafts: [NQDraft], credentialContext: [String: String],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        let cacheable = drafts.compactMap { draft -> [String: Any]? in
            guard draft.status == "fresh", !draft.windows.isEmpty else { return nil }
            var entry: [String: Any] = [
                "provider": draft.provider,
                "label": draft.label ?? draft.provider,
                "source": draft.source ?? "unavailable",
                "windows": draft.windows.map(serializeWindow),
                "state": [
                    "status": "fresh",
                    "stale": false,
                    "refreshedAt": draft.refreshedAt as Any,
                    "sourcesTried": NQCommon.sourceNames(draft.attempts),
                ],
            ]
            if let plan = draft.plan { entry["plan"] = plan }
            if let credits = draft.credits { entry["credits"] = serializeCredits(credits) }
            if let context = credentialContext[draft.provider] { entry["credentialContext"] = context }
            return entry
        }
        guard !cacheable.isEmpty else { return }
        var byIdentity: [String: [String: Any]] = [:]
        var order: [String] = []
        for entry in rawEntries(environment: environment) {
            let identity = "\(entry["provider"] as? String ?? "")/\(entry["accountKey"] as? String ?? "default")"
            if byIdentity[identity] == nil { order.append(identity) }
            byIdentity[identity] = entry
        }
        for entry in cacheable {
            let identity = "\(entry["provider"] as? String ?? "")/default"
            if byIdentity[identity] == nil { order.append(identity) }
            byIdentity[identity] = entry
        }
        writeRawEntries(order.compactMap { byIdentity[$0] }, environment: environment)
    }

    // MARK: - File I/O

    private struct Entry {
        let provider: String
        let accountKey: String?
        let credentialContext: String?
        let snapshot: CachedSnapshot
    }

    private static func readEntries(environment: [String: String]) -> [Entry] {
        rawEntries(environment: environment).compactMap(normalize)
    }

    private static func rawEntries(environment: [String: String]) -> [[String: Any]] {
        guard let data = FileManager.default.contents(atPath: NQPaths.cacheFilePath(environment: environment)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let schema = json["schemaVersion"] as? Int, [1, 2, 3].contains(schema),
              let providers = json["providers"] as? [[String: Any]]
        else { return [] }
        return providers
    }

    private static func writeRawEntries(_ entries: [[String: Any]], environment: [String: String]) {
        let file = NQPaths.cacheFilePath(environment: environment)
        NQPaths.ensurePrivateParent(file)
        let payload: [String: Any] = [
            "generatedAt": NQTime.nowIso(),
            "schemaVersion": schemaVersion,
            "providers": entries,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]) else { return }
        let temp = "\(file).\(ProcessInfo.processInfo.processIdentifier).tmp"
        do {
            try data.write(to: URL(fileURLWithPath: temp), options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temp)
            if FileManager.default.fileExists(atPath: file) {
                try? FileManager.default.removeItem(atPath: file)
            }
            try FileManager.default.moveItem(atPath: temp, toPath: file)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file)
        } catch {
            try? FileManager.default.removeItem(atPath: temp)
        }
    }

    private static func normalize(_ raw: [String: Any]) -> Entry? {
        guard let provider = raw["provider"] as? String, validProviders.contains(provider) else { return nil }
        guard let label = (raw["label"] as? String)?.nqNonEmpty else { return nil }
        guard let source = (raw["source"] as? String)?.nqNonEmpty else { return nil }
        guard let state = raw["state"] as? [String: Any] else { return nil }
        guard let status = (state["status"] as? String)?.nqNonEmpty, validStatuses.contains(status) else { return nil }
        guard let sourcesTried = state["sourcesTried"] as? [String] else { return nil }
        let windows = (raw["windows"] as? [[String: Any]] ?? []).compactMap(normalizeWindow)
        guard !windows.isEmpty else { return nil }

        let accountKey = (raw["accountKey"] as? String)?.nqNonEmpty
        let credentialContext = (raw["credentialContext"] as? String)?.nqNonEmpty
        let snapshot = CachedSnapshot(
            provider: provider, label: label, source: source, plan: (raw["plan"] as? String)?.nqNonEmpty,
            windows: windows, credits: normalizeCredits(raw["credits"] as? [String: Any]),
            refreshedAt: (state["refreshedAt"] as? String)?.nqNonEmpty, sourcesTried: sourcesTried)
        return Entry(provider: provider, accountKey: accountKey, credentialContext: credentialContext, snapshot: snapshot)
    }

    private static func normalizeWindow(_ raw: [String: Any]) -> QuotaWindow? {
        guard let id = (raw["id"] as? String)?.nqNonEmpty else { return nil }
        guard let label = (raw["label"] as? String)?.nqNonEmpty else { return nil }
        guard let kind = (raw["kind"] as? String)?.nqNonEmpty, validKinds.contains(kind) else { return nil }
        return QuotaWindow(
            id: id, label: label, kind: kind, percentUsed: raw["percentUsed"] as? Double,
            percentRemaining: raw["percentRemaining"] as? Double, spentUsd: raw["spentUsd"] as? Double,
            limitUsd: raw["limitUsd"] as? Double, resetsAt: (raw["resetsAt"] as? String)?.nqNonEmpty,
            windowSeconds: raw["windowSeconds"] as? Double)
    }

    private static func normalizeCredits(_ raw: [String: Any]?) -> ProviderCredits? {
        guard let raw else { return nil }
        let remaining = raw["remaining"] as? Double
        let unlimited = raw["unlimited"] as? Bool
        let unit = (raw["unit"] as? String)?.nqNonEmpty
        guard remaining != nil || unlimited != nil || unit != nil else { return nil }
        return ProviderCredits(remaining: remaining, unlimited: unlimited, unit: unit)
    }

    private static func serializeWindow(_ window: QuotaWindow) -> [String: Any] {
        var dict: [String: Any] = [
            "id": window.id ?? "window", "label": window.label ?? "window", "kind": window.kind ?? "unknown",
        ]
        if let value = window.percentUsed { dict["percentUsed"] = value }
        if let value = window.percentRemaining { dict["percentRemaining"] = value }
        if let value = window.resetsAt { dict["resetsAt"] = value }
        if let value = window.windowSeconds { dict["windowSeconds"] = value }
        if let value = window.spentUsd { dict["spentUsd"] = value }
        if let value = window.limitUsd { dict["limitUsd"] = value }
        return dict
    }

    private static func serializeCredits(_ credits: ProviderCredits) -> [String: Any] {
        var dict: [String: Any] = [:]
        if let value = credits.remaining { dict["remaining"] = value }
        if let value = credits.unlimited { dict["unlimited"] = value }
        if let value = credits.unit { dict["unit"] = value }
        return dict
    }
}

private extension String {
    var nqNonEmpty: String? { isEmpty ? nil : self }
}
