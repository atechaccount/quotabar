# Status

## In progress

- None.

## Waiting on user

- None.

## Next

- Add real Limit Reset Credits once `quota-axi` reports that field. It reports a spending-credit balance, which is a different number, so nothing in the UI promises reset credits today.
- Build the separately scoped Notification Center widget when full Xcode is available. This is deferred follow-up work and no widget extension exists in this package.
- Investigate whether the ad-hoc-signed app sees fewer credential sources than an interactive shell; `auth_required` rows are expected and safe in the meantime.
- Review vendor mark licensing before distributing QuotaBar beyond personal use. The marks in `Sources/QuotaBar/Resources/ProviderMarks` are the vendors' own.

## Recent round

Three changes after the captain ran the build, plus a sharpening of the first.

- **The menu bar mark sits right next to its number.** The gap was 15pt and none of `imagePosition` or `imageHugsTitle` moved it - all four combinations measured at exactly 15.0pt, because that spacing is AppKit's own when a button carries `image` plus `title`. The mark now travels as a text attachment inside `attributedTitle`, which makes the gap typographic and ours to set. Measured 1.0-5.0pt across every digit count in both appearances, smallest 1.0pt, never touching.
- **The panel sizes to its page again.** A fixed height made every short provider page as long as the longest page in the set. An animated resize was investigated rather than assumed: `NSPopover.animates` governs the size transition as well as the open, but the height comes from the hosting controller's `preferredContentSize`, which NSPopover does not animate - measured `from=658 immediate=480 settled=480 transition=instant`. Turning `animates` on after the open would therefore buy no resize animation while restoring an animated close, so it stays off and the resize is instant.
- **One type scale.** Sizes now go through `Typography`, written as their design size and passed through a single factor with a floor for the fine print. The whole interface got about a tenth smaller.

The within-page layout-stability work is unchanged: tabular figures and reserved columns both stand, and the tests that guard them still pass.

## Previous round

Six changes from the captain after running the built app.

- **Nothing moves when a number changes.** He diagnosed it exactly: a `1` is narrower than a `4` in a proportional font, so Claude and Codex laid out differently. Tabular figures are now the rule for every changing number - the popover root, the Preferences root, and the status item button, which AppKit draws and neither SwiftUI root reached. Only four call sites had them before; the freshness ages, the hidden-provider count, the credits line, the provider-state labels and the whole menu bar title did not. Digit *count* is handled separately by reserved columns and a fixed panel height, because tabular figures do not make `9%` as wide as `100%`. The self-test reports the panel size for every page: `overview=430x682 claude=430x682 codex=430x682 agy=430x682 ... stable=true`.
- **No mark beside the provider name** on the provider pages. The tab above already identifies the provider.
- **The window value sits above its reset time** rather than beside it, at the reset text's existing size.
- **The dropdown appears instead of animating open** (`NSPopover.animates = false`).
- **The menu bar mark has a faint backing plate** so a colored mark stays legible against a wallpaper showing through a translucent menu bar. The strength is deliberately barely-there; `menubar-backing.png` from the render hook shows four strengths over four backgrounds for choosing by eye.
- **A tab strip tint is offered but not shipped** (`Layout.tabStripTintOpacity` is 0). The render hook draws both variants.

## Earlier round

The presentation layer was rebuilt against the approved design in `docs/design/`. The quota model, the refresh scheduler, the preferences store and the evidence hooks were kept.

- **The menu bar mark is fixed.** The SwiftUI `MenuBarExtra` was replaced by an AppKit `NSStatusItem` in `StatusItemController`. Its button gets a real `NSImage` of the provider's mark, sized for the menu bar, painted in the contrast-adjusted brand color with `isTemplate` off, plus the percentage as the title. It re-renders when the focused provider or the effective appearance changes. The old label passed a custom SwiftUI `Shape`, which the status item host dropped while keeping the `Text` - a percentage with no icon.
- **The self-test now reads the real status button.** It rasterises the live `NSStatusBarButton` and reports ink in the mark region, because the previous offscreen-only mark check passed while the real menu bar showed nothing.
- **Tabbed shell.** Overview plus one page per shown provider, replacing the rejected single flat column. The filled tab is the page; the outlined tab with the dot is the menu bar focus. Selecting a provider tab moves the menu bar focus; returning to Overview does not.
- **Real provider marks.** The hand-drawn geometry is gone. The vendors' own SVGs are carried as SwiftPM resources and loaded as `NSImage`; `build.sh` fails if the resource bundle is missing.
- **Right-aligned numbers.** Labels left, percentages and reset times on fixed right-aligned columns, on every page and in Preferences.
- **First-launch preferences.** Provider visibility is seeded once from the first measurable snapshot - fresh measurable providers on, everything else off - computed from the snapshot rather than a hard-coded provider list, and never overridden afterwards.
- **Provider pages.** A signed-in provider shows its account, plan, source and one section per reported window. An unavailable provider is hidden by default and, when turned on, states its real status and every source `quota-axi` tried, never a zero.

Verified on the built bundle against live `quota-axi` output: 11 providers reported, 3 shown and 8 correctly off after the seed; the real status button drew its mark with 300 ink pixels in the mark region alongside the title; the sticky selection held through a provider page and back to Overview; and the refresh schedule ticked at 32.7s and 31.1s against a 30s interval with no errors. A copy of the app under a throwaway bundle identifier confirmed the genuine first-launch seed: focus on Claude, three providers on, eight off.
