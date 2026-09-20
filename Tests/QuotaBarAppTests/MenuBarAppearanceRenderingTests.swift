import AppKit
import QuotaBarCore
import Testing
@testable import QuotaBar

/// The appearance settings are only worth anything if they survive a relaunch
/// and actually change what is drawn. This covers both halves: what the store
/// reads back, and what the mark image and the status title come out as.
@MainActor
struct MenuBarAppearanceRenderingTests {
    // MARK: - Persistence

    /// In memory on purpose: a scratch `UserDefaults` suite writes a real plist
    /// into `~/Library/Preferences` for every test run.
    private func reopened(_ store: PreferenceStore) -> AppPreferences {
        AppPreferences(defaults: store)
    }

    @Test
    func anUntouchedInstallReadsBackTheOriginalPresentation() {
        let preferences = AppPreferences(defaults: InMemoryPreferenceStore())
        #expect(preferences.menuBarAppearance == MenuBarAppearance.default)
    }

    @Test
    func everyAppearanceSettingSurvivesARelaunch() {
        let store = InMemoryPreferenceStore()
        let preferences = AppPreferences(defaults: store)

        let chosen = MenuBarAppearance(
            backingScope: .markAndNumber,
            markStyle: .white,
            backingColorStyle: .custom,
            backingColorHex: "#3366FF",
            backingOpacity: 0.24,
            textColorStyle: .custom,
            textColorHex: "#FF8800",
            font: .serif)
        preferences.menuBarAppearance = chosen

        // The same store, read by a fresh instance: this is what a relaunch is.
        #expect(reopened(store).menuBarAppearance == chosen)
    }

    @Test
    func eachChoiceIsStoredUnderItsOwnKeyRatherThanOneBlob() {
        let store = InMemoryPreferenceStore()
        let preferences = AppPreferences(defaults: store)
        preferences.menuBarAppearance.markStyle = .black

        // Only the one setting moved; everything else still reads its default.
        var expected = MenuBarAppearance.default
        expected.markStyle = .black
        #expect(reopened(store).menuBarAppearance == expected)
    }

    /// The captain's greyscale mark carries over to the ink it was drawing,
    /// and the migrated value is written back so the next launch - which may
    /// be in the other appearance - does not move it again.
    @Test
    func aStoredGreyscaleMarkMigratesOnceToTheMatchingInk() {
        for (dark, expected) in [(true, MenuBarMarkStyle.white), (false, .black)] {
            let store = InMemoryPreferenceStore(["menuBarMarkStyle": "greyscale"])
            let preferences = AppPreferences(defaults: store, darkMenuBar: dark)
            #expect(preferences.menuBarAppearance.markStyle == expected)
            #expect(store.string(forKey: "menuBarMarkStyle") == expected.rawValue)

            // Relaunched in the other appearance: the migration is done, so the
            // choice stays where it landed.
            let relaunched = AppPreferences(defaults: store, darkMenuBar: !dark)
            #expect(relaunched.menuBarAppearance.markStyle == expected)
        }
    }

    /// A stored value QuotaBar no longer understands must not take the menu bar
    /// with it.
    @Test
    func anUnreadableStoredChoiceFallsBackToItsDefault() {
        let store = InMemoryPreferenceStore([
            "menuBarMarkStyle": "sepia",
            "menuBarReadoutFont": "",
            "menuBarBackingScope": MenuBarBackingScope.none.rawValue,
        ])
        let appearance = AppPreferences(defaults: store).menuBarAppearance

        #expect(appearance.markStyle == .color)
        #expect(appearance.font == .system)
        #expect(appearance.backingScope == .none, "a readable choice still has to be honoured")
    }

    // MARK: - The drawn mark

