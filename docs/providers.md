# Providers

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

The marks are the vendors' real marks, carried as SVG files in `Sources/QuotaBar/Resources/ProviderMarks` and loaded as `NSImage` at run time.
They came from the public [CodexBar](https://github.com/steipete/CodexBar) resource set.
`build.sh` copies the generated `QuotaBar_QuotaBar.bundle` into the app and fails the build if it is missing, because without it the menu bar has no mark to draw.
They are carried for personal use; distributing QuotaBar more widely needs a separate trademark review.

A provider with no mark of its own falls back to QuotaBar's own glyph rather than borrowing another vendor's artwork.

Colors are nudged toward readability only when a raw brand color falls below a 3:1 contrast floor against the menu bar background, which in practice affects the lighter colors on a light menu bar only.
`BrandColorTests` asserts this floor for every provider in both appearances, and `ProviderMarkImageTests` asserts that every mark resource loads, draws ink in both appearances, is not a template image, and comes out in the expected brand color.

The information design was referenced from the public CodexBar app; no code was copied.
