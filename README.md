# QuotaBar

A small native macOS menu bar app that shows every AI coding provider quota reported by [`quota-axi`](https://github.com/durell/quota-axi).

QuotaBar never contacts provider APIs, reads credentials, or computes provider quota itself.
It runs `quota-axi --json --full` and renders that output as the single source of truth.

## Requirements

- macOS 14 or newer.
- Swift 6 and the macOS SDK from Xcode Command Line Tools.
- `quota-axi` on `PATH`, or installed at `/Users/durell/Library/pnpm/bin/quota-axi`.

If `quota-axi` cannot be found, QuotaBar shows a clear error and keeps its refresh schedule alive.

## Build and install

```sh
./test.sh
./build.sh
```

The build script creates and ad-hoc signs `dist/QuotaBar.app`.
The test wrapper runs `swift test` with the framework flags required by Command Line Tools installations that do not include the `xctest` loader.

Install it with:

```sh
ditto dist/QuotaBar.app /Applications/QuotaBar.app
open /Applications/QuotaBar.app
```

Open Preferences from the menu and enable Launch at login after installing the app in `/Applications`.
QuotaBar uses Apple's `SMAppService` for this setting.

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

## Provider colors

All known brand colors live in one table in `Sources/QuotaBarCore/BrandColors.swift`.
Add a provider by adding one identifier-to-hex entry there; unknown providers automatically use a neutral fallback color and still render.

The initial accents were referenced from the public CodexBar provider descriptors, while all QuotaBar code, icons, and architecture are original.

## Scope

- This package builds only the menu bar application.
- A Notification Center widget is deferred and no widget extension is included.

Status: under construction.
