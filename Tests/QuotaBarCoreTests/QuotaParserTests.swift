import Testing
@testable import QuotaBarCore

struct QuotaParserTests {
    @Test
    func testDecodesCapturedQuotaAXIOutput() throws {
        let directory = "/" + #filePath.split(separator: "/").dropLast().joined(separator: "/")
        let snapshot = try QuotaParser.decodeFile(atPath: directory + "/Fixtures/quota-axi-sample.json")

        #expect(snapshot.schemaVersion == 5)
        #expect(snapshot.providers.count == 11)

        let claude = try #require(snapshot.providers.first { $0.provider == "claude" })
        // The headline is the short rolling session window, not the weekly one.
        let headline = try #require(claude.headline)
        #expect(headline.isSession)
        #expect(headline.windowLabel == "session")
        #expect(headline.percentRemaining == claude.sessionWindow?.percentRemaining)
        #expect(claude.windows?.count == 2)
        #expect(claude.weeklyWindow?.percentRemaining == 52)

        let cursor = try #require(snapshot.providers.first { $0.provider == "cursor" })
        #expect(!cursor.isFresh)
        #expect(cursor.headlineRemaining == nil)
        #expect(cursor.unavailableDescription == "not signed in")
    }

    @Test
    func testFutureSchemaAndMalformedOptionalFieldsStillRender() throws {
        let json = #"{"schemaVersion":999,"futureField":true,"providers":[{"provider":"future","label":42,"windows":"changed","state":{"status":"fresh"},"quotaSemantics":{"effectiveAvailability":[{"effectivePercentRemaining":77}]}}]}"#
        let snapshot = try QuotaParser.decode(json)

        #expect(snapshot.schemaVersion == 999)
        #expect(snapshot.providers.first?.displayName == "future")
        #expect(snapshot.providers.first?.headlineRemaining == 77)
    }

    @Test
    func testUnknownProviderStateNeverLooksLikeZeroQuota() throws {
        let json = #"{"providers":[{"provider":"new-provider","state":{"status":"surprise"},"windows":[{"percentRemaining":0}]}]}"#
        let provider = try #require(QuotaParser.decode(json).providers.first)

        #expect(!provider.isFresh)
        #expect(provider.headlineRemaining == nil)
        #expect(provider.unavailableDescription == "unavailable")
    }
}
