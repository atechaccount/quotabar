import AppKit
import QuotaBarCore
import Testing
@testable import QuotaBar

/// The marks are now real vendor artwork loaded from resources rather than
/// geometry drawn in Swift, so what has to be proven changed: the resource has
/// to be present, it has to rasterize to something, and it has to come out in
/// the brand color rather than as a template AppKit will flatten.
@MainActor
struct ProviderMarkImageTests {
    private func ink(_ image: NSImage) -> (coverage: Double, average: BrandRGB) {
        guard let data = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: data)
        else { return (0, BrandRGB(red: 0, green: 0, blue: 0)) }

        var covered = 0
        var total = 0
        var sum = (red: 0.0, green: 0.0, blue: 0.0)
        for x in 0..<bitmap.pixelsWide {
            for y in 0..<bitmap.pixelsHigh {
                total += 1
                guard let color = bitmap.colorAt(x: x, y: y), color.alphaComponent > 0.5 else {
                    continue
                }
                covered += 1
                sum.red += Double(color.redComponent)
                sum.green += Double(color.greenComponent)
                sum.blue += Double(color.blueComponent)
            }
        }
        guard covered > 0 else { return (0, BrandRGB(red: 0, green: 0, blue: 0)) }
        return (
            Double(covered) / Double(total) * 100,
            BrandRGB(
                red: sum.red / Double(covered),
                green: sum.green / Double(covered),
                blue: sum.blue / Double(covered)))
    }

    @Test
    func everyKnownProviderShipsARealMark() {
        for provider in BrandColors.brands.keys.sorted() {
            #expect(
                ProviderMarkImage.hasVendorMark(for: provider),
                "\(provider) has no mark resource in the bundle")
        }
    }

    @Test
    func everyMarkDrawsSomethingInBothAppearances() {
        for provider in BrandColors.brands.keys.sorted() {
            for dark in [false, true] {
                let image = ProviderMarkImage.image(provider: provider, dark: dark, side: 32)
                let measured = ink(image)
                #expect(
                    measured.coverage > 8,
                    "\(provider) dark=\(dark) covers only \(measured.coverage)% and will look empty")
                #expect(
                    measured.coverage < 95,
                    "\(provider) dark=\(dark) is nearly a solid block")
            }
        }
    }

    /// A template image is exactly what made the menu bar mark disappear into the
    /// menu bar's own ink, so it must stay off.
    @Test
    func marksAreNotTemplatesAndCarryTheBrandColor() {
        for provider in BrandColors.brands.keys.sorted() {
            for dark in [false, true] {
                let image = ProviderMarkImage.image(provider: provider, dark: dark, side: 32)
                #expect(!image.isTemplate, "\(provider) must not be a template image")

                let measured = ink(image)
                let expected = BrandColors.readableColor(for: provider, darkAppearance: dark)
                let distance = abs(measured.average.red - expected.red)
                    + abs(measured.average.green - expected.green)
                    + abs(measured.average.blue - expected.blue)
                let drawn = "(\(measured.average.red), \(measured.average.green), "
                    + "\(measured.average.blue))"
                #expect(
                    distance < 0.12,
                    "\(provider) dark=\(dark) drew \(drawn) instead of the brand color")
            }
        }
    }

    /// A provider QuotaBar has no mark for gets QuotaBar's own glyph, never
    /// another vendor's artwork.
    @Test
    func anUnknownProviderFallsBackToTheAppGlyph() {
        #expect(!ProviderMarkImage.hasVendorMark(for: "something-new"))
        let image = ProviderMarkImage.image(provider: "something-new", dark: false, side: 32)
        #expect(ink(image).coverage > 8, "the fallback glyph drew nothing")
    }

    @Test
    func theAppGlyphDrawsInBothAppearances() {
        for dark in [false, true] {
            #expect(ink(ProviderMarkImage.appGlyph(side: 32, dark: dark)).coverage > 8)
        }
    }
}
