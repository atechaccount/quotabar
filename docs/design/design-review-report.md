# QuotaBar UX mockups and findings

## Outcome

- Produced four self-contained HTML mockups with inline CSS and inline SVG assets.
- Covered the Overview page, a signed-in provider page, an unavailable provider page, Preferences, the menu-bar item, and side-by-side light and dark appearances.
- Kept all Swift sources unchanged because implementation is outside this investigation task.
- Iterated the mockups through Lavish feedback rounds until the captain approved the settled design, then closed the review loop.
- The approved revision uses real provider SVG assets, right-aligns comparable numeric values, hides unavailable providers by default, makes the sticky menu-bar provider selection explicit, removes pace estimates, uses solid progress bars, and omits the unsupported Limit Reset Credits block.

## Deliverables

- Overview: `/Users/durell/dev/Tools/firstmate/data/quotabar-ux-mockups/mockups/overview.html`
- Signed-in provider: `/Users/durell/dev/Tools/firstmate/data/quotabar-ux-mockups/mockups/provider-signed-in.html`
- Unavailable provider: `/Users/durell/dev/Tools/firstmate/data/quotabar-ux-mockups/mockups/provider-unavailable.html`
- Preferences: `/Users/durell/dev/Tools/firstmate/data/quotabar-ux-mockups/mockups/preferences.html`
- Every file is the exact approved revision, is self-contained, uses no script or network fetch, and opens directly in a browser with no build step.

## Reference study

