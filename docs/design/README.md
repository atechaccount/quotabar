# Approved design reference

These four HTML mockups are the approved reference for QuotaBar's current interface. They were reviewed and approved before the interface was built, and the implementation in `Sources/QuotaBar` follows them. Treat them as the acceptance criteria for any change to the popover, the provider pages, the Preferences window, or the menu bar item.

Open any file directly in a browser. Each one is self-contained: inline CSS, inline SVG, no script, no network fetch, no build step. Every screen is shown in both light and dark appearance side by side.

- [`mockups/overview.html`](mockups/overview.html) - the default page: the tab strip, the provider summaries, and the one quiet line pointing at the providers the Overview is not showing.
- [`mockups/provider-signed-in.html`](mockups/provider-signed-in.html) - a provider that is reporting quota: account and plan header, one section per window, solid meters, reset times on the right edge.
- [`mockups/provider-unavailable.html`](mockups/provider-unavailable.html) - a provider that cannot be read: the real status, the sources quota-axi actually tried, and QuotaBar's boundary. Never a zero.
- [`mockups/preferences.html`](mockups/preferences.html) - the Preferences window, including the first-launch posture for every switch.

[`design-review-report.md`](design-review-report.md) is the review that produced them. It carries the settled design specification, the first-launch preference defaults, the diagnosis of the missing menu bar mark, and the reasoning behind each decision. It is a snapshot of the review and is not updated as the code changes.

Two points the mockups encode that are easy to lose in a later edit:

- The filled tab is the page being looked at. The outlined tab with the dot is the provider driving the menu bar. They are different things, and moving back to Overview must not change the second one.
- Comparable numbers sit on clean right edges. Labels stay on the left.

The provider marks are the vendors' own, carried as SVG resources in `Sources/QuotaBar/Resources/ProviderMarks`. They are used here for personal use; distributing QuotaBar more widely needs a separate trademark review.
