# Status

## In progress

- None.

## Waiting on user

- None.

## Next

- Build the separately scoped Notification Center widget when full Xcode is available. This is deferred follow-up work and no widget extension exists in this package.
- Keep login-item status deliberately unqueried until the user opens Preferences, avoiding a Background Task Management permission prompt during ordinary startup and quota refresh.
- Investigate whether the ad-hoc-signed app sees fewer credential sources than an interactive shell; `auth_required` rows are expected and safe in the meantime.

## Recent round

Polish round driven by running the app. What changed:

- **Preferences opens reliably.** The SwiftUI `Settings` scene was replaced by `SettingsWindowPresenter`, which activates the app, orders the window front and makes it key, and drops the window on close so reopening works. `SettingsWindowPresenterTests` drives the same object the button drives; `QUOTABAR_VERIFY=1` proves it in the built bundle, reporting `visible=true key=true` on the first open, the second, and the reopen after a close.
- **The menu bar number is attributed.** It now shows the focused provider's mark next to its session percentage, never a bare number. The focus defaults to Claude or Codex, whichever is signed in, and is switched in one click from the dropdown. "Lowest of shown" remains available but is no longer the default.
- **Session is the headline.** A provider's headline number is its short rolling session window, with the weekly window kept as secondary context. Both are always visible with their own reset times.
- **Provider marks.** Every provider has a distinct mark drawn in code in its brand color, in the dropdown and beside the menu bar number. Marks and colors share one table in `Sources/QuotaBarCore/BrandColors.swift`.
- **Full overview.** Every provider `quota-axi` reports appears, with every window broken out by its own label, remaining percent, reset cadence and reset time. Providers that are not signed in appear dimmed in a separate section, never as a fake zero.
- **Legibility.** Brand colors are checked against a 3:1 contrast floor on both light and dark menu bars and darkened only when a raw color falls below it, which affects the lighter colors on a light menu bar only.

Verified on the built bundle against live `quota-axi` output: 11 providers reported, 3 active and 8 dimmed with nothing dropped; every mark rendered in its expected brand color in both appearances; and the refresh schedule ticked at 32.4s and 30.0s against a 30s interval with no errors.
