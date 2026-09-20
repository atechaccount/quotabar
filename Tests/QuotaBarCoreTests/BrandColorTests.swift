import Testing
@testable import QuotaBarCore

struct BrandColorTests {
    @Test
    func everyKnownProviderHasAColorAndItsOwnRealMark() {
        let expected = [
            "claude", "codex", "cursor", "copilot", "grok", "kimi",
            "zai", "agy", "alibaba", "opencode-go", "commandcode",
        ]
        for provider in expected {
            #expect(BrandColors.brands[provider] != nil, "missing brand for \(provider)")
            #expect(
                BrandColors.brand(for: provider).iconResourceName != nil,
                "\(provider) has no real mark to load")
            #expect(!BrandColors.brand(for: provider).vendor.isEmpty)
        }

        let marks = expected.compactMap { BrandColors.brand(for: $0).iconResourceName }
        #expect(Set(marks).count == marks.count, "two providers share a mark file")
    }

    @Test
    func claudeIsOrange() {
        #expect(BrandColors.hex(for: "claude") == "#D97757")
    }

    /// An unknown provider gets no mark at all rather than borrowing another
    /// vendor's artwork; the app falls back to its own glyph.
    @Test
    func anUnknownProviderHasNoVendorMark() {
        let brand = BrandColors.brand(for: "something-new")
        #expect(brand == BrandColors.fallback)
        #expect(brand.iconResourceName == nil)
    }

    /// The marks are drawn on both a light and a dark menu bar, so every brand
    /// color must clear the contrast floor in both appearances after adjustment.
    @Test
    func everyBrandColorIsReadableInBothAppearances() {
        for (provider, brand) in BrandColors.brands {
            for dark in [true, false] {
                let background = dark ? BrandColors.darkBackground : BrandColors.lightBackground
                let color = BrandColors.readableColor(for: provider, darkAppearance: dark)
                let ratio = BrandColors.contrastRatio(color, background)
                #expect(
                    ratio >= BrandColors.minimumContrastRatio,
                    "\(provider) (\(brand.hex)) contrast \(ratio) on \(dark ? "dark" : "light")")
            }
        }
    }

    /// Every raw brand color clears the floor on a dark menu bar unchanged, so on
    /// dark the captain sees the real brand color and nothing is touched.
    @Test
    func brandColorsAreUsedUnchangedOnADarkMenuBar() {
        for provider in BrandColors.brands.keys {
            let original = BrandColors.rgb(fromHex: BrandColors.hex(for: provider))
            #expect(
                BrandColors.readableColor(for: provider, darkAppearance: true) == original,
                "\(provider) should render as its own color on dark")
        }
    }

    /// Several brand colors are too light to read on a light menu bar and are
    /// darkened just enough to clear the floor.
    @Test
    func tooLightColorsAreDarkenedForALightMenuBar() {
        for provider in ["cursor", "agy", "alibaba", "claude"] {
            let original = BrandColors.rgb(fromHex: BrandColors.hex(for: provider))
            let adjusted = BrandColors.readableColor(for: provider, darkAppearance: false)

            #expect(adjusted != original, "\(provider) should have been darkened")
            #expect(
                BrandColors.relativeLuminance(adjusted) < BrandColors.relativeLuminance(original),
                "\(provider) should get darker, not lighter")
        }
    }

    @Test
    func aColorThatAlreadyReadsWellIsLeftAlone() {
        let original = BrandColors.rgb(fromHex: BrandColors.hex(for: "kimi"))
        #expect(BrandColors.readableColor(for: "kimi", darkAppearance: false) == original)
    }

    @Test
    func contrastRatioIsSymmetricAndBounded() {
        let white = BrandRGB(red: 1, green: 1, blue: 1)
        let black = BrandRGB(red: 0, green: 0, blue: 0)
        #expect(abs(BrandColors.contrastRatio(white, black) - 21) < 0.01)
        #expect(BrandColors.contrastRatio(white, black) == BrandColors.contrastRatio(black, white))
        #expect(abs(BrandColors.contrastRatio(white, white) - 1) < 0.001)
    }
}

struct QuotaFormattingCadenceTests {
    @Test
    func cadenceNamesHowOftenAWindowComesBack() {
        #expect(QuotaFormatting.cadence(windowSeconds: 18_000) == "every 5h")
        #expect(QuotaFormatting.cadence(windowSeconds: 604_800) == "every 1w")
        #expect(QuotaFormatting.cadence(windowSeconds: 86_400) == "every 1d")
        #expect(QuotaFormatting.cadence(windowSeconds: nil) == nil)
        #expect(QuotaFormatting.cadence(windowSeconds: 0) == nil)
    }
}
