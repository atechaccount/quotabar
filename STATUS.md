# Status

## In progress

- None.

## Waiting on user

- None.

## Next

- Show several providers in the menu bar at once on a larger screen. Named as out of scope for the appearance work and not built.
- The Overview reset countdown. Out of scope for the appearance work.
- Add real Limit Reset Credits once `quota-axi` reports that field. It reports a spending-credit balance, which is a different number, so nothing in the UI promises reset credits today.
- Build the separately scoped Notification Center widget when full Xcode is available. This is deferred follow-up work and no widget extension exists in this package.
- Investigate whether the ad-hoc-signed app sees fewer credential sources than an interactive shell; `auth_required` rows are expected and safe in the meantime.
- Review vendor mark licensing before distributing QuotaBar beyond personal use. The marks in `Sources/QuotaBar/Resources/ProviderMarks` are the vendors' own.

## Recent round

The menu bar icon sits closer to the percentage, and the spacing slider is gone.

- **The spacing setting never worked.** It was applied as `.kern` on the mark's text attachment, and TextKit ignores kerning on an attachment glyph: measured across the whole range the setting could reach, every value laid the item out to exactly the same width, to three decimal places. The captain was right that moving the slider did nothing, and right that the app could go tighter; the reason was the mechanism, not the app.
- **The gap is geometry now.** An attachment advances by its image and by nothing else, and bounds that differ from the image stretch the artwork, so the clear space after the mark is part of the mark's own image. `MenuBarMetrics.markTrailingMargin` is that space, 0.7pt, and `markTrailingTrim` crops the rest of the plate inset away.
- **Measured, not reasoned about.** The real limit is where the mark's rendered ink meets the first glyph of the readout, so both were rasterised at 32 samples per point across every face, every readout width and both ends of the mark size range. At the shipped mark size the ink-to-ink gap goes from 3.19pt to 2.19pt for the app's own glyph and from 4.56pt to 3.56pt for Claude's, whose artwork carries 1.36pt of its own padding. The tightest case the settings can reach - the app glyph, whose ink fills its box, in front of the `?` of an unknown readout, whose left bearing is the smallest of any leading glyph - still renders 1.06pt of clear space, two device pixels on a Retina display. That is the floor 0.7pt was chosen to hold.
- **The setting is gone, not hidden.** The stored `menuBarMarkGap` key, the slider and the `MenuBarAppearance` field are all removed, and an install that moved that slider has the dead key cleared on first launch - the same tidy-up the retired greyscale mark style does. Verified against the real preferences on this machine: the key was there before the run and absent after. The icon size setting is untouched.
- `MenuBarMetrics.markTrailingMargin` is a hard floor with no control in front of it, and `LayoutStabilityTests` plus the self-test's `menubargap` sweep - now `margin=` and `floorHeld=` - hold it there.

## Previous round

The overview rows now carry the reset countdown.

- **Each overview row says when its headline window comes back.** The countdown sits under the percentage and its window label, in the same reserved right-hand column, drawn by the same `QuotaFormatting.resetLine` the provider pages use - one implementation, not two. A provider that reports no reset time draws no line at all rather than a dash, because the row has no space to spend on a value nobody reported; the provider pages, which have a reserved line to fill, still say "No reset time".
- Measured before and after on the built bundle: the Overview page goes from 630pt to 663pt, exactly one caption line per row across three rows. The panel width holds at 430, every provider page still settles at its 468pt floor, and the self-test reports `oneWidth=true pagesThatChangedSize=none`. Neither `Layout.popoverWidth` nor `Layout.minContentHeight` nor `Layout.maxContentHeight` was touched.
- `OverviewResetTests` covers both cases by rasterising the row: with a reset it is one caption line taller, and without one the band that line would occupy is completely empty. It also checks every shape the countdown can take against the reserved column width, so none of them truncates.

## Round before that

**The menu bar item is smaller.** The mark and its number now come from one place, `MenuBarMetrics`: a design size each - the 20pt mark against the 13pt system font the item was first built at - and a single `scale` factor, shipped at 0.85, so the pair cannot drift out of proportion with each other. The mark is 17pt and the number 11pt, which takes the whole item from 78pt wide to 70pt. The number's weight steps up to medium to pay for the smaller size on a translucent menu bar. The backing plate's inset became a fraction of the side so it scales too, and the kern is derived from it, which keeps the whole mark-to-number gap on `MenuBarMetrics.gap` at any size; the gap itself is not scaled, because it is an optical minimum rather than a dimension.

Shipped as one better default rather than a sixth appearance setting. The five that landed last round are all matters of taste with no better answer; the size was simply too big, and one right size beats a control nobody should have to find.