- The requested local screenshot was not present at `/Users/durell/Downloads/Screenshot 2026-09-20 at 11.10.12 AM.png` when checked with `rg --files /Users/durell/Downloads`.
- Used the captain's detailed description together with CodexBar's public [UI documentation](https://github.com/steipete/CodexBar/blob/main/docs/ui.md), [public screenshot](https://github.com/steipete/CodexBar/blob/main/docs/codexbar.png), and public source instead of approximating the reference from memory.
- CodexBar's information architecture confirms a compact Overview plus provider-specific detail pages, a bounded provider summary instead of an unbounded flat list, direct switching at the top, and provider status/details below.
- CodexBar does not hand-draw provider marks in Swift.
- Its `Sources/CodexBar/Resources/ProviderIcon-*.svg` files are SwiftPM resources, and `Sources/CodexBar/ProviderBrandIcon.swift` loads them as `NSImage`, sizes them to 18 by 18 points, marks them as templates, and caches them.
- The mockups now embed the corresponding public CodexBar SVG geometry for Claude, Codex, Antigravity, Cursor, GitHub Copilot, Grok, Kimi, Alibaba Coding Plan, OpenCode Go, Command Code, and Z.AI.
- Each HTML file carries that geometry as inline SVG `<symbol>` definitions and renders it with local `<use>` elements, so none of the marks depends on a fetched image, font, script, or runtime package.
- The Overview chart mark remains an original non-vendor navigation glyph.
- These are vendor marks carried for personal use as requested, and broader redistribution should get a separate asset and trademark review.

## Real quota-axi data

- Ran `quota-axi --json --full` directly and designed against its real schema and provider states.
- The initial design sample was generated at `2026-09-20T15:24:02.920Z` and contained 11 providers.
- Claude was fresh on Pro with `service.5k7fv@simplelogin.com`, a 100 percent session window, and a 46 percent weekly window in that sample.
- Codex was fresh on Plus with `buy@durellgill.com`, a 91 percent session window, an 88 percent weekly window, and a spending-credit balance of zero in that sample.
- Antigravity was fresh from its CLI with Gemini weekly at 1 percent and Claude/GPT weekly at 100 percent.
- Cursor, GitHub Copilot, Grok, Kimi, Z.AI, and Command Code required authentication.
- Alibaba Coding Plan was unavailable because `bl-cli` was unavailable.
- OpenCode Go required authentication and reported unresolved rolling, weekly, and monthly semantics.
- A second snapshot at `2026-09-20T16:05:58.588Z` confirmed the same provider/state structure while live quota percentages changed, as expected for a static mockup using a captured sample.
- `Sources/QuotaBarCore/QuotaModels.swift:22-32` confirms the app can display provider identity, source, plan, account, windows, spending credits, attempts, state, and quota semantics.
- `Sources/QuotaBarCore/QuotaModels.swift:153-210` confirms each quota window supplies its label, used/remaining percentage, reset time, and cadence when available.
- No mockup field depends on contacting a provider API or reading credentials from QuotaBar itself.

## Settled design implementation specification

### Shared shell and navigation

- Use a compact popover page model instead of the rejected single flat column.
- Put a bounded tab switcher at the top with Overview followed by enabled providers.
- Give every provider tab its real mark and brand-color underline.
- Fill the tab for the page currently being viewed.
- Give the provider driving the menu bar a brand-color outline and small status dot so page selection and persistent menu-bar focus remain distinguishable.
- Selecting a provider tab opens its page and makes it the menu-bar focus.
- Selecting Overview changes only the page and leaves the menu-bar focus unchanged.
- Render the menu-bar preview above each light and dark mockup as a colored provider mark followed by its headline percentage when measurable.
- Keep Refresh, Preferences, About where shown, and Quit as stable bottom action rows with right-aligned keyboard shortcuts.

### Overview

- Make Overview the default page.
- Show only providers with fresh measurable quota in the first-launch top switcher and Overview.
- Keep each provider summary to its name, account/plan context, right-aligned headline percentage, solid session/weekly meters, and right-aligned values.
- Do not repeat provider icons inside the Overview rows because the top switcher already supplies provider identity.
- Replace the eight unavailable rows with one quiet `8 more providers` path to Preferences.
- In the approved example, Overview is the filled page tab while Claude retains the focus outline and dot, and the live menu-bar preview remains Claude at 100 percent.

### Signed-in provider

- Use the real provider mark, provider name, account, plan, source, and freshness header.
- Put labels on the left and comparable percentages and reset times on clean right edges.
- Show only quota windows the snapshot actually contains.
- Omit derived pace, deficit, runway, and session-count estimates from this design round.
- Omit Limit Reset Credits because quota-axi does not report that field.
- Keep refresh, Preferences, About, and Quit as stable action rows with shortcuts.
- In the approved example, Codex is both the filled page tab and outlined menu-bar focus, and the menu-bar preview shows its mark and 91 percent.

### Unavailable provider

- Hide this page by default.
- Show it only after the user explicitly enables that provider in Preferences.
- Never render a missing quota as zero.
- State the actual status, show the real sources quota-axi attempted, explain the QuotaBar boundary, and offer refresh or hiding the provider.
- The menu bar shows only the focused provider's mark when no measurable percentage exists, which matches `Sources/QuotaBarCore/MenuBarReadout.swift:79-93`.
- In the approved example, Cursor was manually enabled, is both the current page and remembered menu-bar focus, and therefore keeps its mark in the menu bar while the number disappears.

### Preferences

- Explain that provider switches control both the top switcher and Overview.
- Put current provider state next to each switch and use the same green, gray, amber, and red status language in the legend.
- Seed only Claude, Codex, and Antigravity on for the captured first-launch snapshot because they were fresh and measurable.
- Seed every unavailable, authentication-required, or unresolved provider off.
- Preserve user choices after the first availability-based seed instead of continuously overriding them.
- Keep Refresh interval, Read-only refresh, Menu bar Shows, Focused provider, Launch at login, and the full provider visibility list in one conventional Preferences window.
- Explain each control in place, including that read-only refresh can make data stale and that launch at login is opt-in.
- Show current provider state beside every switch and include a legend for Connected, Measurable, Sign-in required, CLI unavailable, and Unresolved windows.

## Sticky menu-bar provider selection

- This is a named design behavior to preserve, not new behavior to invent.
- The current app calls `model.focus(on:)` when the focused provider is selected at `Sources/QuotaBar/Views.swift:136-137` and `Sources/QuotaBar/Views.swift:293-296`.
- `Sources/QuotaBar/AppModel.swift:141-143` delegates that choice to Preferences.
- `Sources/QuotaBar/AppPreferences.swift:76-80` stores the provider, switches the menu-bar mode to `focusedProvider`, and marks the initial seed complete.
- `Sources/QuotaBar/AppPreferences.swift:34-36` writes every focused-provider change to `UserDefaults`, so the remembered choice survives closing the dropdown, moving to Overview, quitting, and relaunching the app.
- Before the user has chosen, `Sources/QuotaBar/AppPreferences.swift:63-74` performs a one-time seed from the first real snapshot.
- `Sources/QuotaBarCore/MenuBarReadout.swift:53-57` and `Sources/QuotaBarCore/MenuBarReadout.swift:96-106` prefer a fresh Claude, then a fresh Codex, then the first fresh provider with a measurable headline.
- If none exists, focus remains unset and `Sources/QuotaBar/Views.swift:25-34` displays the QuotaBar glyph with no percentage.
- If the remembered provider later signs out or becomes unavailable but remains in the snapshot, `Sources/QuotaBarCore/MenuBarReadout.swift:71-93` keeps that provider's mark and removes the percentage rather than silently switching providers or showing a fake zero.
- If the remembered provider disappears from the snapshot entirely, the resolver returns its empty readout at `Sources/QuotaBarCore/MenuBarReadout.swift:79`, so the QuotaBar glyph appears with no percentage until another provider is chosen.
- Hiding a provider removes its tab and Overview card, but the implementation must not silently rewrite the persisted focus as a side effect.
- The mockups encode the binding explicitly: Overview keeps Claude outlined while Overview is filled, the Codex page has Codex filled and outlined with a Codex menu-bar readout, and the unavailable Cursor page has Cursor filled and outlined with a mark-only Cursor readout.

## Missing menu-bar icon diagnosis

### Evidence

- `Sources/QuotaBar/QuotaBarApp.swift:9-17` creates a SwiftUI `MenuBarExtra` with `.window` style.
- `Sources/QuotaBar/Views.swift:19-38` gives that status item a custom `HStack` containing `ProviderMark` and `Text`.
- The provider mark is not a `Canvas`.
- `Sources/QuotaBar/ProviderMarkView.swift:19-168` implements it as a custom SwiftUI `Shape` filled with an appearance-adjusted brand color.
- Only the fallback QuotaBar glyph at `Sources/QuotaBar/Views.swift:41-59` uses `Canvas`.
- `Sources/QuotaBar/SelfTest.swift:71-123` renders each `ProviderMark` with `ImageRenderer` outside the status-item host and checks pixel coverage and average color.
- Running `QUOTABAR_SELFTEST=1 /Users/durell/.treehouse/quotabar-eebf1b/1/quotabar/dist/QuotaBar.app/Contents/MacOS/QuotaBar` exited zero and reported nonzero coverage plus the expected light/dark RGB for all 11 marks.
- The same self-test reported `menubar mode=focusedProvider focus=claude mark=claude percent=93%`, so model selection and label data were present.
- The built app still displays the percentage without the provider mark in the real menu bar, according to the observed user-facing failure.
- The self-test does not render the actual `MenuBarExtra` host, so it proves mark geometry and color but cannot prove status-item integration.

### Cause

- The established fault boundary is the SwiftUI `MenuBarExtra` label bridge, not the quota model, provider selection, mark geometry, mark fill, or contrast adjustment.
- QuotaBar supplies an arbitrary custom SwiftUI `Shape` where a native status item normally consumes an `NSImage` and optional title.
- The actual host preserves the `Text` but drops the custom shape.
- The hypothesis that template rasterization alone removes the mark is not supported because template processing should preserve a nonempty alpha silhouette even when it removes color.
- The precise private SwiftUI extraction mechanism is undocumented, but the integration boundary is isolated by the passing offscreen renderer and failing real status item.

### Can a macOS menu-bar item be full color?

- Yes.
- Apple documents that `NSStatusItem.button` is the `NSStatusBarButton` to customize with an image, title, target, and action: [NSStatusItem.button](https://developer.apple.com/documentation/appkit/nsstatusitem/button).
- Apple documents that an image with `isTemplate == true` must be black and clear and is processed by controls for context: [NSImage.isTemplate](https://developer.apple.com/documentation/appkit/nsimage/istemplate).
- A non-template `NSImage` therefore retains its supplied color instead of asking AppKit to tint it as a template.
- CodexBar itself uses an AppKit `NSStatusBarButton`, supplies its image and title explicitly, and sets generated usage icons to template images.
- CodexBar also sets warning-flash images to `isTemplate = false`, which is direct public-source evidence that its AppKit status-item path can carry non-template color imagery.
- eqMac's public status-item implementation likewise offers `classic`, `colored`, and `macOS` modes by toggling `image.isTemplate` before assigning `button.image`.
- There is no per-app user setting required to tint the item because image/template behavior belongs to the application.

### Recommended fix for the later implementation task

- Replace the custom SwiftUI status-label shape path with an explicit AppKit status-item image and title path.
- Load the real provider SVG as `NSImage`, size it for the menu bar, render the existing light/dark contrast-adjusted brand color into it, and set `isTemplate = false`.
- Assign the image to `NSStatusItem.button.image`, assign the quota string to `button.title`, and set `button.imagePosition = .imageLeft`.
- Update the pre-rendered image when the focused provider or effective appearance changes.
- Treat a SwiftUI `Image(nsImage:)` inside the current `MenuBarExtra` as a smaller implementation experiment, not the primary recommendation, because the current failure already sits at that host boundary.
- Keep a status-item integration test in addition to the existing standalone `ImageRenderer` self-test.
- The mockups retain a colored real provider mark beside the number because this AppKit route makes that target achievable.

## Preference inventory and first-launch posture

| Preference | Current default and reason | Recommended first launch | Mockup |
| --- | --- | --- | --- |
| Refresh interval | 120 seconds from `Sources/QuotaBar/AppPreferences.swift:52-54`; this is the middle practical polling interval and matches the app's existing scheduler assumptions. | Keep 2 minutes. | 2 minutes |
| Menu bar mode | `focusedProvider` from `Sources/QuotaBar/AppPreferences.swift:55-56`; `Sources/QuotaBarCore/MenuBarReadout.swift:3-18` explains that an unattributed lowest percentage is ambiguous. | Keep Focused provider. | Focused provider |
| Focused provider | Starts empty at `Sources/QuotaBar/AppPreferences.swift:57` and is seeded once from the first real snapshot at `Sources/QuotaBar/AppPreferences.swift:63-74`; preferred order is Claude then Codex at `Sources/QuotaBarCore/MenuBarReadout.swift:53-57`. | Seed the first fresh preferred provider, which was Claude in the captured sample, then preserve the user's choice. | Claude |
| Read-only refresh | `false` at `Sources/QuotaBar/AppPreferences.swift:58`; normal refresh allows quota-axi to renew credentials so quota remains fresh. | Keep off. | Off |
| Provider visibility | `hiddenProviders` starts empty at `Sources/QuotaBar/AppPreferences.swift:59`, and `isVisible` means not hidden at `Sources/QuotaBar/AppPreferences.swift:82-90`; therefore every reported provider is on even when signed out or unavailable. | Seed fresh measurable providers on and every other provider off after the first snapshot, then preserve user choices. | Claude, Codex, and Antigravity on; eight others off |
| Launch at login | QuotaBar stores no independent default; `LaunchAtLoginController` starts `notDetermined` at `Sources/QuotaBar/LaunchAtLoginController.swift:33-49` and reads the system login-item state when Preferences appears at `Sources/QuotaBar/Views.swift:453`. | Present off as the first-launch posture and require explicit opt-in. | Off |

- The captain's `everything enabled` observation comes specifically from the empty exclusion set for provider visibility.
- It is not backed by detection, freshness, account state, or measurable quota.
- The other boolean preference, read-only refresh, already defaults off.
- Launch at login is system-owned rather than defaulting on in QuotaBar.

### First-snapshot provider visibility seed

| Provider | Captured state | Recommended first launch |
| --- | --- | --- |
| Claude | Connected, fresh, measurable | On |
| Codex | Connected, fresh, measurable | On |
| Antigravity | Fresh and measurable without account identity | On |
| Alibaba Coding Plan | CLI unavailable | Off |
| Command Code | Sign-in required | Off |
| Cursor | Sign-in required | Off |
| GitHub Copilot | Sign-in required | Off |
| Grok | Sign-in required | Off |
| Kimi | Sign-in required | Off |
| OpenCode Go | Sign-in required with three unresolved windows | Off |
| Z.AI | Sign-in required | Off |

- Compute this seed once from the first successful snapshot rather than hard-coding these three provider names for every machine.
- After the seed, never override the user's provider switches when later snapshots change state.

## Reset-credit finding

- The CodexBar reference includes a Limit Reset Credits block, but quota-axi does not report a reset-credit count.
- The live Codex object reports `credits: { remaining: 0, unlimited: false, unit: "credits" }`, which is a spending-credit balance.
- `Sources/QuotaBar/Views.swift:282-289` already renders that spending-credit balance as remaining credits.
- Calling it Limit Reset Credits would promise a different field that does not exist.
- The block was removed from both light and dark signed-in mockups.
- Adding true limit-reset credits requires upstream quota-axi work and remains a follow-up.

## Validation and evidence commands

- `quota-axi --json --full > .artifacts/quota-current.json`
- `QUOTABAR_SELFTEST=1 /Users/durell/.treehouse/quotabar-eebf1b/1/quotabar/dist/QuotaBar.app/Contents/MacOS/QuotaBar > .artifacts/selftest.txt 2>&1`
- The self-test exited zero, reported 11 providers, 3 active providers, 8 inactive providers, nonzero mark coverage for every light/dark rendering, and no refresh error.
- `gh-axi api repos/steipete/CodexBar/contents/Sources/CodexBar/ProviderBrandIcon.swift --header 'Accept: application/vnd.github.raw+json' --full`
- `gh-axi api 'repos/steipete/CodexBar/git/trees/main?recursive=1' --jq '[.tree[] | select(.path | startswith("Sources/CodexBar/Resources/")) | .path]' --full`
- `npx ctx7@latest library AppKit 'NSStatusItem NSStatusBarButton image full color and NSImage isTemplate behavior'`
- `npx ctx7@latest docs /websites/developer_apple_appkit 'NSStatusItem NSStatusBarButton image rendering and NSImage isTemplate full-color versus template behavior'`
- Used `chrome-devtools-axi` to open every `file://` mockup, inspect the DOM and computed layout, verify real SVG symbols and uses, confirm right alignment, confirm no horizontal overflow, and capture the latest screenshots.
- Final DOM checks found no horizontal or internal-panel overflow in either appearance, matching light/dark sticky-focus states on every menu screen, and matching provider-mark references between each focused tab and its menu-bar preview.
- `rg -n '[[:blank:]]+$' mockups` found no trailing whitespace.
- `rg -n 'https?://|<script|reset credits|Limit Reset' mockups` found no network fetches, no scripts, and no reset-credit promise.
- `diff -rq mockups /Users/durell/dev/Tools/firstmate/data/quotabar-ux-mockups/mockups` confirmed the preserved handoff is byte-for-byte identical to the captain-approved review files.
- The Lavish session was ended through `lavish-axi end`, its feedback poll exited, and its local server was stopped after approval.
- `bin/fm-captain-hold.sh complete quotabar-ux-mockups --none` and `bin/fm-captain-hold.sh verify quotabar-ux-mockups` passed because the captain approved the design and no product choice remains unresolved in this review.
- No Swift build or test suite was run because this task changes only static mockups and explicitly excludes app implementation.
- No permission-triggering automation was used.
- No screen recording, Accessibility, Apple Events, notification, camera, microphone, login-item registration, or login-item status read was performed.
- The live launch-at-login state is intentionally unverified because the task forbids even the status read.

## Follow-up work outside this task

- Implement the settled design in Swift only after explicit authorization.
- Replace generic code-drawn app provider marks with the reviewed real provider assets in the implementation.
- Implement the AppKit status-item image/title path and add an integration-level status-item render check.
- Add true Limit Reset Credits only after quota-axi exposes that distinct data.
- Complete the deferred Notification Center widget separately.
- Investigate whether the ad-hoc-signed bundle sees fewer credential sources than an interactive shell separately.
- Review vendor mark licensing and trademark requirements before distributing beyond personal use.
