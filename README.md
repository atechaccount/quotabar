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

## What the menu bar shows

The menu bar item always shows a provider's mark next to its number, so a percentage is never unattributed.

- **Focused provider** (the default) shows one chosen provider and its session percentage.
- **Lowest of shown** shows whichever visible provider has the least left. This is available but is deliberately not the default, because the lowest number anywhere is rarely the one you are working against.
- **Icon only** shows the app mark alone.

Switch between these from the dropdown itself, in one click, using the "Menu bar" controls at the top.
Clicking any provider row also focuses that provider.
The focus starts on Claude or Codex, whichever is signed in.

## Session versus weekly

The headline number for a provider is its **session** window, the short rolling window that constrains day-to-day work on entry-tier plans.
The weekly window is secondary context and is always visible beneath it.

Every window a provider reports appears in the overview as its own row, with its own label, its own remaining percent, how often it resets, and its own reset time.
Nothing `quota-axi` reports is dropped.
Providers that are not signed in still appear, dimmed, in a separate section below the active ones, never as a fake zero.

Every percentage in the UI is **remaining**, and the header says so.

## Provider colors and marks

Brand colors and per-provider marks live in one table in `Sources/QuotaBarCore/BrandColors.swift`.
Add a provider with one line:

```swift
"newprovider": ProviderBrand(hex: "#123456", mark: .hexagon),
```

Unknown providers fall back to a neutral color and a plain dot, and still render.

Marks are drawn in code as simple vector geometry in `Sources/QuotaBar/ProviderMarkView.swift`; no vendor logo artwork is downloaded or embedded.
Colors are nudged toward readability only when a raw brand color falls below a 3:1 contrast floor against the menu bar background, which in practice affects the lighter colors on a light menu bar only.
`BrandColorTests` asserts this floor for every provider in both appearances.

Provider accents and the overview's information design were referenced from the public CodexBar app; no code or assets were copied.

## Verifying a build

Two hooks print evidence from the built bundle without screenshots or any system permission:

```sh
open dist/QuotaBar.app --env QUOTABAR_VERIFY=1 --stdout /tmp/verify.log     # preferences window
open dist/QuotaBar.app --env QUOTABAR_SELFTEST=1 --stdout /tmp/selftest.log # overview, marks, schedule
```

`QUOTABAR_VERIFY` opens the real preferences window three times, including once after closing it, and reports whether it was visible, key and frontmost each time.
`QUOTABAR_SELFTEST` prints every provider row and window it would render from live `quota-axi` output, renders each mark offscreen and compares its pixels against the expected brand color, then watches the refresh schedule tick.
Both quit the app when they finish.

## Scope

- This package builds only the menu bar application.
- A Notification Center widget is deferred and no widget extension is included.