**And the readout reserves its three digits properly.** The item already held one width, but the padding was trailing, so the number slid left inside that width as the quota fell and the percent sign went with it - 4% read as a shorter readout than 100% rather than the same one. The padding moved to the leading edge, which right-aligns the digits in a three-digit column and lands the percent sign in the same place at every value. Leading padding was tried and rejected once before, when the mark and the number were still separated by AppKit's own 15pt and the column opened on top of a gap that was already far too wide; the gap is 1.5pt now and the kern that sets it is applied to the mark rather than to the number, so the column starts hard against the mark and what sits in front of a short number is reserved room for the hundreds digit rather than spacing. The serif-face correction moved with it: the shortfall kern now lands on the pad run alone, because a range that reached over the digits would widen the number and move the very percent sign the column exists to hold.

Evidence after the change. `menubargap` now sweeps all four faces as well as both appearances and every digit count, because a smaller item is where the glyphs would first run into each other: `smallest=1.0pt at=monospaced/dark/100% touching=no`. It sweeps the readouts that fill the column rather than every digit count, because a shorter number now puts the column's empty room in front of its first digit by design, and measuring ink there would report the column and call it a gap; the full-width readouts are the tightest case regardless. The live status button reports `frame=70x22 drawn=yes`. A new `menubarcolumn` line reports the drawn item width and the percent sign's offset at 4%, 44% and 100% in both appearances and in all four faces: `oneWidth=true percentSignHeld=true` on every one of them. `menubar-backing.png` now draws the real status title rather than an approximation of it, and `menubar-column.png` draws those three values with a rule down the measured percent sign, so a percent sign that moved would leave the rule.

## The round before that

The menu bar item's appearance is the captain's to set rather than fixed in code. Every default is the presentation the app already had, so an untouched install looks exactly as it did.

- **Five settings, under Preferences > Menu bar appearance.** The icon in brand colour or greyscale; the backing covering nothing, the icon, or the icon and number together; the backing's colour and strength; the number's colour, white, black, matching the menu bar or custom; and the readout's face - system, rounded, monospaced or serif. Each is written under its own key, so one unreadable stored value cannot take the rest of the menu bar with it.
- **The decisions live in `MenuBarAppearance` in `QuotaBarCore`,** away from AppKit, which is what makes them testable: what each backing scope plates, what colour the mark and the number come out in, and which face the number is set in.
- **The wide plate is the status button's layer background.** A sublayer draws on top of the title AppKit renders into the layer's contents, and no image can reach behind text the button lays out itself. `QUOTABAR_SELFTEST` now sweeps every option through the real status item: `scope=markAndNumber ... layerAlpha=0.070 layerRadius=5.6`, greyscale drawing `markAvg=(0.47,0.47,0.47)`, and the item's width holding at 77pt across the sweep.
- **A reserved-width bug the font choice exposed.** `U+2007 FIGURE SPACE` is one digit wide in most faces but not in the serif one, so a 9% item came out narrower than a 100% one. `statusTitle` now measures both in the chosen face and kerns away the difference; the test asserts one width from 0% to 100% in every face.

## And the one before that

Two polish items after the captain ran the three-change build. Neither was a defect.

- **A short provider page no longer snaps the panel shorter.** The page area gained a floor, `Layout.minContentHeight`, measured at 256pt: the page area of the ordinary two-window provider page, a session and a week. Every signed-in provider page now settles at 468pt whether the provider reports two windows, one, or none, so switching between Claude and Antigravity resizes nothing. Pages that genuinely need more are untouched - Overview measured 696pt and the unavailable pages 631-731pt - so nothing is padded to the longest page. The alignment on the short page was the second half of it: each page now ends in a footer pushed down by a `Spacer`, so the space a missing window would have taken opens above the boundary note rather than leaving a hole beneath it, and the note lands on the same line on every provider page. `QUOTABAR_RENDER` draws Antigravity twice, with two windows and with one, for holding side by side.
- **The type came down again, to 0.85 against a 9.0pt floor.** Every step is smaller than it was at 0.9: 19 base draws at 16.0, 16 at 13.5, 14 at 12.0, 13 at 11.0, 12 at 10.0, 11 at 9.5, and the three smallest bases in use - 9.5, 10 and 10.5 - collapse onto the floor, which is exactly the group that collapsed before. The floor moved because it had to: base 11 is the secondary body size on the plan line, the account identity, the freshness sentence, the credits line and every reset time, and at 0.85 it computes to 9.35, so the old 9.5 floor would have clamped it into the fine print. 0.85 with a 9.0pt floor is the furthest this pair goes - anything smaller needs a floor under 9.0, which is too small to read in a menu bar panel.

## Earlier round

Three changes after the captain ran the build, plus a sharpening of the first.

