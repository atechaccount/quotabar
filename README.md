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

The menu bar item is a plain AppKit `NSStatusItem`. Its button gets a real `NSImage` of the focused provider's mark, painted in that provider's brand color with `isTemplate` left off, plus the percentage as the button title.

This is deliberate and load-bearing. QuotaBar previously used SwiftUI's `MenuBarExtra` with a custom `Shape` in its label; the status item host keeps the `Text` from such a label and silently drops the shape, so the menu bar showed a bare percentage with no mark at all. `StatusItemController` owns the status item, re-renders on every model change and on every appearance change, and `SelfTest` rasterises the live button to prove the mark is actually drawn.

The mark sits on a very faint rounded plate - by default a little white on a dark menu bar, a little black on a light one - so a colored mark stays legible when a bright or busy wallpaper shows through a translucent menu bar. It is meant to read as the background settling slightly, never as a button. What it covers, what colour it is and how strong it is are all settings; see below.

### How big the item is

The item's size lives in one place, `MenuBarMetrics`. The mark and the number beside it are read as one object, so they are sized as one: a design size each - a 20pt mark against the 13pt system font, which is what the item was first built at - and a single `scale` factor that moves both. The shipped factor is 0.85, which puts the mark at 17pt and the number at 11pt and takes the whole item from 78pt wide to 70pt. The number's weight steps up to medium as it comes down in size, because thin small digits over a bright wallpaper are what a translucent menu bar takes away first; `menubar-backing.png` from the render hook draws the real item over a light menu bar, a dark one, and a bright and a busy wallpaper for checking that by eye.

This is deliberately separate from the popover's `Typography` factor. The dropdown is QuotaBar's own surface; the status item sits in the system menu bar beside everybody else's, and the two are meant to be different sizes. It is also deliberately not one of the appearance settings below: those are all matters of taste with no better answer, and the size is not - it was simply too big.

The gap between the mark and the number is not scaled with them. It is an optical minimum rather than a dimension of the item, already as small as it can be without the glyphs running into each other, so `MenuBarMetrics.gap` stays put while the pair shrinks. The backing plate's inset does scale, and the kern is derived from it, so the whole gap works out to `gap` at every size.

The title uses tabular figures and is padded to three digit widths with `U+2007 FIGURE SPACE` on the **trailing** edge, so the item keeps one width from 0% to 100% and nothing to its left in the menu bar shuffles as the quota falls. FIGURE SPACE is one digit wide in most faces but not in every one - the serif face draws it narrower - so `statusTitle` measures both in the chosen face and kerns away the difference.

The mark travels inside the attributed title as a text attachment rather than in `button.image`. That is not decoration: `button.image` plus `button.title` puts a fixed ~15pt of AppKit spacing between the two, and none of `imagePosition` or `imageHugsTitle` shifts it - all four combinations measure at exactly 15.0pt. As an attachment the gap becomes a typographic one, set by `ProviderMarkImage.menuBarGap`. The ink actually lands 0.5-4.0pt apart depending on face, appearance and digit, because a typographic gap is the nominal one plus whatever sidebearing the mark and the digit bring. `QUOTABAR_SELFTEST` sweeps every face at every digit count in both appearances, and reports the smallest and where it was, which must never reach zero.

- **Focused provider** (the default) shows one chosen provider and its session percentage.
- **Lowest of shown** shows whichever visible provider has the least left. This is available but is deliberately not the default, because the lowest number anywhere is rarely the one you are working against.
- **Icon only** shows the app mark alone.

### Appearance settings

How the item is drawn is under Preferences > Menu bar appearance, and every default is the presentation QuotaBar shipped with, so an untouched install is unchanged. The decisions live in `MenuBarAppearance` in `QuotaBarCore`, away from AppKit, because they are the part worth testing; `ProviderMarkImage` and `StatusItemController` only carry the answers to the drawing calls.

- **Icon** - the provider mark in its brand colour, or greyscale. Greyscale takes the hue out by luma and then clears the same contrast floor the brand colours do, so a drained mark never disappears into the menu bar.
- **Backing** - none, behind the icon, or behind the icon and number together. The icon-only plate is drawn into the mark image. The wide one is the status item button's own **layer background**: a sublayer would draw on top of the title AppKit renders into the layer's contents, and no image can reach behind text the button lays out itself. Whichever scope is chosen, the mark keeps one size.
- **Backing colour** - match the menu bar, or a colour and strength of your own. Anything much past a tenth reads as a badge.
- **Number colour** - match the menu bar (the system label colour), white, black, or a colour of your own.
- **Readout font** - system, rounded, monospaced or serif. Each is a system font *design* applied to the monospaced-digit system font with the tabular-figure feature re-stated on the result, so every face keeps its digits one width.

