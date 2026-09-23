import Foundation
import QuotaBarCore

/// Evidence hook for verifying the native Swift readers against the bundled
/// quota-axi 0.1.51 runtime, field by field, on this machine's real Claude and
/// Codex sign-ins. Launch the bundle with `QUOTABAR_COMPARE_QUOTA=1`.
///
/// Always read-only on both sides (`--no-credential-refresh` for the bundled
/// run, `readOnly: true` for the native run): comparison must never delegate a
/// credential refresh or write to the shared quota-axi cache differently than
/// a normal read would. Run this by hand, a small bounded number of times -
/// never in a loop - since every run is two live requests per provider against
/// the real usage endpoints.
enum QuotaCompare {
    static func run() async {
        print("COMPARE begin")
        let native = await NativeQuotaService.run(readOnly: true)
        let bundled: QuotaSnapshot?
        do {
            bundled = try await QuotaAXIRunner().run(readOnly: true, timeout: 20, providers: ["claude", "codex", "cursor"])
        } catch {
            print("COMPARE bundled-run-failed error=\(error.localizedDescription)")
            bundled = nil
        }

        for providerId in ["claude", "codex", "cursor"] {
            let nativeProvider = native.providers.first { $0.provider == providerId }
            let bundledProvider = bundled?.providers.first { $0.provider == providerId }
            compare(providerId, nativeProvider, bundledProvider)
        }
        print("COMPARE end")
    }

    private static func compare(_ providerId: String, _ native: QuotaProvider?, _ bundled: QuotaProvider?) {
        print("COMPARE provider=\(providerId)")
        guard let native else {
            print("  native=missing (should never happen - the native reader always returns a report)")
            return
        }
        guard let bundled else {
            print("  bundled=unavailable (bundled quota-axi could not run at all)")
            return
        }
        field("status", native.state?.status, bundled.state?.status)
        field("stale", native.state?.stale.map(String.init), bundled.state?.stale.map(String.init))
        field("source", native.source, bundled.source)
        field("plan", native.plan, bundled.plan)
        field("identityPresent", String(hasIdentity(native)), String(hasIdentity(bundled)))
        field("windowCount", String(native.allWindows.count), String(bundled.allWindows.count))

        let nativeWindows = Dictionary(uniqueKeysWithValues: native.allWindows.map { ($0.stableID, $0) })
        let bundledWindows = Dictionary(uniqueKeysWithValues: bundled.allWindows.map { ($0.stableID, $0) })
        for id in Set(nativeWindows.keys).union(bundledWindows.keys).sorted() {
            let nativeWindow = nativeWindows[id]
            let bundledWindow = bundledWindows[id]
            field(
                "  window[\(id)].percentRemaining",
                nativeWindow?.percentRemaining.map { String($0) }, bundledWindow?.percentRemaining.map { String($0) })
            field("  window[\(id)].resetsAt", nativeWindow?.resetsAt, bundledWindow?.resetsAt)
        }
        if providerId == "claude" {
            let nativeExtra = native.allWindows.first { $0.id == "extra_usage" }
            let bundledExtra = bundled.allWindows.first { $0.id == "extra_usage" }
            field("extraUsagePresent", String(nativeExtra != nil), String(bundledExtra != nil))
        }
    }

    private static func hasIdentity(_ provider: QuotaProvider) -> Bool {
        !(provider.account?.email ?? "").isEmpty || !(provider.account?.accountId ?? "").isEmpty
    }

    private static func field(_ name: String, _ nativeValue: String?, _ bundledValue: String?) {
        let match = nativeValue == bundledValue ? "match" : "DIFFER"
        print("  \(name): native=\(nativeValue ?? "nil") bundled=\(bundledValue ?? "nil") [\(match)]")
    }
}
