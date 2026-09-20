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

The presentation layer was rebuilt against the approved design in `docs/design/`. The quota model, the refresh scheduler, the preferences store and the evidence hooks were kept.

- **The menu bar mark is fixed.** The SwiftUI `MenuBarExtra` was replaced by an AppKit `NSStatusItem` in `StatusItemController`. Its button gets a real `NSImage` of the provider's mark, sized for the menu bar, painted in the contrast-adjusted brand color with `isTemplate` off, plus the percentage as the title. It re-renders when the focused provider or the effective appearance changes. The old label passed a custom SwiftUI `Shape`, which the status item host dropped while keeping the `Text` - a percentage with no icon.
- **The self-test now reads the real status button.** It rasterises the live `NSStatusBarButton` and reports ink in the mark region, because the previous offscreen-only mark check passed while the real menu bar showed nothing.
- **Tabbed shell.** Overview plus one page per shown provider, replacing the rejected single flat column. The filled tab is the page; the outlined tab with the dot is the menu bar focus. Selecting a provider tab moves the menu bar focus; returning to Overview does not.
- **Real provider marks.** The hand-drawn geometry is gone. The vendors' own SVGs are carried as SwiftPM resources and loaded as `NSImage`; `build.sh` fails if the resource bundle is missing.
- **Right-aligned numbers.** Labels left, percentages and reset times on fixed right-aligned columns, on every page and in Preferences.
- **First-launch preferences.** Provider visibility is seeded once from the first measurable snapshot - fresh measurable providers on, everything else off - computed from the snapshot rather than a hard-coded provider list, and never overridden afterwards.
- **Provider pages.** A signed-in provider shows its account, plan, source and one section per reported window. An unavailable provider is hidden by default and, when turned on, states its real status and every source `quota-axi` tried, never a zero.

Verified on the built bundle against live `quota-axi` output: 11 providers reported, 3 shown and 8 correctly off after the seed; the real status button drew its mark with 300 ink pixels in the mark region alongside the title; the sticky selection held through a provider page and back to Overview; and the refresh schedule ticked at 32.7s and 31.1s against a 30s interval with no errors. A copy of the app under a throwaway bundle identifier confirmed the genuine first-launch seed: focus on Claude, three providers on, eight off.
