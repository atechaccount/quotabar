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

The Read-only refresh preference adds `--no-credential-refresh`.
Turn it on to avoid credential renewal, with the tradeoff that displayed quota can become stale.

## Finding `quota-axi` and Node

QuotaBar resolves both `quota-axi` and the Node executable its shim needs when launched from the Dock, Spotlight, or at login, where macOS supplies a minimal `PATH`.
It searches pnpm locations, both Homebrew prefixes, and versioned nvm directories instead of depending on a terminal's login environment.
