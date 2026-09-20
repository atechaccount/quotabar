# Project guidance

- Read `STATUS.md` before substantial work.
- Treat `quota-axi --json --full` as the only quota source; never contact provider APIs or read credentials directly.
- Keep provider colors in `Sources/QuotaBarCore/BrandColors.swift`.
- Run `./test.sh` and `./build.sh` before delivery.
- Keep the Notification Center widget out of this package until it is explicitly scoped and full Xcode is available.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