    private func pixels(_ image: NSImage) -> NSBitmapImageRep? {
        image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))
    }

    /// The band below the mark, where only the plate can have drawn: the mark is
    /// inset from the image edge on every side.
    private func plateAlpha(_ image: NSImage) -> Double {
        guard let bitmap = pixels(image) else { return 0 }
        let row = 0
        var best = 0.0
        for x in (bitmap.pixelsWide / 3)...(bitmap.pixelsWide * 2 / 3) {
            best = max(best, Double(bitmap.colorAt(x: x, y: row)?.alphaComponent ?? 0))
        }
        return best
    }

    private func averageInk(_ image: NSImage) -> BrandRGB {
        guard let bitmap = pixels(image) else { return BrandRGB(red: 0, green: 0, blue: 0) }
        var sum = (red: 0.0, green: 0.0, blue: 0.0)
        var counted = 0
        for x in 0..<bitmap.pixelsWide {
            for y in 0..<bitmap.pixelsHigh {
                guard let color = bitmap.colorAt(x: x, y: y), color.alphaComponent > 0.5 else {
                    continue
                }
                counted += 1
                sum.red += Double(color.redComponent)
                sum.green += Double(color.greenComponent)
                sum.blue += Double(color.blueComponent)
            }
        }
        guard counted > 0 else { return BrandRGB(red: 0, green: 0, blue: 0) }
        return BrandRGB(
            red: sum.red / Double(counted),
            green: sum.green / Double(counted),
            blue: sum.blue / Double(counted))
    }

    @Test
    func theBackingScopeDecidesWhetherTheMarkImageCarriesAPlate() {
        var appearance = MenuBarAppearance.default

        appearance.backingScope = .mark
        let plated = ProviderMarkImage.menuBarImage(
            provider: "claude", dark: true, appearance: appearance)
        #expect(plateAlpha(plated) > 0.02, "the icon-only backing drew no plate")

        appearance.backingScope = .none
        let bare = ProviderMarkImage.menuBarImage(
            provider: "claude", dark: true, appearance: appearance)
        #expect(plateAlpha(bare) < 0.01, "a plate was drawn with the backing turned off")

        // The wide plate is the status item's layer, not the image: the image
        // must stay bare or the mark would sit on two plates.
        appearance.backingScope = .markAndNumber
        let wide = ProviderMarkImage.menuBarImage(
            provider: "claude", dark: true, appearance: appearance)
        #expect(plateAlpha(wide) < 0.01, "the mark image plated itself as well as the whole item")
    }

    /// Whatever the backing does, the mark keeps one size - otherwise changing
    /// the backing would resize the icon in the menu bar.
    @Test
    func theMarkKeepsOneSizeAcrossEveryBackingScope() {
        let sizes = Set(MenuBarBackingScope.allCases.map { scope -> String in
            var appearance = MenuBarAppearance.default
            appearance.backingScope = scope
            let image = ProviderMarkImage.menuBarImage(
                provider: "claude", dark: false, appearance: appearance)
            return "\(image.size.width)x\(image.size.height)"
        })
        #expect(sizes.count == 1, "the mark changes size with the backing: \(sizes.sorted())")
    }

    @Test
    func aCustomBackingColourReachesThePlate() {
        var appearance = MenuBarAppearance.default
        appearance.backingColorStyle = .custom
        appearance.backingColorHex = "#FF0000"
        appearance.backingOpacity = 0.9

        let image = ProviderMarkImage.menuBarImage(
            provider: "claude", dark: true, appearance: appearance)
        guard let bitmap = pixels(image),
              let corner = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: 0)
        else {
            Issue.record("the plate did not rasterize")
            return
        }
        #expect(Double(corner.alphaComponent) > 0.5, "the custom strength never reached the plate")
        #expect(
            Double(corner.redComponent) > 0.8 && Double(corner.greenComponent) < 0.3,
            "the plate came out \(corner) instead of red")
    }

    /// The drawn mark, not just the colour decision: black has to come out
    /// black and white has to come out white, in both appearances, and the
    /// brand colour has to still be a colour.
    @Test
    func blackAndWhiteMarksDrawAsFlatInksWhileColourKeepsItsHue() {
        var appearance = MenuBarAppearance.default
        appearance.backingScope = .none

        for dark in [false, true] {
            let colored = averageInk(ProviderMarkImage.menuBarImage(
                provider: "claude", dark: dark, appearance: appearance))
            #expect(
                abs(colored.red - colored.blue) > 0.1,
                "the coloured mark drew as a grey: \(colored)")
        }

        for (style, expected) in [(MenuBarMarkStyle.black, 0.0), (.white, 1.0)] {
            appearance.markStyle = style
            for dark in [false, true] {
                let ink = averageInk(ProviderMarkImage.menuBarImage(
                    provider: "claude", dark: dark, appearance: appearance))
                for channel in [ink.red, ink.green, ink.blue] {
                    #expect(
                        abs(channel - expected) < 0.04,
                        "\(style.rawValue) dark=\(dark) drew \(ink) rather than a flat ink")
                }
            }
        }
    }

    // MARK: - The drawn title

    private func titleColor(_ appearance: MenuBarAppearance) -> NSColor? {
        let mark = ProviderMarkImage.menuBarImage(
            provider: "claude", dark: true, appearance: appearance)
        let title = StatusItemController.statusTitle(
            mark: mark, percent: "44%", appearance: appearance)
        return title.attribute(
            .foregroundColor, at: title.length - 1, effectiveRange: nil) as? NSColor
    }

    @Test
    func theNumberTakesTheChosenColour() {
        var appearance = MenuBarAppearance.default
        #expect(titleColor(appearance) == NSColor.labelColor)

        appearance.textColorStyle = .white
        #expect(titleColor(appearance)?.usingColorSpace(.sRGB)?.redComponent == 1)

        appearance.textColorStyle = .black
        #expect(titleColor(appearance)?.usingColorSpace(.sRGB)?.redComponent == 0)

        appearance.textColorStyle = .custom
        appearance.textColorHex = "#FF8800"
        let custom = titleColor(appearance)?.usingColorSpace(.sRGB)
        #expect((custom?.redComponent ?? 0) > 0.9)
        #expect((custom?.blueComponent ?? 1) < 0.1)
    }

    @Test
    func theNumberTakesTheChosenFace() {
        let names = MenuBarFontChoice.allCases.map { StatusItemController.font(for: $0).fontName }
        #expect(Set(names).count == MenuBarFontChoice.allCases.count,
                "two font choices drew the same face: \(names)")
        #expect(StatusItemController.font(for: .system) == StatusItemController.titleFont)
    }

    /// Whichever face is chosen, a 1 has to be as wide as a 4, or the menu bar
    /// item breathes as the quota falls.
    @Test
    func everyFontChoiceKeepsTabularFigures() {
        for choice in MenuBarFontChoice.allCases {
            let font = StatusItemController.font(for: choice)
            let widths = Set(["1", "4", "8", "0"].map { digit -> Int in
                Int(((digit as NSString).size(withAttributes: [.font: font]).width * 100).rounded())
            })
            #expect(widths.count == 1, "\(choice.rawValue) is not tabular: \(widths.sorted())")

            var appearance = MenuBarAppearance.default
            appearance.font = choice
            let mark = ProviderMarkImage.menuBarImage(
                provider: "claude", dark: false, appearance: appearance)
            let reserved = Set([0.0, 9, 44, 100].map { value -> Int in
                let title = StatusItemController.statusTitle(
                    mark: mark,
                    percent: StatusItemController.reservedPercent(value),
                    appearance: appearance)
                return Int(title.size().width.rounded())
            })
            // The unknown readout is widened to the same column, and it is
            // widened by measuring the chosen face, so it belongs in the set.
            let unknown = StatusItemController.statusTitle(
                mark: mark,
                percent: StatusItemController.reservedUnknown(),
                appearance: appearance)
            let unknownWidth = Int(unknown.size().width.rounded())
            #expect(
                reserved.union([unknownWidth]).count == 1,
                "\(choice.rawValue) changes width: \(reserved.sorted()) unknown=\(unknownWidth)")
        }
    }

    @Test
    func theChosenFaceIsTheOneInTheTitle() {
        var appearance = MenuBarAppearance.default
        appearance.font = .serif
        let mark = ProviderMarkImage.menuBarImage(
            provider: "claude", dark: false, appearance: appearance)
        let title = StatusItemController.statusTitle(
            mark: mark, percent: "44%", appearance: appearance)
        let font = title.attribute(.font, at: title.length - 1, effectiveRange: nil) as? NSFont
        #expect(font?.fontName == StatusItemController.font(for: .serif).fontName)
    }

    /// The mark has to survive every appearance: losing it is the original bug.
    @Test
    func theMarkStaysInTheTitleUnderEveryAppearance() {
        for scope in MenuBarBackingScope.allCases {
            for style in MenuBarMarkStyle.allCases {
                for font in MenuBarFontChoice.allCases {
                    var appearance = MenuBarAppearance.default
                    appearance.backingScope = scope
                    appearance.markStyle = style
                    appearance.font = font

                    let mark = ProviderMarkImage.menuBarImage(
                        provider: "claude", dark: true, appearance: appearance)
                    let title = StatusItemController.statusTitle(
                        mark: mark, percent: "44%", appearance: appearance)
                    let carried = StatusItemController.markImage(in: title)
                    #expect(
                        carried != nil,
                        "\(scope.rawValue)/\(style.rawValue)/\(font.rawValue) lost the mark")
                    #expect(carried?.isTemplate == false, "a template image loses the colour")
                }
            }
        }
    }

    // MARK: - The wide plate

    @Test
    func onlyTheWidestScopePlatesTheWholeItem() {
        var appearance = MenuBarAppearance.default

        for scope in [MenuBarBackingScope.none, .mark] {
            appearance.backingScope = scope
            #expect(StatusItemController.wholeItemPlate(appearance: appearance, dark: true) == nil)
        }

        appearance.backingScope = .markAndNumber
        let plate = StatusItemController.wholeItemPlate(appearance: appearance, dark: true)
        #expect(plate != nil)
        #expect((plate?.cornerRadius ?? 0) > 0, "the wide plate is a rectangle with sharp corners")

        let drawn = plate?.color.usingColorSpace(.sRGB)
        #expect(Double(drawn?.alphaComponent ?? 0) == MenuBarAppearance.automaticOpacityOnDark)
        #expect(Double(drawn?.redComponent ?? 0) == 1, "a dark menu bar takes a white plate")
    }

    /// Every backing scope wears a plate while the panel is open, including the
    /// one that draws none the rest of the time - taking the feedback away
    /// altogether was never the fix.
    @Test
    func everyScopeShowsAPlateWhileThePanelIsOpen() {
        for scope in MenuBarBackingScope.allCases {
            var appearance = MenuBarAppearance.default
            appearance.backingScope = scope
            for dark in [false, true] {
                let open = StatusItemController.wholeItemPlate(
                    appearance: appearance, dark: dark, open: true)
                #expect(open != nil, "\(scope.rawValue) dark=\(dark) showed nothing when open")
                #expect((open?.cornerRadius ?? 0) > 0)
            }
        }
    }

    // MARK: - The plate's hug

    /// The plate is placed against the reserved column, not the button's
    /// bounds, and the column is the same width at 4% as at 100% - so the
    /// plate must be too. A plate that tracked the ink would breathe as the
    /// quota fell, which is the movement the column exists to prevent.
    @Test
    func theHuggingPlateKeepsOneWidthAtEveryReadout() {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 200, height: 22))
        var widths: Set<Int> = []
        var appearance = MenuBarAppearance.default
        appearance.backingScope = .markAndNumber

        for value in [0.0, 4, 9, 44, 100] {
            let mark = ProviderMarkImage.menuBarImage(
                provider: "claude", dark: false, appearance: appearance)
            let title = StatusItemController.statusTitle(
                mark: mark,
                percent: StatusItemController.reservedPercent(value),
                appearance: appearance)
            button.attributedTitle = title
            widths.insert(Int(StatusItemController.wholeItemPlateFrame(in: button).width))
        }
        #expect(widths.count == 1, "the plate changed width with the number: \(widths.sorted())")
    }

    /// And it really is narrower than the button, by the hug on each side - a
    /// plate that fell back to the bounds is the frame the captain objected to.
    @Test
    func theHuggingPlateSitsInsideTheButtonsBounds() {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 120, height: 22))
        var appearance = MenuBarAppearance.default
        appearance.backingScope = .markAndNumber
        let mark = ProviderMarkImage.menuBarImage(
            provider: "claude", dark: false, appearance: appearance)
        let title = StatusItemController.statusTitle(
            mark: mark, percent: StatusItemController.reservedPercent(44), appearance: appearance)
        button.attributedTitle = title

        let frame = StatusItemController.wholeItemPlateFrame(in: button)
        #expect(frame.width < button.bounds.width)
        #expect(frame.width > title.size().width, "the plate has to leave the readout some room")
        #expect(frame.minX > 0, "the plate starts inside the button")
        #expect(frame.height == button.bounds.height)

        // A button no wider than its title has nothing to give back, so the
        // plate falls back to the bounds rather than being drawn narrower than
        // the readout it is meant to sit behind.
        let tight = NSButton(frame: NSRect(x: 0, y: 0, width: title.size().width, height: 22))
        tight.attributedTitle = title
        #expect(StatusItemController.wholeItemPlateFrame(in: tight) == tight.bounds)
    }
}
