import Testing
@testable import QuotaBarCore

/// The decisions the appearance settings drive, away from any drawing. The
/// first test is the one that matters most: an untouched install must look
/// exactly as QuotaBar looked before any of this was configurable.
struct MenuBarAppearanceTests {
    @Test
    func theDefaultIsTheOriginalPresentation() {
        let appearance = MenuBarAppearance.default

        #expect(appearance.backingScope == .mark)
        #expect(appearance.markStyle == .color)
        #expect(appearance.backingColorStyle == .automatic)
        #expect(appearance.textColorStyle == .automatic)
        #expect(appearance.font == .system)

        // The plate the app shipped with: the menu bar's own contrast direction,
        // at the original barely-there strengths.
        let dark = appearance.markBacking(dark: true)
        #expect(dark?.color == BrandRGB(red: 1, green: 1, blue: 1))
        #expect(dark?.opacity == 0.11)
        let light = appearance.markBacking(dark: false)
        #expect(light?.color == BrandRGB(red: 0, green: 0, blue: 0))
        #expect(light?.opacity == 0.07)

        // And the automatic text colour is the system label colour, which is not
        // a value this module can name.
        #expect(appearance.textColor() == nil)
    }

    @Test
    func theBackingScopeDecidesWhichPlateIsDrawn() {
        var appearance = MenuBarAppearance.default

        appearance.backingScope = .none
        #expect(appearance.markBacking(dark: true) == nil)
        #expect(appearance.wholeItemBacking(dark: true) == nil)

        appearance.backingScope = .mark
        #expect(appearance.markBacking(dark: true) != nil)
        #expect(appearance.wholeItemBacking(dark: true) == nil)

        appearance.backingScope = .markAndNumber
        #expect(appearance.markBacking(dark: true) == nil)
        #expect(appearance.wholeItemBacking(dark: true) != nil)
    }

    @Test
    func aCustomBackingUsesTheChosenColourAndStrengthInBothAppearances() {
        var appearance = MenuBarAppearance.default
        appearance.backingColorStyle = .custom
        appearance.backingColorHex = "#3366FF"
        appearance.backingOpacity = 0.3

        for dark in [false, true] {
            let backing = appearance.backing(dark: dark)
            #expect(backing?.color == BrandColors.rgb(fromHex: "#3366FF"))
            #expect(backing?.opacity == 0.3)
        }
    }

    @Test
    func aCustomBackingStrengthIsHeldInsideItsRange() {
        var appearance = MenuBarAppearance.default
        appearance.backingColorStyle = .custom

        appearance.backingOpacity = 9
        #expect(appearance.backing(dark: true)?.opacity == MenuBarAppearance.opacityRange.upperBound)

        appearance.backingOpacity = -3
        #expect(appearance.backing(dark: true)?.opacity == 0)
    }

    @Test
    func theTextColourFollowsTheChoice() {
        var appearance = MenuBarAppearance.default

        appearance.textColorStyle = .white
        #expect(appearance.textColor() == BrandRGB(red: 1, green: 1, blue: 1))

        appearance.textColorStyle = .black
        #expect(appearance.textColor() == BrandRGB(red: 0, green: 0, blue: 0))

        appearance.textColorStyle = .custom
        appearance.textColorHex = "#FF8800"
        #expect(appearance.textColor() == BrandColors.rgb(fromHex: "#FF8800"))

        appearance.textColorStyle = .automatic
        #expect(appearance.textColor() == nil)
    }

    /// Greyscale takes the hue out and nothing else: the mark keeps the tonal
    /// weight it had, and it still has to clear the contrast floor against the
    /// menu bar it is drawn on.
    @Test
    func greyscaleDrainsTheHueAndStaysReadable() {
        var appearance = MenuBarAppearance.default
        appearance.markStyle = .greyscale

        for provider in BrandColors.brands.keys.sorted() {
            for dark in [false, true] {
                let grey = appearance.markColor(for: provider, dark: dark)
                #expect(
                    abs(grey.red - grey.green) < 0.001 && abs(grey.green - grey.blue) < 0.001,
                    "\(provider) dark=\(dark) kept a hue: \(grey)")

                let background = dark ? BrandColors.darkBackground : BrandColors.lightBackground
                #expect(
                    BrandColors.contrastRatio(grey, background)
                        >= BrandColors.minimumContrastRatio - 0.001,
                    "\(provider) dark=\(dark) greyscale is unreadable on the menu bar")
            }
        }
    }

    @Test
    func colourIsStillTheBrandColour() {
        let appearance = MenuBarAppearance.default
        for provider in BrandColors.brands.keys.sorted() {
            for dark in [false, true] {
                #expect(
                    appearance.markColor(for: provider, dark: dark)
                        == BrandColors.readableColor(for: provider, darkAppearance: dark))
            }
        }
    }

    @Test
    func hexSurvivesARoundTrip() {
        for hex in ["#D97757", "#000000", "#FFFFFF", "#3366FF"] {
            #expect(BrandColors.hex(from: BrandColors.rgb(fromHex: hex)) == hex)
        }
    }
}
