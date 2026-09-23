import CryptoKit
import Foundation

/// Cache directory, keychain-access-marker, and Claude profile-selector paths.
/// Mirrors `src/lib/fs.js` and `src/lib/claude-profile.js`. quota-axi's own
/// on-disk quota cache lives here too (`quotas.json`), so the native reader and
/// the bundled quota-axi runtime share one cache file.
enum NQPaths {
    static func cacheDirPath(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        let base = environment["XDG_CACHE_HOME"]?.nilIfEmpty
            ?? (NSHomeDirectory() as NSString).appendingPathComponent(".cache")
        return (base as NSString).appendingPathComponent("quota-axi")
    }

    static func cacheFilePath(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        (cacheDirPath(environment: environment) as NSString).appendingPathComponent("quotas.json")
    }

    /// Mirrors `ensurePrivateParent`.
    static func ensurePrivateParent(_ file: String) {
        let directory = (file as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
    }

    /// Mirrors `claudeKeychainAccessMarkerPath`.
    static func claudeKeychainAccessMarkerPath(account: String, service: String, environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        let serviceSuffix = String(sha256Hex(service).prefix(8))
        let accountSuffix = String(sha256Hex(account).prefix(16))
        return (cacheDirPath(environment: environment) as NSString)
            .appendingPathComponent("claude-keychain-access-granted-\(serviceSuffix)-account-\(accountSuffix)")
    }

    /// Mirrors `cursorCliKeychainAccessMarkerPath`.
    static func cursorCliKeychainAccessMarkerPath(account: String, environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        let accountSuffix = String(sha256Hex(account).prefix(16))
        return (cacheDirPath(environment: environment) as NSString)
            .appendingPathComponent("cursor-cli-keychain-access-granted-account-\(accountSuffix)")
    }

    /// Writes a best-effort access-granted marker: write to a pid-suffixed temp
    /// file, then rename into place, mirroring
    /// `writeKeychainAccessMarkerBestEffort` in both `providers/claude.js` and
    /// `providers/cursor-cli-credential.js`.
    static func writeKeychainAccessMarkerBestEffort(_ file: String) {
        ensurePrivateParent(file)
        let temp = "\(file).\(ProcessInfo.processInfo.processIdentifier).tmp"
        do {
            try "granted\n".write(toFile: temp, atomically: true, encoding: .utf8)
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

    static func hasKeychainAccessMarker(_ file: String) -> Bool {
        FileManager.default.fileExists(atPath: file)
    }

    static func sha256Hex(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// Mirrors `src/lib/claude-profile.js`: Claude Code's own credential-directory
/// and secure-storage selectors, so the reader looks in exactly the place
/// Claude Code itself would.
enum NQClaudeProfile {
    static let keychainServiceBase = "Claude Code-credentials"
    static let oauthTokenEnvKey = "CLAUDE_CODE_OAUTH_TOKEN"

    struct Locations {
        let configDir: String
        let secureStorageSelected: Bool
        let keychainService: String
        let acceptsOpaqueDefaultItem: Bool
    }

    /// The explicit environment credential Claude Code resolves before any
    /// stored credential. Presence-only; never logged.
    static func envOauthToken(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        NQSecret.usableLiteralSecret(environment[oauthTokenEnvKey]?.trimmingCharacters(in: .whitespaces))
    }

    static func locations(environment: [String: String] = ProcessInfo.processInfo.environment) -> Locations {
        let configured = environment["CLAUDE_CONFIG_DIR"]
        let storage = environment["CLAUDE_SECURESTORAGE_CONFIG_DIR"]
        let defaultDir = (NSHomeDirectory() as NSString).appendingPathComponent(".claude")
        let configDir = (configured ?? defaultDir).precomposedStringWithCanonicalMapping
        let storageSelector = storage?.precomposedStringWithCanonicalMapping.nilIfEmpty
        let selector = storageSelector ?? (configured != nil ? configDir : nil)
        return Locations(
            configDir: configDir,
            secureStorageSelected: storageSelector != nil,
            keychainService: selector.map { suffixedKeychainService($0) } ?? keychainServiceBase,
            acceptsOpaqueDefaultItem: selector == nil)
    }

    static func isOpaqueSuffixedKeychainService(_ service: String) -> Bool {
        guard service.hasPrefix("\(keychainServiceBase)-") else { return false }
        let suffix = service.dropFirst(keychainServiceBase.count + 1)
        return suffix.count == 8 && suffix.allSatisfy(\.isHexDigit) && suffix == suffix.lowercased()
    }

    private static func suffixedKeychainService(_ selector: String) -> String {
        "\(keychainServiceBase)-\(String(NQPaths.sha256Hex(selector).prefix(8)))"
    }

    /// A deterministic, opaque cache-provenance id for the Claude profile this
    /// process selected. Mirrors `claudeCredentialContextId`.
    static func credentialContextId(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        let locations = locations(environment: environment)
        let envSelected = envOauthToken(environment: environment) != nil
        var parts = ["claude-profile-v3", resolvedPath(locations.configDir), locations.keychainService]
        if envSelected { parts.append("env-token") }
        let json = (try? JSONSerialization.data(withJSONObject: parts, options: [])) ?? Data()
        return NQPaths.sha256Hex(String(data: json, encoding: .utf8) ?? "")
    }

    private static func resolvedPath(_ path: String) -> String {
        (path as NSString).standardizingPath
    }
}
