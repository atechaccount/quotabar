import Foundation

/// Every Keychain access goes through `/usr/bin/security` as a child process,
/// exactly as quota-axi does (`providers/claude.js`, `providers/cursor-cli-
/// credential.js`) - never the Security framework directly, so a new app
/// identity never trips a Keychain ACL prompt for code signing reasons the
/// Security framework would apply that the command-line tool does not.
///
/// **Prompt avoidance**: a value read (`-w`) is only ever attempted when the
/// caller has already established (via a keychain-access marker file) that a
/// prior read succeeded without a prompt, or a presence-only check (no `-w`)
/// is used instead. QuotaBar itself never passes an "allow keychain prompt"
/// flag (mirroring `QuotaAXIRunner`'s existing `--json --full` invocation,
/// which never sends `--allow-keychain-prompt` either), so this module never
/// deliberately trips the interactive Keychain dialog.
enum NQSecurity {
    static let itemNotFoundExitCode: Int32 = 44

    /// `security find-generic-password -a <account> -s <service> -w`: reads the
    /// stored secret. Only called once a keychain-access marker or an explicit
    /// allow-prompt flag says this is safe.
    static func findGenericPasswordValue(
        account: String, service: String, keychainPath: String? = nil, timeout: TimeInterval
    ) async throws -> String {
        var arguments = ["find-generic-password", "-a", account, "-w", "-s", service]
        if let keychainPath { arguments.append(keychainPath) }
        return try await NQProcess.execFileText("/usr/bin/security", arguments, timeout: timeout)
    }

    /// `security find-generic-password -a <account> -s <service>` with no `-w`:
    /// a presence check that never prompts and never reads a value.
    static func findGenericPasswordPresence(account: String, service: String, timeout: TimeInterval) async -> Presence {
        do {
            _ = try await NQProcess.execFileText(
                "/usr/bin/security", ["find-generic-password", "-a", account, "-s", service],
                timeout: timeout)
            return .present
        } catch let error as NQProcess.ExecError {
            return isItemNotFound(error) ? .missing : .unknown
        } catch {
            return .unknown
        }
    }

    enum Presence { case present, missing, unknown }

    static func isItemNotFound(_ error: NQProcess.ExecError) -> Bool {
        error.exitStatus == itemNotFoundExitCode
    }

    /// `security list-keychains`, parsed into the quoted absolute paths it prints.
    static func listKeychains(timeout: TimeInterval) async -> [String]? {
        guard let output = try? await NQProcess.execFileText("/usr/bin/security", ["list-keychains"], timeout: timeout)
        else { return nil }
        var paths: [String] = []
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"") else { return nil }
            let path = String(trimmed.dropFirst().dropLast())
            guard path.hasPrefix("/") else { return nil }
            if !paths.contains(path) { paths.append(path) }
        }
        return paths.isEmpty ? nil : paths
    }

    /// `security dump-keychain <paths...>`: metadata only (no `-d`, `-r`, `-a`,
    /// `-i`), for locating which keychain in the search list holds the item.
    static func dumpKeychainMetadata(paths: [String], timeout: TimeInterval) async -> String? {
        try? await NQProcess.execFileText("/usr/bin/security", ["dump-keychain"] + paths, timeout: timeout)
    }
}

/// Ports `selectKeychainItem`/`listKeychainItem` from `providers/claude.js`: a
/// metadata-only search of the whole Keychain search list for the exact item
/// this profile selects, tolerant of the vendor's opaque per-install service
/// suffix, and never opening or asserting absence from inconclusive evidence.
enum NQClaudeKeychainLookup {
    struct FoundItem { let service: String; let keychainPath: String }

    enum Result {
        case present(FoundItem)
        case missing
        case unknown
    }

    static func find(
        account: String, locations: NQClaudeProfile.Locations, timeout: TimeInterval
    ) async -> Result {
        guard let paths = await NQSecurity.listKeychains(timeout: timeout) else { return .unknown }
        guard let metadata = await NQSecurity.dumpKeychainMetadata(paths: paths, timeout: timeout) else {
            return .unknown
        }
        return select(metadata: metadata, account: account, locations: locations, paths: paths)
    }

