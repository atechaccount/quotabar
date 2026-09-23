# Verifying a build

Three hooks print evidence from the built bundle without screenshots or any system permission:

```sh
QUOTABAR_SELFTEST=1 ./dist/QuotaBar.app/Contents/MacOS/QuotaBar   # data, marks, status item, schedule
QUOTABAR_VERIFY=1   ./dist/QuotaBar.app/Contents/MacOS/QuotaBar   # preferences window
QUOTABAR_RENDER=.artifacts/render ./dist/QuotaBar.app/Contents/MacOS/QuotaBar  # layout PNGs
```

`QUOTABAR_SELFTEST` prints every provider row and window it would render from live `quota-axi` output, the visibility seed, every mark's ink coverage and average color in both appearances, and then reads the **real** `NSStatusBarButton`: what image and title it was handed, and how much ink the live button actually draws in the mark region.
That last check exists because the previous self-test rendered marks offscreen, passed, and still shipped a menu bar with no icon in it.
It then opens the real popover, walks every page, and reports the panel size each one settles at, so a page that resizes the window shows up as a number rather than as a complaint.
It also exercises the sticky selection end to end and restores the focus it borrowed.

`QUOTABAR_VERIFY` opens the real preferences window three times, including once after closing it, and reports whether it was visible, key and frontmost each time.
It substitutes a stub for the login-item status so opening the window cannot trigger a system prompt, and says so in its output.
Note that this hook runs at launch with no user interaction, and macOS 14 can refuse activation in that situation, so it may report `appActive=false`; the window is ordered front regardless and still appears.

`QUOTABAR_RENDER` draws the real views into PNGs with `ImageRenderer` so the layout can be looked at without capturing the screen.
It draws Antigravity twice, as `provider-two-windows` and `provider-single-window`, because the short page is where the floor and the footer show and the two are meant to be held side by side.
It also writes `menubar-backing.png`, the real menu bar item at four backing strengths over a light menu bar, a dark one, and a bright and a busy wallpaper, for choosing that value by eye, and `menubar-column.png`, the same item at 4%, 44% and 100% with a rule down the percent sign.
It writes `extra-usage-*-menubar.png` and `extra-usage-*-dropdown.png` for $4.20 spent against a $20 cap, $0 spent against a $50 cap, a spend with no cap, extra usage off, and the current Claude snapshot from `QuotaAXIRunner` in read-only mode.
The `RENDER extra-usage` lines print the menu bar and dropdown text for each case, and the live render reports an error if quota-axi is unavailable.
Two limitations to know: `ImageRenderer` draws a `ScrollView` as an empty box, so these renders use the non-scrolling variant of the same views, and it draws AppKit-backed controls such as `Picker` and `Toggle` as a yellow placeholder rather than the control.

All three quit the app when they finish.
