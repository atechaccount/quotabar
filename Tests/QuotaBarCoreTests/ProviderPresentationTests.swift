import Testing
@testable import QuotaBarCore

/// The Preferences legend, the provider pages and the Overview all describe the
/// same five states, so the classification behind them is tested once here.
struct ProviderAvailabilityTests {
    private func provider(_ json: String) throws -> QuotaProvider {
        try #require(QuotaParser.decode(json).providers.first)
    }

    @Test
    func freshQuotaWithAnAccountIsConnected() throws {
        let subject = try provider("""
        {"providers":[{"provider":"claude","label":"Claude","plan":"pro",
          "account":{"email":"someone@example.com"},"state":{"status":"fresh"},
          "windows":[{"kind":"session","label":"session","percentRemaining":84}]}]}
        """)
        #expect(subject.availability == .connected)
        #expect(subject.availability.isMeasurable)
        #expect(subject.overviewContext == "Pro · someone@example.com")
        #expect(subject.planDescription == "Pro plan")
        #expect(subject.accountIdentity == "someone@example.com")
    }

    /// Antigravity reports real quota with no identity behind it. It is
    /// measurable, and the Overview says so rather than inventing an account.
    @Test
    func freshQuotaWithoutAnAccountIsMeasurable() throws {
        let subject = try provider("""
        {"providers":[{"provider":"agy","label":"Antigravity","source":"cli",
          "state":{"status":"fresh"},
          "windows":[{"id":"gemini_weekly","label":"Gemini weekly","kind":"weekly","percentRemaining":1}]}]}
        """)
        #expect(subject.availability == .measurable)
        #expect(subject.availability.isMeasurable)
        #expect(subject.overviewContext == "CLI · No account identity")
        #expect(subject.accountIdentity == "No account identity")
        #expect(subject.planDescription == nil)
    }

    @Test
    func aMissingCommandLineToolIsReportedBeforeAMissingSignIn() throws {
        let subject = try provider("""
        {"providers":[{"provider":"alibaba","label":"Alibaba Coding Plan","source":"unavailable",
          "state":{"status":"unavailable","error":"bl_cli_unavailable","sourcesTried":["bl-cli"]},
          "attempts":[{"source":"bl-cli","status":"skipped","error":"bl_cli_unavailable"}]}]}
        """)
        #expect(subject.availability == .cliUnavailable)
        #expect(subject.availability.label == "CLI unavailable")
        #expect(subject.availability.tone == .warning)
        #expect(subject.unavailableGuidance.contains("command-line tool"))
    }

    /// OpenCode Go is both signed out and unmeasurable. Saying "sign-in
    /// required" alone would hide the part a sign-in will not fix.
    @Test
    func unresolvedWindowsWinOverAPlainSignIn() throws {
        let subject = try provider("""
        {"providers":[{"provider":"opencode-go","label":"OpenCode Go","source":"api",
          "state":{"status":"auth_required","error":"opencode_go_credential_unavailable"},
          "quotaSemantics":{"status":"partial","unresolvedWindowIds":["rolling","weekly","monthly"]}}]}
        """)
        #expect(subject.availability == .unresolvedWindows(count: 3))
        #expect(subject.availability.label == "3 unresolved windows")
        #expect(!subject.availability.isMeasurable)
        #expect(subject.unavailableHeadline == "Quota windows unresolved")
    }

    @Test
    func aSignedOutProviderSaysSoAndNeverReadsAsZero() throws {
        let subject = try provider("""
        {"providers":[{"provider":"cursor","label":"Cursor","source":"unavailable",
          "state":{"status":"auth_required","error":"Cursor sign-in required",
                   "sourcesTried":["state-vscdb","cli-keychain"]},
          "attempts":[{"source":"state-vscdb","status":"skipped","error":"credentials_missing"},
                      {"source":"cli-keychain","status":"skipped","error":"credentials_missing"}],
          "quotaSemantics":{"status":"unknown","effectiveAvailability":[]}}]}
        """)
        #expect(subject.availability == .signInRequired)
        #expect(subject.headline == nil)
        #expect(subject.unavailableHeadline == "No quota data yet")
        #expect(subject.unavailableGuidance.contains("Sign in through Cursor"))

        let diagnostics = subject.sourceDiagnostics
        #expect(diagnostics.count == 2)
        #expect(diagnostics[0].sourceID == "state-vscdb")
        #expect(diagnostics[0].title == "Application state database")
        #expect(diagnostics[0].outcome == "No credentials")
        #expect(diagnostics[1].title == "CLI keychain")
    }