`QUOTABAR_SELFTEST` puts each option through the real status item and prints `SELFTEST appearancesweep` lines with the drawn mark's average colour, the button layer's plate alpha and corner radius, and the item's width, then restores the settings it borrowed.

### The sticky selection

Selecting a provider tab opens that provider's page **and** points the menu bar at it. Selecting Overview only changes the page: the menu bar stays where it was. The choice is written to `UserDefaults` on every change, so it survives closing the popover, moving back to Overview, quitting and relaunching.

Two edge cases are deliberate:

- Before any choice has been made, the first snapshot seeds the focus once, preferring a signed-in Claude, then Codex, then the first provider with a measurable headline. With nothing measurable, the menu bar shows QuotaBar's own glyph and no number.
- If the focused provider later signs out, its mark stays in the menu bar and only the number disappears. Hiding a provider in Preferences removes its tab but never rewrites the stored focus.

## Pages

The popover is a tab strip over one page at a time, not a single flat column.

- **Overview** is the default page. It shows only providers with fresh, measurable quota: name, account and plan, a right-aligned headline percentage, and one solid meter per window. Everything else is one quiet line naming the count and pointing at Preferences.
- **A signed-in provider page** shows that provider's account, plan, source and freshness, then one section per window quota-axi actually reported, with the percentage and the reset time each on their own right edge.
- **An unavailable provider page** is hidden until the provider is turned on by hand. It states the real status, lists every source quota-axi tried and what came back, and says what QuotaBar will and will not do about it. It never renders a missing quota as zero.

Type is one scale: sizes are written as the base size they were designed at and passed through a single factor in `Typography`, with a floor that keeps the fine print readable. Changing the whole interface's size is one constant. The pair is 0.85 against a 9.0pt floor, which is as far down as it goes while the hierarchy survives: base 11 is the secondary body size - the plan line, the account identity, the freshness sentence, the credits line, every reset time - and at 0.85 it computes to 9.35, so a floor above 9.0 would clamp it into the fine print along with the three sizes below it.

On a provider page the window's remaining percentage sits directly above its reset time, so the eye reads one right-hand column instead of two. Labels sit on the left; comparable numbers and reset times sit on clean right edges throughout. The provider pages carry no mark beside the provider name - the tab above already says which provider the page is.

The dropdown appears rather than animating open, and the same four action rows are present on every page. The size change between pages is instant too: `NSPopover.animates` governs both, and an animated resize was tried and measured - the height comes from the hosting controller's `preferredContentSize`, which NSPopover does not animate, so turning `animates` back on after the open bought no resize animation and would only have restored an animated close.

### Nothing moves

Two separate causes, both fixed structurally rather than case by case.

**Digit shape.** In a proportional font the digit `1` is narrower than a `4`, so two numbers with the same character count still take different widths and everything beside them shifts. Every changing number therefore renders with tabular figures: the popover and the Preferences window each apply `.monospacedDigit()` at their root, and the menu bar title - which AppKit draws, so it never saw either - sets `NSFont.monospacedDigitSystemFont` on the status item button.

**Digit count.** Tabular figures do not help when `9%` becomes `100%`. Every changing number also sits in a reserved, right-aligned column whose width is a constant in `Layout`.

This is about content moving *within* a page. The panel itself sizes to its page, so pages of different shapes have different heights - a short provider page is not padded out to the length of the Overview. What must not vary is the same page measured twice, and the width, which is fixed for every page.

The page area has a floor as well as a cap. `Layout.minContentHeight` is 256pt, measured as the page area of the ordinary two-window provider page - a session and a week, which is what Claude, Codex and Antigravity report - so a provider with one window or none rises to meet that page instead of snapping the panel shorter than the tab beside it. Every signed-in provider page therefore settles at 468pt, and only the pages that genuinely need more, Overview and the unavailable pages, are taller. Each page ends in a footer pushed down by a `Spacer`, so the space a missing window would have taken opens above the footer rather than leaving a hole under it, and the boundary note lands on the same line whatever the provider reports.

`LayoutStabilityTests` covers both halves, and `QUOTABAR_SELFTEST` reports the panel size for every page in the running app.

The approved mockups for all of this are committed in [`docs/design`](docs/design/README.md) and are the acceptance criteria for interface changes.

## First-launch preferences

Provider visibility used to be an empty exclusion set, which meant every provider quota-axi mentioned was switched on, including the ones that cannot be read at all.

