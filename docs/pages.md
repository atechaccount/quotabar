# Pages

The popover is a tab strip over one page at a time, not a single flat column.

- **Overview** is the default page. It shows only providers with fresh, measurable quota: name, account and plan, a right-aligned headline percentage, and one solid meter per window. Everything else is one quiet line naming the count and pointing at Preferences.
- **A signed-in provider page** shows that provider's account, plan, source and freshness, then one section per window quota-axi actually reported, with the percentage and the reset time each on their own right edge.
- **An unavailable provider page** is hidden until the provider is turned on by hand. It states the real status, lists every source quota-axi tried and what came back, and says what QuotaBar will and will not do about it. It never renders a missing quota as zero.

Type is one scale: sizes are written as the base size they were designed at and passed through a single factor in `Typography`, with a floor that keeps the fine print readable.
Changing the whole interface's size is one constant.
The pair is 0.85 against a 9.0pt floor, which is as far down as it goes while the hierarchy survives: base 11 is the secondary body size - the plan line, the account identity, the freshness sentence, the credits line, every reset time - and at 0.85 it computes to 9.35, so a floor above 9.0 would clamp it into the fine print along with the three sizes below it.

On a provider page the window's remaining percentage sits directly above its reset time, so the eye reads one right-hand column instead of two.
Labels sit on the left; comparable numbers and reset times sit on clean right edges throughout.
The provider pages carry no mark beside the provider name - the tab above already says which provider the page is.

The dropdown appears rather than animating open, and the same four action rows are present on every page.
The size change between pages is instant too: `NSPopover.animates` governs both, and an animated resize was tried and measured - the height comes from the hosting controller's `preferredContentSize`, which NSPopover does not animate, so turning `animates` back on after the open bought no resize animation and would only have restored an animated close.

## Nothing moves

Two separate causes, both fixed structurally rather than case by case.

**Digit shape.** In a proportional font the digit `1` is narrower than a `4`, so two numbers with the same character count still take different widths and everything beside them shifts.
Every changing number therefore renders with tabular figures: the popover and the Preferences window each apply `.monospacedDigit()` at their root, and the menu bar title - which AppKit draws, so it never saw either - sets `NSFont.monospacedDigitSystemFont` on the status item button.

**Digit count.** Tabular figures do not help when `9%` becomes `100%`.
Every changing number also sits in a reserved, right-aligned column whose width is a constant in `Layout`.

This is about content moving *within* a page.
The panel itself sizes to its page, so pages of different shapes have different heights - a short provider page is not padded out to the length of the Overview.
What must not vary is the same page measured twice, and the width, which is fixed for every page.

The page area has a floor as well as a cap.
`Layout.minContentHeight` is 256pt, measured as the page area of the ordinary two-window provider page - a session and a week, which is what Claude, Codex and Antigravity report - so a provider with one window or none rises to meet that page instead of snapping the panel shorter than the tab beside it.
Every signed-in provider page therefore settles at 468pt, and only the pages that genuinely need more, Overview and the unavailable pages, are taller.
Each page ends in a footer pushed down by a `Spacer`, so the space a missing window would have taken opens above the footer rather than leaving a hole under it, and the boundary note lands on the same line whatever the provider reports.

`LayoutStabilityTests` covers both halves, and `QUOTABAR_SELFTEST` reports the panel size for every page in the running app.

The approved mockups for all of this are committed in [`docs/design`](design/README.md) and are the acceptance criteria for interface changes.
