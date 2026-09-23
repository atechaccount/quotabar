# Refresh

## Reliable refresh design

- The default refresh interval is 2 minutes, with 30-second, 1-minute, 5-minute, 15-minute, and 30-minute choices.
- Scheduling uses a monotonic `ContinuousClock` task instead of a run-loop `Timer`.
- Each next deadline stays anchored to the prior scheduled deadline, so command duration does not stretch the interval.
- A macOS wake notification cancels any suspended wait, refreshes immediately, and re-anchors the next deadline.
- Opening the menu and choosing Refresh now both request an immediate refresh.
- Runs never overlap; requests during a run coalesce into one follow-up run.
- Every command is terminated after 20 seconds, and a failure or timeout never stops later ticks.
- Failed attempts leave the last good quota visible and mark it stale beside the continuously updating Last updated age.

The Read-only refresh preference disables credential renewal for every provider: it passes `readOnly: true` to the native readers (which then never delegate Claude's `claude doctor` refresh) and adds `--no-credential-refresh` on the rare bundled-runtime fallback.
Turn it on to avoid credential renewal, with the tradeoff that displayed quota can become stale.

## Quota source: native Swift first, bundled quota-axi as a fallback

`HybridQuotaSource` (`Sources/QuotaBarCore/NativeQuota/NativeQuotaService.swift`) is what `AppModel` refreshes from.
For Claude, Codex, and Cursor, it runs the native Swift readers under `Sources/QuotaBarCore/NativeQuota/` directly, in-process, with no subprocess and no Node.js dependency.
See [`native-quota-porting.md`](native-quota-porting.md) for what each reader ports and why.

The bundled quota-axi executable is kept only as a fallback for those same three providers, used if the native readers ever throw outright; they are not expected to, since every reader absorbs its own failures into a `QuotaProvider` the same way quota-axi's own adapters do.
`Scripts/BuildQuotaAXI.sh` and the bundled runtime stay in the app until Cursor can be verified against a live signed-in account (see `native-quota-porting.md`); removing them is follow-up work.

## Finding the bundled `quota-axi` fallback

QuotaBar runs the standalone quota-axi executable beside its own app executable first.
It does not need Node.js at runtime when that bundled copy is present.
For development builds without the bundled copy, it still searches `PATH`, pnpm locations, and both Homebrew prefixes for quota-axi, then searches those locations and versioned nvm directories for the Node executable its shim needs.
