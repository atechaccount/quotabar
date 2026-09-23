import Foundation

/// The native Swift replacement for shelling out to quota-axi, covering the
/// three providers QuotaBar's team actually uses: Claude, Codex, and Cursor.
/// Each reader mirrors its quota-axi 0.1.51 source file and never throws -
/// exactly like quota-axi's own adapters, every failure becomes a
/// `QuotaProvider` with `state.status` describing what went wrong, rather than
/// an exception. See `docs/native-quota-porting.md`.
public enum NativeQuotaService {
    public static func run(
        readOnly: Bool, environment: [String: String] = ProcessInfo.processInfo.environment
    ) async -> QuotaSnapshot {
        async let claude = NQClaudeReader.fetchQuota(readOnly: readOnly, environment: environment)
        async let codex = NQCodexReader.fetchQuota(readOnly: readOnly, environment: environment)
        async let cursor = NQCursorReader.fetchQuota(readOnly: readOnly, environment: environment)
        let providers = await [claude, codex, cursor]
        return QuotaSnapshot(generatedAt: NQTime.nowIso(), schemaVersion: 3, providers: providers)
    }
}

/// QuotaBar's primary quota source: the native Swift readers, with the
/// bundled quota-axi runtime kept only as a fallback for exactly the same
/// three providers if the native path throws outright (it is not expected
/// to - every reader above absorbs its own failures - but a fallback that
/// only ever activates on a genuine bug is cheap insurance, and removing the
/// bundled runtime and `Scripts/BuildQuotaAXI.sh` waits on live Cursor
/// verification per the task scope).
public struct HybridQuotaSource: Sendable {
    private static let nativeProviders = ["claude", "codex", "cursor"]

    private let bundledRunner: QuotaAXIRunner

    public init(bundledRunner: QuotaAXIRunner = QuotaAXIRunner()) {
        self.bundledRunner = bundledRunner
    }

    public func run(readOnly: Bool, timeout: TimeInterval = 20) async throws -> QuotaSnapshot {
        let snapshot = await NativeQuotaService.run(readOnly: readOnly)
        guard snapshot.providers.count == Self.nativeProviders.count else {
            // Defensive only: the native readers always return one report per
            // provider. If that ever stops being true, fall back rather than
            // show a partial snapshot.
            return try await bundledRunner.run(readOnly: readOnly, timeout: timeout, providers: Self.nativeProviders)
        }
        return snapshot
    }
}
