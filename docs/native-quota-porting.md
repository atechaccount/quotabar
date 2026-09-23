# Porting a quota-axi update into the native Swift readers

QuotaBar's primary quota source for Claude, Codex, and Cursor is now a native Swift port of quota-axi 0.1.51, not the bundled Node runtime.
The bundled `quota-axi` executable (built by `Scripts/BuildQuotaAXI.sh`, pinned in `Scripts/quota-axi.version`) is kept only as a runtime fallback in `HybridQuotaSource`, used if the native readers ever throw outright.
The three native readers absorb their own failures exactly like quota-axi's own adapters do, so that fallback is not expected to activate in normal operation.

quota-axi is a dependency, not code QuotaBar owns.
When it releases an update that changes Claude, Codex, or Cursor behavior, re-port the affected pieces by hand using this map, rather than trying to keep the two in permanent lockstep.

## Where the Swift code lives

All of it is under `Sources/QuotaBarCore/NativeQuota/`.

## File map

Each row is a quota-axi 0.1.51 source file (from `npm pack quota-axi@0.1.51`, under `dist/src/`) and the Swift file that ports it.

| quota-axi source | Swift port | What to re-check on an update |
| --- | --- | --- |
| `providers/claude.js` | `NQClaudeReader.swift` | Credential discovery order, the OAuth usage/profile endpoints and headers, the `claude doctor` delegate contract, window normalization (`five_hour`/`seven_day`/`seven_day_opus`/`limits`/`extra_usage`), stale-cache eligibility windows. |
| `providers/codex.js` | `NQCodexReader.swift` | The two usage endpoints, the `auth.json` shape, JWT claim names, the `codex ... app-server` JSON-RPC probe (method names, `account/read`, `account/rateLimits/read`), window normalization including named/model-scoped limits. |
| `providers/cursor.js` | `NQCursorReader.swift` | The DashboardService RPC methods and their request/response shape, window normalization, the Grok Bot window, billing-cycle math. |
| `providers/cursor-cli-credential.js` (macOS branch only) | `NQCursorCliCredential.swift` | `cli-config.json` shape, the Keychain service/account names. |
| `providers/common.js` | `NQCommon.swift` | `withRemaining`, `successProvider`/`failedProvider`/`staleFromCache`, `statusFromError`. |
| `providers/delegated-refresh.js` | `NQDelegatedRefresh.swift` | The non-interactive environment forced on a delegate, the no-signal-on-timeout rule, the exit-code-to-attempt mapping. |
| `providers/claude.js`'s `liveClaudeRefreshBlocker`/`isLiveClaudeCodeProcess` | `NQDelegatedRefresh.swift` (`NQClaudeProcessGuard`) | The process-line matching rules that stand down a delegated refresh when Claude Code is already running. |
| `providers/credential-selection.js` | `NQCredentialSelection.swift` | The valid-then-expired ordering and the outcome-merge rules (a generic port, used by Codex). |
| `interpretation.js` (the `claude`/`codex`/`cursor` cases, `availability`, `boundConflict`, `staleSemantics`) | `NQInterpretation.swift` | Only the fields QuotaBarCore's `QuotaSemantics`/`EffectiveAvailability` actually decode are computed: `scope`, `status`, `effectivePercentRemaining`, `description`, `unresolvedWindowIds`. The pace/runway/selection detail quota-axi also publishes is dropped deliberately, matching what `QuotaParser`'s lossy decode already drops from the bundled JSON. |
| `lib/time.js` | `NQFoundation.swift` (`NQTime`) | `clampPercent`, `percentRemaining`, epoch/ISO parsing, `Retry-After` parsing. |
| `lib/secret.js` | `NQFoundation.swift` (`NQSecret`) | The literal-secret usability check (rejects `$`/`!`-prefixed and control-byte values). |
| `lib/process.js`, `lib/running-processes.js` | `NQProcess.swift` | Bounded child-process execution, `PATH` search, the `ps` invocation used by the process guard. |
| `lib/fs.js`, `lib/claude-profile.js` | `NQPaths.swift` | The quota-axi cache directory, Keychain access-marker paths, `claudeCredentialContextId`, Claude Code's own config-dir/secure-storage selectors. |
| `cache.js` (the claude/codex/cursor-relevant paths) | `NQCache.swift` | Reads and writes the *same* `~/.cache/quota-axi/quotas.json` file quota-axi itself uses, so the native reader and the bundled runtime interoperate. Entries for any other provider, or a non-default `accountKey`, are preserved untouched. |

## What was deliberately not ported

- **Every path that would require QuotaBar to actively refresh or rotate a token.** Codex and Cursor never refresh at all in quota-axi 0.1.51 (the stored expiry is advisory; the live endpoint alone decides), and this port copies that exactly. Claude's only refresh path is delegating to `claude doctor` under quota-axi's own concurrency guard; see `NQClaudeReader.swift`'s doc comment and `NQDelegatedRefresh.swift`.
- **`--allow-claude-inference` / `claude-native-quota.js`.** QuotaBar never passes that flag, so the branch is unreachable.
- **`--profile-only`.** QuotaBar never sets `CLAUDE_CONFIG_DIR`/`CODEX_HOME` in profile-only mode.
- **The Pi credential broker's OAuth-entry parsing** (`pi-codex-credential.js`). Only its "is there a Pi auth file at all" existence check is kept (`~/.pi/agent/auth.json` or `$PI_CODING_AGENT_DIR/auth.json`), so a machine without one reports exactly the `credentials_missing` skip quota-axi would. A user routing Codex through the separate Pi agent ecosystem is out of scope.
- **Multi-account discovery** (`discoverCodexAccounts` in codex.js). QuotaBar has always read one Codex account.
- **Other providers** (Copilot, Grok, Kimi, Z.AI, Antigravity, Alibaba, OpenCode Go, Command Code, MiniMax, MiMo, DeepSeek, OpenRouter, ElevenLabs). Out of scope for this port; their code in quota-axi is untouched and unused by QuotaBar now that the bundled runtime is a fallback rather than the primary source.

## Verifying a re-port

- Run `./test.sh`. Every ported parser and refresh-decision rule has a unit test under `Tests/QuotaBarCoreTests/NativeQuota/`.
- Run the side-by-side comparison hook against your own signed-in Claude and Codex accounts: `QUOTABAR_COMPARE_QUOTA=1 ./dist/QuotaBar.app/Contents/MacOS/QuotaBar` (documented in `verifying-a-build.md`). Run it a small bounded number of times, never in a loop; it makes two live requests per provider (native and bundled) each time.
- Cursor cannot be verified this way unless you have a signed-in Cursor install; `Tests/QuotaBarCoreTests/NativeQuota/NQCursorReaderTests.swift` covers it with fixtures instead.

## Cursor is unverified against a live account

Cursor was not signed in on the machine this port was built on (no `state.vscdb`, no CLI login).
`NQCursorReaderTests.swift` covers the normalization and credential-resolution logic against fixtures and against the real "nothing installed" case, but the live DashboardService request/response shape has not been checked against a real account.
If quota-axi's Cursor RPC shapes ever change, re-derive the fixtures from a real response before trusting this port's Cursor output.
