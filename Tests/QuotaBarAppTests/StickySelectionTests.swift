import AppKit
import QuotaBarCore
import Testing
@testable import QuotaBar

/// The behaviour the captain described: open the dropdown, pick Claude, go back
/// to Overview, and the menu bar keeps showing Claude until something else is
/// picked - including after a quit and relaunch.
@MainActor
struct StickyMenuBarSelectionTests {
    private let snapshot = try! QuotaParser.decode("""
    {"providers":[
      {"provider":"claude","label":"Claude","plan":"pro","account":{"email":"a@b.c"},
       "state":{"status":"fresh"},
       "windows":[{"kind":"session","label":"session","percentRemaining":84}]},
      {"provider":"codex","label":"Codex","plan":"plus","account":{"email":"d@e.f"},
       "state":{"status":"fresh"},
       "windows":[{"kind":"session","label":"session","percentRemaining":14}]},
      {"provider":"agy","label":"Antigravity","source":"cli","state":{"status":"fresh"},
       "windows":[{"id":"gemini_weekly","label":"Gemini weekly","kind":"weekly","percentRemaining":1}]},
      {"provider":"cursor","label":"Cursor","state":{"status":"auth_required"}}]}
    """)

    /// In memory on purpose: a scratch `UserDefaults` suite writes a real plist
    /// into `~/Library/Preferences` for every test run.
    private func scratchDefaults() -> PreferenceStore {
        InMemoryPreferenceStore()
    }

    private func model(_ defaults: PreferenceStore) -> AppModel {
        AppModel(
            startRefreshing: false,
            preferences: AppPreferences(defaults: defaults),
            snapshot: snapshot)
    }

    @Test
    func choosingAProviderPageAlsoMovesTheMenuBar() {
        let subject = model(scratchDefaults())
        subject.select(.provider("codex"))

        #expect(subject.resolvedPage == .provider("codex"))
        #expect(subject.preferences.focusedProvider == "codex")
        #expect(subject.menuBarReadout.provider == "codex")
        #expect(subject.menuBarReadout.percentRemaining == 14)
    }

    @Test
    func goingBackToOverviewLeavesTheMenuBarWhereItWas() {
        let subject = model(scratchDefaults())
        subject.select(.provider("claude"))
        subject.select(.overview)

        #expect(subject.resolvedPage == .overview)
        #expect(subject.preferences.focusedProvider == "claude")
        #expect(subject.menuBarReadout.provider == "claude")
        #expect(subject.menuBarReadout.percentRemaining == 84)
    }

    @Test
    func theChoiceSurvivesQuitAndRelaunch() {
        let defaults = scratchDefaults()
        model(defaults).select(.provider("agy"))

        // A second model over the same defaults is what a relaunch looks like.
        let relaunched = model(defaults)
        #expect(relaunched.preferences.focusedProvider == "agy")
        #expect(relaunched.menuBarReadout.provider == "agy")
        #expect(relaunched.resolvedPage == .overview, "a relaunch opens on Overview")
    }

    /// Before any choice, the seed picks a provider actually in use rather than
    /// whichever number is lowest.
    @Test
    func beforeAnyChoiceTheFirstSnapshotSeedsTheFocusOnce() {
        let defaults = scratchDefaults()
        let preferences = AppPreferences(defaults: defaults)
        #expect(preferences.focusedProvider == "")

        preferences.seedFocusIfNeeded(from: snapshot)
        #expect(preferences.focusedProvider == "claude")

        // A later snapshot never re-seeds over the user's own choice.
        preferences.focus(on: "codex")
        preferences.seedFocusIfNeeded(from: snapshot)
        #expect(preferences.focusedProvider == "codex")
    }

    /// With no focus at all the menu bar shows QuotaBar's own glyph and no
    /// number, never a borrowed mark or a fake zero.
    @Test
    func withNoFocusTheMenuBarShowsTheAppGlyphAndNoNumber() {
        let subject = model(scratchDefaults())
        #expect(subject.preferences.focusedProvider == "")
        #expect(subject.menuBarReadout.provider == nil)
        #expect(subject.menuBarReadout.percentRemaining == nil)
    }