The first successful snapshot now decides it once: providers with fresh, measurable quota start on, everything else starts off. The seed is computed from that snapshot rather than from a hard-coded provider list, so a machine signed into a different set of providers gets its own answer. After that seed, a later snapshot never turns a switch back on or off - the choices are the user's.

Everything else starts off or neutral: read-only refresh off, launch at login off and opt-in, refresh interval 2 minutes, menu bar mode Focused provider.

QuotaBar never reads the login-item status until the Preferences window is open, so ordinary startup and refresh never trigger a Background Task Management prompt.

## Session versus weekly

The headline number for a provider is its **session** window, the short rolling window that constrains day-to-day work on entry-tier plans.
The weekly window is secondary context and is always visible beneath it.

Every window a provider reports appears as its own row on the Overview and its own section on the provider's page, with its own label, its own remaining percent and its own reset time.
Nothing `quota-axi` reports for a shown provider is dropped.
A provider that is not signed in is off by default rather than dimmed in a list; turn it on in Preferences and it gets its own page, which states the real status instead of a fake zero.

Every percentage in the UI is **remaining**, and the header says so.

## Provider colors and marks

Brand colors, mark files and vendor names live in one table in `Sources/QuotaBarCore/BrandColors.swift`. Add a provider with one line:

```swift
"newprovider": ProviderBrand(
    hex: "#123456", iconResourceName: "ProviderIcon-newprovider", vendor: "New Provider"),
```

The marks are the vendors' real marks, carried as SVG files in `Sources/QuotaBar/Resources/ProviderMarks` and loaded as `NSImage` at run time. They came from the public [CodexBar](https://github.com/steipete/CodexBar) resource set. `build.sh` copies the generated `QuotaBar_QuotaBar.bundle` into the app and fails the build if it is missing, because without it the menu bar has no mark to draw. They are carried for personal use; distributing QuotaBar more widely needs a separate trademark review.

A provider with no mark of its own falls back to QuotaBar's own glyph rather than borrowing another vendor's artwork.

Colors are nudged toward readability only when a raw brand color falls below a 3:1 contrast floor against the menu bar background, which in practice affects the lighter colors on a light menu bar only. `BrandColorTests` asserts this floor for every provider in both appearances, and `ProviderMarkImageTests` asserts that every mark resource loads, draws ink in both appearances, is not a template image, and comes out in the expected brand color.

The information design was referenced from the public CodexBar app; no code was copied.

## Verifying a build

Three hooks print evidence from the built bundle without screenshots or any system permission:

```sh
QUOTABAR_SELFTEST=1 ./dist/QuotaBar.app/Contents/MacOS/QuotaBar   # data, marks, status item, schedule
QUOTABAR_VERIFY=1   ./dist/QuotaBar.app/Contents/MacOS/QuotaBar   # preferences window
QUOTABAR_RENDER=.artifacts/render ./dist/QuotaBar.app/Contents/MacOS/QuotaBar  # layout PNGs
```

`QUOTABAR_SELFTEST` prints every provider row and window it would render from live `quota-axi` output, the visibility seed, every mark's ink coverage and average color in both appearances, and then reads the **real** `NSStatusBarButton`: what image and title it was handed, and how much ink the live button actually draws in the mark region. That last check exists because the previous self-test rendered marks offscreen, passed, and still shipped a menu bar with no icon in it. It then opens the real popover, walks every page, and reports the panel size each one settles at, so a page that resizes the window shows up as a number rather than as a complaint. It also exercises the sticky selection end to end and restores the focus it borrowed.

`QUOTABAR_VERIFY` opens the real preferences window three times, including once after closing it, and reports whether it was visible, key and frontmost each time. It substitutes a stub for the login-item status so opening the window cannot trigger a system prompt, and says so in its output. Note that this hook runs at launch with no user interaction, and macOS 14 can refuse activation in that situation, so it may report `appActive=false`; the window is ordered front regardless and still appears.

`QUOTABAR_RENDER` draws the real views into PNGs with `ImageRenderer` so the layout can be looked at without capturing the screen. It draws Antigravity twice, as `provider-two-windows` and `provider-single-window`, because the short page is where the floor and the footer show and the two are meant to be held side by side. It also writes `menubar-backing.png`, a swatch of the menu bar mark at four backing strengths over a light menu bar, a dark one, and a bright and a busy wallpaper, for choosing that value by eye. Two limitations to know: `ImageRenderer` draws a `ScrollView` as an empty box, so these renders use the non-scrolling variant of the same views, and it draws AppKit-backed controls such as `Picker` and `Toggle` as a yellow placeholder rather than the control.

All three quit the app when they finish.

## Scope

- This package builds only the menu bar application.
- A Notification Center widget is deferred and no widget extension is included.
