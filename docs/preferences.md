# First-launch preferences

Provider visibility used to be an empty exclusion set, which meant every provider quota-axi mentioned was switched on, including the ones that cannot be read at all.

The first successful snapshot now decides it once: providers with fresh, measurable quota start on, everything else starts off.
The seed is computed from that snapshot rather than from a hard-coded provider list, so a machine signed into a different set of providers gets its own answer.
After that seed, a later snapshot never turns a switch back on or off - the choices are the user's.

Everything else starts off or neutral: read-only refresh off, launch at login off and opt-in, refresh interval 2 minutes, menu bar mode Focused provider.

QuotaBar never reads the login-item status until the Preferences window is open, so ordinary startup and refresh never trigger a Background Task Management prompt.
