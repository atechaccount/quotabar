# QuotaBar

A small native macOS menu bar app that shows Claude, Codex, and Cursor quota.

QuotaBar reads Claude, Codex, and Cursor quota natively in Swift: each provider's own local credential store and usage API, in-process, with no Node.js and no subprocess at runtime.
A bundled copy of [`quota-axi`](https://github.com/kunchenguid/quota-axi) ships alongside it as a fallback for those same three providers, used only if the native reader ever fails outright.
See [`docs/native-quota-porting.md`](docs/native-quota-porting.md) for what that native port covers and how to keep it current against quota-axi upstream.

## Build and install

Read this section top to bottom and run the commands in order.
It assumes nothing beyond a normal `git clone` of this repository.

### 1. Check the prerequisites

Run each of these. If any command fails or is missing, install that tool before continuing.

```sh
sw_vers -productVersion        # must print 14.0 or higher
swift --version                # must print Swift 6 or higher
xcodebuild -version 2>/dev/null || echo "no full Xcode - that's fine, Command Line Tools are enough"
node --version                 # any recent Node works; only needed to build the bundled quota-axi fallback
npm --version
```

If `swift` is missing entirely, install the Xcode Command Line Tools with `xcode-select --install`.
If `node`/`npm` are missing, install Node.js from [nodejs.org](https://nodejs.org) or with `brew install node`.

### 2. Run the tests

```sh
./test.sh
```

This must finish with a line like `Test run with N tests in M suites passed`.
If it fails, stop here and fix the failure (or ask for help) before building - do not install a build with failing tests.

### 3. Build the app

```sh
./build.sh
```

This fetches the pinned quota-axi release, compiles its standalone executable, builds QuotaBar itself in release mode, and ad-hoc signs the result.
It ends by printing `Built and signed: /path/to/dist/QuotaBar.app`.
The app is now at `dist/QuotaBar.app` inside this repository - it has not been installed anywhere yet.

If this step fails, see "Common failures" below before trying again.

### 4. Quit any QuotaBar that is already running

If you have never installed QuotaBar before, skip this step.
Otherwise, quit it first so the next step can safely overwrite it:

```sh
osascript -e 'tell application "QuotaBar" to quit' 2>/dev/null
# or, if that does not work:
pkill -x QuotaBar 2>/dev/null
```

Neither command is an error if QuotaBar was not running.

### 5. Install it into /Applications

```sh
ditto dist/QuotaBar.app /Applications/QuotaBar.app
```

`ditto` overwrites an existing install cleanly, including removing files an older version had that the new one does not.

### 6. Launch it

```sh
open /Applications/QuotaBar.app
```

### 7. Confirm it worked

Look at the menu bar (top right of the screen, near the clock).
You should see a new icon appear within a few seconds: a small colored mark (Claude's, Codex's, or Cursor's, whichever is signed in) next to a percentage, or the app's own plain glyph if nothing is signed in yet.
Click it - a dropdown should open showing quota for each provider.
If nothing appears after 15-20 seconds, see "Common failures" below.

To confirm the installed copy is the one you just built, run `defaults read /Applications/QuotaBar.app/Contents/Info.plist CFBundleShortVersionString` and check it against the version in this repository's `Resources/Info.plist`.

### Common failures

- **`error: required tool 'X' was not found`** during `./build.sh` - install the missing tool named in the error (see step 1) and re-run `./build.sh`.
- **`./test.sh` or `./build.sh` hangs or is very slow the first time** - `./build.sh` downloads the pinned quota-axi release over the network the first time it runs; check your network connection if it does not finish within a few minutes.
- **The menu bar icon never appears** - open Console.app, search for "QuotaBar", and look for a crash or launch error. Also confirm macOS is 14.0 or newer (`sw_vers -productVersion`); QuotaBar does not run on older macOS.
- **The icon appears but shows no provider data** - this means no supported provider (Claude, Codex, or Cursor) is signed in on this Mac yet. Sign in through that provider's own CLI or app, then click the QuotaBar icon and choose Refresh.
- **macOS says the app is "damaged" or refuses to open it** - this happens if the app was copied in a way that stripped its signature (for example, zipping and re-extracting across machines). Re-run `./build.sh` and re-install from a fresh `dist/QuotaBar.app` on the same machine.
- **You need to start over cleanly** - quit QuotaBar (step 4), delete `/Applications/QuotaBar.app` and this repository's `dist/` and `.build/` directories, then repeat from step 1.

### Launch at login (optional)

Open Preferences from the QuotaBar menu and enable "Launch at login" after installing the app in `/Applications`.
QuotaBar uses Apple's `SMAppService` for this setting, which only works once the app is running from `/Applications` under a stable path.

## Scope

- This package builds only the menu bar application.
- A Notification Center widget is deferred and no widget extension is included.

## Documentation

[`docs/`](docs/README.md) covers how QuotaBar behaves and why: the [refresh schedule](docs/refresh.md), the [menu bar item](docs/menu-bar.md), the [popover's pages](docs/pages.md), [providers and their marks](docs/providers.md), [first-launch preferences](docs/preferences.md), and [verifying a build](docs/verifying-a-build.md).
The approved mockups in [`docs/design`](docs/design/README.md) are the acceptance criteria for interface changes.
