# Project guidance

- Read `STATUS.md` before substantial work.
- The approved interface reference is `docs/design/` - four HTML mockups plus the review report behind them. Treat the mockups as the acceptance criteria for any change to the popover, the provider pages, the Preferences window, or the menu bar item.
- Treat `quota-axi --json --full` as the only quota source; never contact provider APIs or read credentials directly.
- The menu bar item is an AppKit `NSStatusItem` in `Sources/QuotaBar/StatusItemController.swift`, not a SwiftUI `MenuBarExtra`. A `MenuBarExtra` label keeps its `Text` and silently drops a custom `Shape`, which is how the app once shipped with a percentage and no icon. Any change here must keep a real `NSImage` with `isTemplate` off on `button.image`.
- Provider brand colors, mark files and vendor names live in the one table in `Sources/QuotaBarCore/BrandColors.swift`; adding a provider is one line there plus its SVG in `Sources/QuotaBar/Resources/ProviderMarks`. Never hand-draw a stand-in mark.
- How the menu bar item looks is the captain's to set, not fixed in code. The options and every decision they drive live in `MenuBarAppearance` in `QuotaBarCore`, away from AppKit, and each default is the original presentation. The plate that covers mark and number together is the status button's own layer background: a sublayer draws on top of the title AppKit renders into the layer's contents, and no image reaches behind text the button lays out itself.
- A provider's headline number is its session window, not its weekly or lowest window. See `QuotaProvider.headline`.
- The reset countdown has one implementation, `QuotaFormatting.resetLine`, shared by the provider pages and the overview rows. It returns nil when nothing was reported, so a caller with no room draws nothing and a caller with a reserved line says so in words.
- Selecting a provider tab also points the menu bar at it; selecting Overview must not. The stored focus is never rewritten as a side effect of hiding a provider.
- Labels go left; comparable numbers and reset times go on fixed right-aligned columns. The column widths are in `Layout` in `Sources/QuotaBar/Views.swift`.
- Nothing in the interface may move when a number changes *within a page*. Two causes, both already handled structurally: digit shape needs tabular figures (root `.monospacedDigit()` on the popover and on Preferences, `NSFont.monospacedDigitSystemFont` on the status item button, which AppKit draws and neither SwiftUI root reaches), and digit count needs a reserved column or a padded field. The panel itself sizes to its page on purpose, between `Layout.minContentHeight` and `Layout.maxContentHeight`; what must hold is one width for every page and one size per page. The floor is the ordinary two-window provider page, so a provider reporting fewer windows does not shrink the panel, and each page ends in a `Spacer`-pushed footer so the slack opens above it. `LayoutStabilityTests` and the `panelsize` line of the self-test guard this.
- The menu bar mark is a text attachment in `button.attributedTitle`, not `button.image`. `button.image` plus `button.title` pins ~15pt of AppKit spacing between mark and number that no `imagePosition` or `imageHugsTitle` combination changes. Keep the mark reachable via `StatusItemController.markImage(in:)`, which is what guards against the original no-icon bug.
- Font sizes go through `Typography` in `Sources/QuotaBar/Views.swift`, never as literals. One factor scales the whole interface, against a floor. Change the factor and the floor together: walk every base in use past the floor first, because a factor that pushes base 11 - the secondary body size - onto the floor flattens it into the fine print.
- The menu bar item has its own scale, `MenuBarMetrics` in `Sources/QuotaBar/MenuBarMetrics.swift`, because it sits in the system menu bar rather than in QuotaBar's own surface. The mark and its number are sized from that one factor so they cannot drift out of proportion; the mark-to-number gap is deliberately not scaled with them. Size is not one of the `MenuBarAppearance` settings.
- The menu bar readout is padded to three digit widths on the **leading** edge, so the digits right-align and the percent sign holds one position from 4% to 100%. One width is not enough on its own: with trailing padding the item measured the same and the number still slid inside it. Keep the kern that closes the mark-to-number gap on the mark, never on the number, or the column turns back into spacing. `menubarcolumn` in the self-test and `menubar-column.png` from the render hook are the evidence.
- A new view that renders a changing number belongs under one of those two roots, or it needs its own tabular-figure setting.
- Provider visibility is seeded once from the first measurable snapshot and never overridden afterwards. See `ProviderVisibilitySeed`.
- Verify UI changes with the `QUOTABAR_SELFTEST`, `QUOTABAR_VERIFY` and `QUOTABAR_RENDER` hooks documented in `README.md`; they print evidence without screenshots or system permissions. The self-test must keep reading the real status button: an offscreen-only mark check passed while the real menu bar was empty.
- Never read the login-item status outside an open Preferences window, and never register a login item unprompted. Both trip a system permission dialog.
- Tests and the render hook use `InMemoryPreferenceStore`, never a scratch `UserDefaults` suite, which leaves a plist in `~/Library/Preferences` on every run.
- Run `./test.sh` and `./build.sh` before delivery.
- Keep the Notification Center widget out of this package until it is explicitly scoped and full Xcode is available.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
