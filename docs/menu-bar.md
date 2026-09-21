# What the menu bar shows

The menu bar item is a plain AppKit `NSStatusItem`.
Its button gets a real `NSImage` of the focused provider's mark, painted in that provider's brand color with `isTemplate` left off, plus the percentage as the button title.

This is deliberate and load-bearing.
QuotaBar previously used SwiftUI's `MenuBarExtra` with a custom `Shape` in its label; the status item host keeps the `Text` from such a label and silently drops the shape, so the menu bar showed a bare percentage with no mark at all.
`StatusItemController` owns the status item, re-renders on every model change and on every appearance change, and `SelfTest` rasterises the live button to prove the mark is actually drawn.

The mark sits on a very faint rounded plate - by default a little white on a dark menu bar, a little black on a light one - so a colored mark stays legible when a bright or busy wallpaper shows through a translucent menu bar.
It is meant to read as the background settling slightly, never as a button.
What it covers, what colour it is and how strong it is are all settings; see below.

## How big the item is

The item's size lives in one place, `MenuBarMetrics`.
The mark and the number beside it are read as one object, so they are sized as one: a design size each - a 20pt mark against the 13pt system font, which is what the item was first built at - and a single `scale` factor that moves both.
The shipped factor is 0.85, which puts the mark at 17pt and the number at 11pt and takes the whole item from 78pt wide to 70pt.
The number's weight steps up to medium as it comes down in size, because thin small digits over a bright wallpaper are what a translucent menu bar takes away first; `menubar-backing.png` from the render hook draws the real item over a light menu bar, a dark one, and a bright and a busy wallpaper for checking that by eye.

This is deliberately separate from the popover's `Typography` factor.
The dropdown is QuotaBar's own surface; the status item sits in the system menu bar beside everybody else's, and the two are meant to be different sizes.
It is also deliberately not one of the appearance settings below: those are all matters of taste with no better answer, and the size is not - it was simply too big.

The gap between the mark and the number is not scaled with them.
It is an optical minimum rather than a dimension of the item, already as small as it can be without the glyphs running into each other, so `MenuBarMetrics.gap` stays put while the pair shrinks.
The backing plate's inset does scale, and the kern is derived from it, so the whole gap works out to `gap` at every size.

The title uses tabular figures and is padded to three digit widths with `U+2007 FIGURE SPACE` on the **leading** edge, so the item keeps one width from 0% to 100% and nothing to its left in the menu bar shuffles as the quota falls.
FIGURE SPACE is one digit wide in most faces but not in every one - the serif face draws it narrower - so `statusTitle` measures both in the chosen face and kerns the pad run, and only the pad run, to make up the difference.

Leading, because a fixed width is not the whole of it: with the padding trailing, the item measured the same at 4% and 100% but the number slid left inside that width as the quota fell, and the percent sign moved with it.
Right-aligning the digits in a three-digit column lands the percent sign in the same place at 4%, 44% and 100%, so 4% reads as the same readout as 100% rather than as a shorter one.

Leading padding was tried once before and rejected, and it is worth saying why it is back.
At the time the mark and the number were separated by AppKit's own ~15pt, so the column opened on top of a gap that was already far too wide and the readout drifted right away from its mark.
The default gap is now a tighter 1pt and the captain can adjust it; its lower bound comes from the mark's rendered trailing inset, so the glyphs cannot meet.
It is set by a kern on the *mark*, not on the number, so the column starts hard against the mark at every value.
What sits between the mark and a short number is the reserved room for the hundreds digit, not spacing.

`QUOTABAR_SELFTEST` reports this as `menubarcolumn`, per face: the drawn item width and the percent sign's offset at 4%, 44% and 100% in both appearances, with `oneWidth` and `percentSignHeld`.
`QUOTABAR_RENDER` writes `menubar-column.png`, which draws the real status title at those three values over a light menu bar and a dark one with a rule down the measured percent sign, so a percent sign that moved would leave the rule.

The mark travels inside the attributed title as a text attachment rather than in `button.image`.
That is not decoration: `button.image` plus `button.title` puts a fixed ~15pt of AppKit spacing between the two, and none of `imagePosition` or `imageHugsTitle` shifts it - all four combinations measure at exactly 15.0pt.
As an attachment the gap becomes a typographic one, set by `ProviderMarkImage.menuBarGap`.
The ink actually lands 1.0-4.0pt apart depending on face and appearance, because a typographic gap is the nominal one plus whatever sidebearing the mark and the digit bring.
`QUOTABAR_SELFTEST` sweeps every face in both appearances and reports the smallest and where it was, which must never reach zero.
It sweeps the readouts that fill the reserved column, not every digit count: a shorter number puts the column's empty room in front of its first digit on purpose, so measuring ink there would report the column and call it a gap, and the full-width readouts are the tightest case anyway.

