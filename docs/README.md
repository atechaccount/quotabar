# QuotaBar documentation

How QuotaBar behaves and why, for contributors and agents. `../README.md` covers what it is, what it needs and how to build it.

- [`refresh.md`](refresh.md) - the refresh schedule, the read-only refresh preference, and the native-first/bundled-fallback quota source.
- [`native-quota-porting.md`](native-quota-porting.md) - the native Swift Claude/Codex/Cursor readers: the quota-axi source file each one ports, what was deliberately left out, and how to re-port an upgrade.
- [`menu-bar.md`](menu-bar.md) - the status item: what it draws, how it is sized, the appearance settings, the backing plate, and the sticky provider selection.
- [`pages.md`](pages.md) - the popover's pages, the type scale, and why nothing moves when a number changes.
- [`providers.md`](providers.md) - session versus weekly windows, brand colors, and provider marks.
- [`preferences.md`](preferences.md) - what every setting starts at on a first launch.
- [`verifying-a-build.md`](verifying-a-build.md) - the `QUOTABAR_SELFTEST`, `QUOTABAR_VERIFY` and `QUOTABAR_RENDER` hooks.
- [`design/`](design/README.md) - the approved mockups and the design review behind them. They are the acceptance criteria for interface changes.