    private static func select(
        metadata: String, account: String, locations: NQClaudeProfile.Locations, paths: [String]
    ) -> Result {
        var exactItem: FoundItem?
        var opaqueItems: [String: FoundItem] = [:]
        var seenKeychains = Set<String>()
        var inconclusive = false

        for record in splitRecords(metadata) {
            guard !record.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let keychain = firstMatch(#"^keychain: (.+)$"#, in: record).flatMap(decodeMetadataValue)
            let kind = firstMatch(#"^class: (.+)$"#, in: record)
            guard let keychain, paths.contains(keychain), let kind else {
                inconclusive = true
                continue
            }
            seenKeychains.insert(keychain)
            guard kind == "\"genp\"" else { continue }

            let serviceRaw = firstMatch(#"^\s+"svce"<blob>=(.+)$"#, in: record)
            let accountRaw = firstMatch(#"^\s+"acct"<blob>=(.+)$"#, in: record)
            guard let serviceRaw, let accountRaw,
                  let service = decodeMetadataValue(serviceRaw), let itemAccount = decodeMetadataValue(accountRaw)
            else {
                inconclusive = true
                continue
            }

            let claudeOwned = service.hasPrefix(NQClaudeProfile.keychainServiceBase)
            guard itemAccount == account else {
                if claudeOwned { inconclusive = true }
                continue
            }
            let opaque = locations.acceptsOpaqueDefaultItem && NQClaudeProfile.isOpaqueSuffixedKeychainService(service)
            guard service == locations.keychainService || opaque else {
                if claudeOwned { inconclusive = true }
                continue
            }

            let earlier = opaque ? opaqueItems[service] : exactItem
            if let earlier, let earlierIndex = paths.firstIndex(of: earlier.keychainPath),
               let currentIndex = paths.firstIndex(of: keychain), earlierIndex <= currentIndex
            {
                continue
            }
            let found = FoundItem(service: service, keychainPath: keychain)
            if opaque { opaqueItems[service] = found } else { exactItem = found }
        }

        if let exactItem { return .present(exactItem) }
        if inconclusive || paths.contains(where: { !seenKeychains.contains($0) }) { return .unknown }
        if opaqueItems.count == 1, let only = opaqueItems.values.first { return .present(only) }
        if opaqueItems.count > 1 { return .unknown }
        return .missing
    }

    /// One record per `keychain: "..."` header, matching JS's
    /// `metadata.split(/(?=^keychain: )/m)`.
    private static func splitRecords(_ metadata: String) -> [String] {
        var records: [String] = []
        var current = ""
        for line in metadata.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("keychain: "), !current.isEmpty {
                records.append(current)
                current = ""
            }
            current += line + "\n"
        }
        if !current.isEmpty { records.append(current) }
        return records
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range), match.numberOfRanges > 1,
              let matchRange = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[matchRange])
    }

    /// `security`'s `print_buffer` emits printable bytes in quotes, or hex
    /// followed by an optional ASCII annotation. Mirrors `keychainMetadataValue`.
    private static func decodeMetadataValue(_ raw: String) -> String? {
        guard !raw.isEmpty, raw.count <= 8192 else { return nil }
        if raw == "<NULL>" { return "" }
        if let hexMatch = firstMatch(#"^0x((?:[0-9a-fA-F]{2})+)(?:\s|$)"#, in: raw) {
            var bytes: [UInt8] = []
            var index = hexMatch.startIndex
            while index < hexMatch.endIndex {
                let next = hexMatch.index(index, offsetBy: 2)
                guard let byte = UInt8(hexMatch[index..<next], radix: 16) else { return nil }
                bytes.append(byte)
                index = next
            }
            return String(decoding: bytes, as: UTF8.self)
        }
        if raw.hasPrefix("\"") && raw.hasSuffix("\"") && raw.count >= 2 {
            return String(raw.dropFirst().dropLast())
        }
        return nil
    }
}