- **The menu bar mark sits right next to its number.** The gap was 15pt and none of `imagePosition` or `imageHugsTitle` moved it - all four combinations measured at exactly 15.0pt, because that spacing is AppKit's own when a button carries `image` plus `title`. The mark now travels as a text attachment inside `attributedTitle`, which makes the gap typographic and ours to set. Measured 1.0-5.0pt across every digit count in both appearances, smallest 1.0pt, never touching.
- **The panel sizes to its page again.** A fixed height made every short provider page as long as the longest page in the set. An animated resize was investigated rather than assumed: `NSPopover.animates` governs the size transition as well as the open, but the height comes from the hosting controller's `preferredContentSize`, which NSPopover does not animate - measured `from=658 immediate=480 settled=480 transition=instant`. Turning `animates` on after the open would therefore buy no resize animation while restoring an animated close, so it stays off and the resize is instant.
- **One type scale.** Sizes now go through `Typography`, written as their design size and passed through a single factor with a floor for the fine print. The whole interface got about a tenth smaller.

The within-page layout-stability work is unchanged: tabular figures and reserved columns both stand, and the tests that guard them still pass.

## Earlier still

Six changes from the captain after running the built app.

- **Nothing moves when a number changes.** He diagnosed it exactly: a `1` is narrower than a `4` in a proportional font, so Claude and Codex laid out differently. Tabular figures are now the rule for every changing number - the popover root, the Preferences root, and the status item button, which AppKit draws and neither SwiftUI root reached. Only four call sites had them before; the freshness ages, the hidden-provider count, the credits line, the provider-state labels and the whole menu bar title did not. Digit *count* is handled separately by reserved columns and a fixed panel height, because tabular figures do not make `9%` as wide as `100%`. The self-test reports the panel size for every page: `overview=430x682 claude=430x682 codex=430x682 agy=430x682 ... stable=true`.
- **No mark beside the provider name** on the provider pages. The tab above already identifies the provider.
- **The window value sits above its reset time** rather than beside it, at the reset text's existing size.
- **The dropdown appears instead of animating open** (`NSPopover.animates = false`).
- **The menu bar mark has a faint backing plate** so a colored mark stays legible against a wallpaper showing through a translucent menu bar. The strength is deliberately barely-there; `menubar-backing.png` from the render hook shows four strengths over four backgrounds for choosing by eye.
- **A tab strip tint is offered but not shipped** (`Layout.tabStripTintOpacity` is 0). The render hook draws both variants.

## First round

The presentation layer was rebuilt against the approved design in `docs/design/`. The quota model, the refresh scheduler, the preferences store and the evidence hooks were kept.

- **The menu bar mark is fixed.** The SwiftUI `MenuBarExtra` was replaced by an AppKit `NSStatusItem` in `StatusItemController`. Its button gets a real `NSImage` of the provider's mark, sized for the menu bar, painted in the contrast-adjusted brand color with `isTemplate` off, plus the percentage as the title. It re-renders when the focused provider or the effective appearance changes. The old label passed a custom SwiftUI `Shape`, which the status item host dropped while keeping the `Text` - a percentage with no icon.
- **The self-test now reads the real status button.** It rasterises the live `NSStatusBarButton` and reports ink in the mark region, because the previous offscreen-only mark check passed while the real menu bar showed nothing.
- **Tabbed shell.** Overview plus one page per shown provider, replacing the rejected single flat column. The filled tab is the page; the outlined tab with the dot is the menu bar focus. Selecting a provider tab moves the menu bar focus; returning to Overview does not.
- **Real provider marks.** The hand-drawn geometry is gone. The vendors' own SVGs are carried as SwiftPM resources and loaded as `NSImage`; `build.sh` fails if the resource bundle is missing.
- **Right-aligned numbers.** Labels left, percentages and reset times on fixed right-aligned columns, on every page and in Preferences.
- **First-launch preferences.** Provider visibility is seeded once from the first measurable snapshot - fresh measurable providers on, everything else off - computed from the snapshot rather than a hard-coded provider list, and never overridden afterwards.
- **Provider pages.** A signed-in provider shows its account, plan, source and one section per reported window. An unavailable provider is hidden by default and, when turned on, states its real status and every source `quota-axi` tried, never a zero.

Verified on the built bundle against live `quota-axi` output: 11 providers reported, 3 shown and 8 correctly off after the seed; the real status button drew its mark with 300 ink pixels in the mark region alongside the title; the sticky selection held through a provider page and back to Overview; and the refresh schedule ticked at 32.7s and 31.1s against a 30s interval with no errors. A copy of the app under a throwaway bundle identifier confirmed the genuine first-launch seed: focus on Claude, three providers on, eight off.
