# QuotaBar

A small native macOS menu bar app that shows every AI coding provider quota reported by [`quota-axi`](https://github.com/kunchenguid/quota-axi).

QuotaBar never contacts provider APIs, reads credentials, or computes provider quota itself.
It runs `quota-axi --json --full` and renders that output as the single source of truth.

## Requirements

- macOS 14 or newer.
- Swift 6 and the macOS SDK from Xcode Command Line Tools.
- Node.js and npm to build the app.

The built app includes quota-axi and its runtime, so users need neither a global quota-axi install nor Node.js.
Development builds without the bundled executable can still use a global quota-axi install and Node.js.

## Build and install

```sh
./test.sh
./build.sh
```

The build script fetches the pinned quota-axi release, compiles its standalone executable with Bun, and creates and ad-hoc signs `dist/QuotaBar.app`.
The test wrapper runs `swift test` with the framework flags required by Command Line Tools installations that do not include the `xctest` loader.

Install it with:

```sh
ditto dist/QuotaBar.app /Applications/QuotaBar.app
open /Applications/QuotaBar.app
```

Open Preferences from the menu and enable Launch at login after installing the app in `/Applications`.
QuotaBar uses Apple's `SMAppService` for this setting.

## Scope

- This package builds only the menu bar application.
- A Notification Center widget is deferred and no widget extension is included.

## Documentation

[`docs/`](docs/README.md) covers how QuotaBar behaves and why: the [refresh schedule](docs/refresh.md), the [menu bar item](docs/menu-bar.md), the [popover's pages](docs/pages.md), [providers and their marks](docs/providers.md), [first-launch preferences](docs/preferences.md), and [verifying a build](docs/verifying-a-build.md).
The approved mockups in [`docs/design`](docs/design/README.md) are the acceptance criteria for interface changes.
