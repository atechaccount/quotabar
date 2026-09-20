import Testing
@testable import QuotaBarCore

/// Covers the two things the captain saw go wrong: a percentage that measured the
/// wrong window, and a menu bar number with no provider attached to it.
struct HeadlineTests {
    private func provider(_ json: String) throws -> QuotaProvider {
        try #require(QuotaParser.decode(json).providers.first)
    }

    @Test
    func sessionWindowWinsOverALowerWeeklyWindow() throws {
        let json = """
        {"providers":[{"provider":"claude","state":{"status":"fresh"},
        "windows":[
          {"id":"five_hour","label":"session","kind":"session","percentRemaining":83,"windowSeconds":18000},
          {"id":"seven_day","label":"week","kind":"weekly","percentRemaining":50,"windowSeconds":604800}],
        "quotaSemantics":{"effectiveAvailability":[{"scope":"all_models","effectivePercentRemaining":50}]}}]}
        """
        let headline = try #require(provider(json).headline)

        #expect(headline.percentRemaining == 83)
        #expect(headline.isSession)
        #expect(headline.windowLabel == "session")
    }

    @Test
    func weeklyOnlyProviderReportsTheScopeItMeasured() throws {
        // Antigravity has no session window; its headline must name the pool it read.
        let json = """
        {"providers":[{"provider":"agy","state":{"status":"fresh"},
        "windows":[
          {"id":"gemini_weekly","label":"Gemini weekly","kind":"weekly","percentRemaining":1},
          {"id":"claude_gpt_weekly","label":"Claude/GPT weekly","kind":"weekly","percentRemaining":100}],
        "quotaSemantics":{"effectiveAvailability":[
          {"scope":"gemini","effectivePercentRemaining":1},
          {"scope":"claude_gpt","effectivePercentRemaining":100}]}}]}
        """
        let subject = try provider(json)
        let headline = try #require(subject.headline)

        #expect(headline.percentRemaining == 1)
        #expect(!headline.isSession)
        #expect(headline.windowLabel == "Gemini weekly")
        // Nothing reported may be dropped from the overview.
        #expect(subject.allWindows.count == 2)
    }

    @Test
    func sessionClassificationFallsBackToDurationThenNeverGuesses() throws {
        let json = """
        {"providers":[{"provider":"x","state":{"status":"fresh"},"windows":[
          {"id":"rolling","percentRemaining":40,"windowSeconds":3600},
          {"id":"monthly","percentRemaining":90,"windowSeconds":2592000}]}]}
        """
        let subject = try provider(json)

        #expect(subject.sessionWindow?.id == "rolling")
        #expect(subject.headline?.percentRemaining == 40)
        #expect(subject.headline?.isSession == true)
    }

    @Test
    func aProviderWithNoReadableWindowsHasNoHeadline() throws {
        let json = #"{"providers":[{"provider":"cursor","state":{"status":"auth_required"}}]}"#
        #expect(try provider(json).headline == nil)
    }
}

struct MenuBarReadoutTests {
    private let snapshot = try! QuotaParser.decode("""
    {"providers":[
      {"provider":"claude","label":"Claude","state":{"status":"fresh"},
       "windows":[{"id":"five_hour","label":"session","kind":"session","percentRemaining":83}]},
      {"provider":"codex","label":"Codex","state":{"status":"fresh"},
       "windows":[{"id":"five_hour","label":"session","kind":"session","percentRemaining":31}]},
      {"provider":"agy","label":"Antigravity","state":{"status":"fresh"},
       "windows":[{"id":"gemini_weekly","label":"Gemini weekly","kind":"weekly","percentRemaining":1}]},
      {"provider":"cursor","label":"Cursor","state":{"status":"auth_required"}}]}
    """)

    @Test
    func focusedProviderDrivesTheReadoutAndIsAlwaysAttributed() {
        let readout = MenuBarReadoutResolver.resolve(
            snapshot: snapshot, mode: .focusedProvider,
            focusedProvider: "claude", isVisible: { _ in true })

        #expect(readout.provider == "claude")
        #expect(readout.percentRemaining == 83)
        #expect(readout.windowLabel == "session")
        #expect(readout.accessibilityDescription == "QuotaBar, Claude session 83% remaining")
    }

    @Test
    func theDefaultFocusIsNeverJustWhicheverNumberIsLowest() {
        #expect(MenuBarReadoutResolver.defaultFocus(in: snapshot) == "claude")

        // Lowest-of-shown stays available, but only when explicitly chosen.
        let lowest = MenuBarReadoutResolver.resolve(
            snapshot: snapshot, mode: .lowestOfShown,
            focusedProvider: "claude", isVisible: { _ in true })
        #expect(lowest.provider == "agy")
        #expect(lowest.percentRemaining == 1)
    }

    @Test
    func defaultFocusSkipsAProviderThatIsNotSignedIn() throws {
        let signedOut = try QuotaParser.decode("""
        {"providers":[
          {"provider":"claude","state":{"status":"auth_required"}},
          {"provider":"codex","label":"Codex","state":{"status":"fresh"},
           "windows":[{"kind":"session","percentRemaining":31}]}]}
        """)
        #expect(MenuBarReadoutResolver.defaultFocus(in: signedOut) == "codex")
    }

    @Test
    func lowestOfShownRespectsHiddenProviders() {
        let readout = MenuBarReadoutResolver.resolve(
            snapshot: snapshot, mode: .lowestOfShown,
            focusedProvider: "claude", isVisible: { $0 != "agy" })

        #expect(readout.provider == "codex")
        #expect(readout.percentRemaining == 31)
    }

    @Test
    func aFocusedProviderThatCannotBeReadShowsItsMarkButNoFakeZero() {
        let readout = MenuBarReadoutResolver.resolve(
            snapshot: snapshot, mode: .focusedProvider,
            focusedProvider: "cursor", isVisible: { _ in true })

        #expect(readout.provider == "cursor")
        #expect(readout.percentRemaining == nil)
    }

    @Test
    func iconOnlyShowsNothingElse() {
        let readout = MenuBarReadoutResolver.resolve(
            snapshot: snapshot, mode: .iconOnly,
            focusedProvider: "claude", isVisible: { _ in true })

        #expect(readout == .empty)
        #expect(readout.accessibilityDescription == "QuotaBar")
    }
}