    /// A provider reporting only `sourcesTried` still gets a diagnostics table,
    /// because "we tried nothing" would be a lie about what quota-axi did.
    @Test
    func diagnosticsFallBackToTheSourcesQuotaAxiListed() throws {
        let subject = try provider("""
        {"providers":[{"provider":"grok","label":"Grok",
          "state":{"status":"auth_required","error":"credentials_missing",
                   "sourcesTried":["auth-json","pi:xai"]}}]}
        """)
        let diagnostics = subject.sourceDiagnostics
        #expect(diagnostics.map(\.sourceID) == ["auth-json", "pi:xai"])
        #expect(diagnostics[1].title == "pi credential store (xai)")
        #expect(diagnostics.allSatisfy { $0.outcome == "No credentials" })
    }
}

struct ProviderPresentationVocabularyTests {
    @Test
    func unknownSourcesAreHumanizedRatherThanHidden() {
        #expect(ProviderPresentation.humanizeSourceID("brand-new-source") == "Brand new source")
        #expect(ProviderPresentation.humanizeSourceID(nil) == "Unknown source")
        #expect(ProviderPresentation.humanizeSourceID("env:SOME_KEY")
            == "Environment variable SOME_KEY")
        #expect(ProviderPresentation.humanizeSourceID("gh:hosts.yml") == "GitHub CLI (hosts.yml)")
    }

    @Test
    func outcomesReadAsWordsNotErrorCodes() {
        #expect(ProviderPresentation.humanizeOutcome(status: "skipped", error: "credentials_missing")
            == "No credentials")
        #expect(ProviderPresentation.humanizeOutcome(status: "skipped", error: "bl_cli_unavailable")
            == "Not installed")
        #expect(ProviderPresentation.humanizeOutcome(status: "success", error: nil) == "Succeeded")
        #expect(ProviderPresentation.humanizeOutcome(status: nil, error: nil) == "No result")
    }

    @Test
    func plansAreCapitalizedWithoutManglingShortNames() {
        #expect(ProviderPresentation.humanizePlan("pro") == "Pro")
        #expect(ProviderPresentation.humanizePlan("plus") == "Plus")
        #expect(ProviderPresentation.humanizePlan("business") == "Business")
    }
}

/// The answer to "why is everything enabled?": the first snapshot decides it,
/// from what quota-axi could actually measure, and only once.
struct ProviderVisibilitySeedTests {
    private let firstLaunch = try! QuotaParser.decode("""
    {"providers":[
      {"provider":"claude","state":{"status":"fresh"},"account":{"email":"a@b.c"},
       "windows":[{"kind":"session","percentRemaining":84}]},
      {"provider":"codex","state":{"status":"fresh"},"account":{"email":"d@e.f"},
       "windows":[{"kind":"session","percentRemaining":14}]},
      {"provider":"agy","state":{"status":"fresh"},
       "windows":[{"kind":"weekly","percentRemaining":1}]},
      {"provider":"cursor","state":{"status":"auth_required"}},
      {"provider":"alibaba","state":{"status":"unavailable","error":"bl_cli_unavailable"}},
      {"provider":"opencode-go","state":{"status":"auth_required"},
       "quotaSemantics":{"unresolvedWindowIds":["rolling","weekly","monthly"]}}]}
    """)

    @Test
    func onlyMeasurableProvidersStartOn() {
        let hidden = ProviderVisibilitySeed.hiddenProviders(from: firstLaunch)
        #expect(hidden == ["cursor", "alibaba", "opencode-go"])
    }

    /// The seed is computed from the snapshot, never from a hard-coded list, so
    /// a machine signed into a different set of providers gets its own answer.
    @Test
    func theSeedFollowsTheMachineRatherThanAFixedProviderList() throws {
        let elsewhere = try QuotaParser.decode("""
        {"providers":[
          {"provider":"claude","state":{"status":"auth_required"}},
          {"provider":"kimi","state":{"status":"fresh"},"account":{"email":"k@example.com"},
           "windows":[{"kind":"session","percentRemaining":60}]}]}
        """)
        #expect(ProviderVisibilitySeed.hiddenProviders(from: elsewhere) == ["claude"])
    }

    /// Hiding everything would leave an app with nothing in it and no obvious way
    /// back, so an unusable snapshot defers the decision instead.
    @Test
    func aSnapshotWithNothingMeasurableDoesNotSeedAtAll() throws {
        let nothing = try QuotaParser.decode("""
        {"providers":[
          {"provider":"claude","state":{"status":"auth_required"}},
          {"provider":"codex","state":{"status":"auth_required"}}]}
        """)
        #expect(ProviderVisibilitySeed.hiddenProviders(from: nothing) == nil)
        #expect(ProviderVisibilitySeed.hiddenProviders(from: nil) == nil)
    }
}
