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

    /// Black and white are exactly that, for every provider and in both
    /// appearances. No contrast nudge, no desaturated brand colour: a flat ink.
    @Test
    func blackAndWhiteAreFlatInks() {
        for (style, expected) in [
            (MenuBarMarkStyle.black, BrandRGB(red: 0, green: 0, blue: 0)),
            (MenuBarMarkStyle.white, BrandRGB(red: 1, green: 1, blue: 1)),
        ] {
            var appearance = MenuBarAppearance.default
            appearance.markStyle = style
            for provider in BrandColors.brands.keys.sorted() {
                for dark in [false, true] {
                    #expect(
                        appearance.markColor(for: provider, dark: dark) == expected,
                        "\(provider) dark=\(dark) \(style.rawValue) was not the flat ink")
                }
            }
        }
    }

    /// The retired greyscale setting resolved to a light grey on a dark menu
    /// bar and a dark grey on a light one, so it migrates to the flat ink that
    /// matches what the captain was looking at - never back to the default.
    @Test
    func theRetiredGreyscaleSettingMigratesToTheInkItLookedLike() {
        #expect(MenuBarMarkStyle.stored("greyscale", dark: true) == .white)
        #expect(MenuBarMarkStyle.stored("greyscale", dark: false) == .black)
    }

    @Test
    func aStoredMarkStyleIsReadBackAndAnUnknownOneFallsBackToTheBrandColour() {
        for style in MenuBarMarkStyle.allCases {
            #expect(MenuBarMarkStyle.stored(style.rawValue, dark: true) == style)
            #expect(MenuBarMarkStyle.stored(style.rawValue, dark: false) == style)
        }
        #expect(MenuBarMarkStyle.stored(nil, dark: true) == .color)
        #expect(MenuBarMarkStyle.stored("chartreuse", dark: true) == .color)
    }

    /// The item says the panel is open in its own plate, because macOS does
    /// not: the system highlight is drawn while the mouse is down and is gone
    /// by the time the panel is up.
    @Test
    func theOpenPlateIsAlwaysDrawnAndAlwaysStrongerThanTheBacking() {
        for scope in MenuBarBackingScope.allCases {
            var appearance = MenuBarAppearance.default
            appearance.backingScope = scope
            for dark in [false, true] {
                let open = appearance.itemPlate(dark: dark, open: true)
                #expect(open != nil, "\(scope) dark=\(dark) had no open indication")

                let shut = appearance.itemPlate(dark: dark, open: false)
                #expect(shut?.opacity ?? 0 < open?.opacity ?? 0,
                        "\(scope) dark=\(dark) the open plate was not the stronger one")
            }
        }
    }

    @Test
    func theShutPlateIsExactlyTheBacking() {
        for scope in MenuBarBackingScope.allCases {
            var appearance = MenuBarAppearance.default
            appearance.backingScope = scope
            for dark in [false, true] {
                let plate = appearance.itemPlate(dark: dark, open: false)
                let backing = appearance.wholeItemBacking(dark: dark)
                #expect(plate?.color == backing?.color)
                #expect(plate?.opacity == backing?.opacity)
            }
        }
    }

    /// The open plate is composited over the backing, so a custom backing
    /// colour is still visible through it rather than being replaced.
    @Test
    func theOpenPlateKeepsTheCustomBackingUnderneath() {
        var appearance = MenuBarAppearance.default
        appearance.backingScope = .markAndNumber
        appearance.backingColorStyle = .custom
        appearance.backingColorHex = "#3366FF"
        appearance.backingOpacity = 0.4

        let blue = BrandColors.rgb(fromHex: "#3366FF")
        let open = appearance.itemPlate(dark: true, open: true)
        #expect(open != nil)
        // White over blue: lighter than the blue, but still bluer than white.
        #expect(open!.color.blue > open!.color.red)
        #expect(open!.color.red > blue.red)
        #expect(open!.opacity > 0.4)
    }

    @Test
    func compositingAnOpaqueTopHidesWhatIsUnderIt() {
        let result = MenuBarAppearance.compositing(
            (BrandRGB(red: 1, green: 0, blue: 0), 1),
            over: (BrandRGB(red: 0, green: 0, blue: 1), 0.5))
        #expect(result.opacity == 1)
        #expect(result.color == BrandRGB(red: 1, green: 0, blue: 0))
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