- **Focused provider** (the default) shows one chosen provider and its session percentage.
- **Lowest of shown** shows whichever visible provider has the least left. This is available but is deliberately not the default, because the lowest number anywhere is rarely the one you are working against.
- **Icon only** shows the app mark alone.

## Appearance settings

How the item is drawn is under Preferences > Menu bar appearance, and every default is the presentation QuotaBar shipped with, so an untouched install is unchanged.
The decisions live in `MenuBarAppearance` in `QuotaBarCore`, away from AppKit, because they are the part worth testing; `ProviderMarkImage` and `StatusItemController` only carry the answers to the drawing calls.

- **Icon** - the provider mark in its brand colour, in black, or in white. Black and white are flat fills with no contrast adjustment at all: a black asked for on a dark menu bar is that black. This replaced a "greyscale" choice that drained the hue out of the brand colour and then lifted the result back to a readable contrast, so no two providers came out the same grey and none of them came out black or white. A stored greyscale setting migrates once, to white if the menu bar was dark when it was read and to black if it was light, and the resolved value is written back so a later launch in the other appearance does not move it again.
- **Backing** - none, behind the icon, or behind the icon and number together. The icon-only plate is drawn into the mark image. The wide one is the status item button's own **layer background**: a sublayer would draw on top of the title AppKit renders into the layer's contents, and no image can reach behind text the button lays out itself. Whichever scope is chosen, the mark keeps one size.
- **Backing colour** - match the menu bar, or a colour and strength of your own. Anything much past a tenth reads as a badge.
- **Number colour** - match the menu bar (the system label colour), white, black, or a colour of your own.
- **Readout font** - system, rounded, monospaced or serif. Each is a system font *design* applied to the monospaced-digit system font with the tabular-figure feature re-stated on the result, so every face keeps its digits one width.

`QUOTABAR_SELFTEST` puts each option through the real status item and prints `SELFTEST appearancesweep` lines with the drawn mark's average colour, the plate's alpha, corner radius and width, and the item's width, then restores the settings it borrowed.
`QUOTABAR_RENDER` writes `menubar-mark-style.png`, the three icon choices over a light menu bar and a dark one.

## The plate hugs the readout, and the item says when the panel is open

The plate that covers the mark and the number together is a layer of its own, inserted below the status button's layer in the button's superview.
It used to be the button's layer *background*, which could only ever fill the button's bounds - and a variable-length status item is about 8-10pt wider than its own title on each side, so the plate framed the readout instead of backing it.
A sublayer of the button is no good either: the button draws its title into its layer's contents and sublayers composite above that, so the plate would cover the number.
The plate is now placed against the title's measured width with `MenuBarMetrics.plateHugFraction` of the mark's side either side of it.
What it hugs is the reserved three-digit column, not the ink, so it keeps one width from 0% to 100%.
`QUOTABAR_SELFTEST` reports `platehug` per appearance - the item width, the plate width and the padding between them at 4%, 44% and 100%, with `onePlateWidth` - and `QUOTABAR_RENDER` writes `menubar-plate.png`, which draws the old full-bounds plate and the new one side by side with the backing colour turned up.

macOS draws its own highlight on a status item while the mouse is down, and none of it is QuotaBar's: `highlight(true)` leaves a `cacheDisplay` of the button byte-identical while changing the pixels on screen, so no colour, shape or inset of it is reachable and the single bit `NSStatusBarButton.highlight(_:)` is the whole of the control.
AppKit also does not keep that highlight on for the life of an `NSPopover` - with the panel up the cell reports itself unhighlighted - so without something of its own the item said nothing at all while its panel was open.
It now wears its plate at a stronger strength for as long as the panel is up, in the same rectangle and the same ink family as the backing, composited over whatever backing is set rather than replacing it; the scope that draws no plate otherwise still gets this one.
`QUOTABAR_SELFTEST` reports `openstate` with the plate shut, open and shut again, the measured `systemHighlightInAppDrawing` and whether the cell was highlighted while the panel was open.

## The sticky selection

Selecting a provider tab opens that provider's page **and** points the menu bar at it.
Selecting Overview only changes the page: the menu bar stays where it was.
The choice is written to `UserDefaults` on every change, so it survives closing the popover, moving back to Overview, quitting and relaunching.

Two edge cases are deliberate:

- Before any choice has been made, the first snapshot seeds the focus once, preferring a signed-in Claude, then Codex, then the first provider with a measurable headline. With nothing measurable, the menu bar shows QuotaBar's own glyph and no number.
- If the focused provider later signs out, its mark stays in the menu bar and only the number disappears. Hiding a provider in Preferences removes its tab but never rewrites the stored focus.
