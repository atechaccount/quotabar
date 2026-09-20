# Project guidance

- Read `STATUS.md` before substantial work.
- Treat `quota-axi --json --full` as the only quota source; never contact provider APIs or read credentials directly.
- Keep provider brand colors and marks in the one table in `Sources/QuotaBarCore/BrandColors.swift`; adding a provider is one line there.
- A provider's headline number is its session window, not its weekly or lowest window. See `QuotaProvider.headline`.
- Verify UI changes with the `QUOTABAR_VERIFY` and `QUOTABAR_SELFTEST` hooks documented in `README.md`; they print evidence without screenshots or system permissions.
- Run `./test.sh` and `./build.sh` before delivery.
- Keep the Notification Center widget out of this package until it is explicitly scoped and full Xcode is available.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