    /// A remembered provider that signs out keeps its mark in the menu bar and
    /// loses only the number.
    @Test
    func aFocusedProviderThatGoesUnavailableKeepsItsMark() {
        let subject = model(scratchDefaults())
        subject.select(.provider("cursor"))

        #expect(subject.menuBarReadout.provider == "cursor")
        #expect(subject.menuBarReadout.percentRemaining == nil)
    }

    /// Hiding a provider takes away its tab. It must not quietly rewrite the
    /// stored focus, because that would discard a choice made on purpose.
    @Test
    func hidingAProviderDoesNotRewriteTheStoredFocus() {
        let subject = model(scratchDefaults())
        subject.select(.provider("codex"))
        subject.preferences.setVisible(false, provider: "codex")

        #expect(subject.preferences.focusedProvider == "codex", "the stored choice was rewritten")
        #expect(!subject.tabProviders.contains { $0.provider == "codex" })
        #expect(subject.resolvedPage == .overview, "the page fell back without losing the focus")
        // Hidden from the switcher, but still the attributed menu bar readout.
        #expect(subject.menuBarReadout.provider == "codex")

        subject.preferences.setVisible(true, provider: "codex")
        #expect(subject.resolvedPage == .provider("codex"), "the page came back")
    }
}

/// The tab strip and the Overview list, which the captain sees before anything
/// else.
@MainActor
struct MenuShellTests {
    private let snapshot = try! QuotaParser.decode("""
    {"providers":[
      {"provider":"agy","label":"Antigravity","source":"cli","state":{"status":"fresh"},
       "windows":[{"id":"gemini_weekly","label":"Gemini weekly","kind":"weekly","percentRemaining":1}]},
      {"provider":"codex","label":"Codex","account":{"email":"d@e.f"},"state":{"status":"fresh"},
       "windows":[{"kind":"session","percentRemaining":14}]},
      {"provider":"claude","label":"Claude","account":{"email":"a@b.c"},"state":{"status":"fresh"},
       "windows":[{"kind":"session","percentRemaining":84}]},
      {"provider":"cursor","label":"Cursor","state":{"status":"auth_required"}},
      {"provider":"alibaba","label":"Alibaba Coding Plan",
       "state":{"status":"unavailable","error":"bl_cli_unavailable"}}]}
    """)

    private func model() -> AppModel {
        let preferences = AppPreferences(defaults: InMemoryPreferenceStore())
        preferences.seedVisibilityIfNeeded(from: snapshot)
        return AppModel(startRefreshing: false, preferences: preferences, snapshot: snapshot)
    }

    @Test
    func onlyMeasurableProvidersAppearAfterTheFirstSeed() {
        let subject = model()
        #expect(subject.tabProviders.map(\.provider) == ["claude", "codex", "agy"])
        #expect(subject.overviewProviders.map(\.provider) == ["claude", "codex", "agy"])
        #expect(subject.providersNotShown.map(\.provider).sorted() == ["alibaba", "cursor"])
    }

    /// The strip must not reshuffle under the pointer when the menu bar focus
    /// moves, so its order is deliberately not focus-first.
    @Test
    func theTabOrderDoesNotFollowTheMenuBarFocus() {
        let subject = model()
        let before = subject.tabProviders.map(\.provider)
        subject.select(.provider("agy"))
        #expect(subject.tabProviders.map(\.provider) == before)
    }

    /// A provider the user turns on by hand gets a tab even though it cannot be
    /// read, and lands after the measurable ones.
    @Test
    func aManuallyEnabledUnavailableProviderGetsItsOwnTabLast() {
        let subject = model()
        subject.preferences.setVisible(true, provider: "cursor")

        #expect(subject.tabProviders.map(\.provider) == ["claude", "codex", "agy", "cursor"])
        #expect(subject.overviewProviders.map(\.provider) == ["claude", "codex", "agy"])
        #expect(subject.providersNotShown.map(\.provider) == ["alibaba", "cursor"])
    }
}
