import Foundation

/// Ports the macOS branch of `providers/cursor-cli-credential.js`: the Cursor
/// CLI (`cursor-agent`) keeps sign-in identity in a plain `cli-config.json` and
/// the access token itself in the macOS login Keychain. The Linux auth-file
/// branch is not ported - QuotaBar only ships for macOS.
///
/// **No refresh at all, by design.** Neither the `cursor-refresh-token`
/// Keychain item nor any refresh flow is read or exchanged, because quota-axi
/// has no safe vendor-owned non-interactive refresh command for Cursor. A
/// rejected access token falls back to reporting authentication is required
/// (or an eligible stale snapshot); recovery is running `cursor-agent login`
/// again, same as upstream.
enum NQCursorCliCredential {
    static let cliSource = "cli-keychain"
    static let keychainService = "cursor-access-token"
    static let keychainAccount = "cursor-user"
    private static let promptTimeout: TimeInterval = 60
    private static let presenceTimeout: TimeInterval = 5

    struct Identity {
        var email: String?
        var userId: String?
    }

    enum State {
        case available(accessToken: String, identity: Identity)
        case missing
        case invalid
        /// Presence known, value not read (no access marker yet).
        case skipped(error: String, credentialPresent: Bool)
    }

    static func cliConfigPath(environment: [String: String]) -> String {
        if let override = environment["CURSOR_CLI_CONFIG"], !override.isEmpty { return override }
        return (NSHomeDirectory() as NSString).appendingPathComponent(".cursor/cli-config.json")
    }

    enum IdentityReadResult { case present(Identity), missing, invalid }

    static func readIdentity(environment: [String: String]) -> IdentityReadResult {
        let path = cliConfigPath(environment: environment)
        guard let data = FileManager.default.contents(atPath: path) else { return .missing }
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let authInfo = raw["authInfo"] as? [String: Any]
        else { return .invalid }
        let email = (authInfo["email"] as? String)?.nqNilIfEmpty
        let userId = (authInfo["userId"] as? String)?.nqNilIfEmpty ?? (authInfo["authId"] as? String)?.nqNilIfEmpty
        guard email != nil || userId != nil else { return .missing }
        return .present(Identity(email: email, userId: userId))
    }

    static func readCredentialState(environment: [String: String]) async -> State {
        let identity: Identity
        switch readIdentity(environment: environment) {
        case .missing: return .missing
        case .invalid: return .invalid
        case let .present(value): identity = value
        }
        let markerPath = NQPaths.cursorCliKeychainAccessMarkerPath(account: markerKey(identity), environment: environment)
        guard NQPaths.hasKeychainAccessMarker(markerPath) else {
            return await skippedState()
        }
        do {
            let secret = try await NQSecurity.findGenericPasswordValue(
                account: keychainAccount, service: keychainService, timeout: promptTimeout)
            NQPaths.writeKeychainAccessMarkerBestEffort(markerPath)
            let token = secret.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { return .invalid }
            return .available(accessToken: token, identity: identity)
        } catch let error as NQProcess.ExecError {
            if error.killed { return .skipped(error: "keychain_prompt_timeout", credentialPresent: true) }
            if NQSecurity.isItemNotFound(error) { return .missing }
            return .skipped(error: "keychain_access_denied", credentialPresent: true)
        } catch {
            return .skipped(error: "keychain_access_denied", credentialPresent: true)
        }
    }

    private static func skippedState() async -> State {
        switch await NQSecurity.findGenericPasswordPresence(account: keychainAccount, service: keychainService, timeout: presenceTimeout) {
        case .present: return .skipped(error: "keychain_prompt_required", credentialPresent: true)
        case .missing: return .missing
        case .unknown: return .skipped(error: "keychain_presence_check_failed", credentialPresent: true)
        }
    }

    private static func markerKey(_ identity: Identity) -> String {
        identity.userId ?? identity.email ?? keychainAccount
    }
}

private extension String {
    var nqNilIfEmpty: String? { isEmpty ? nil : self }
}
