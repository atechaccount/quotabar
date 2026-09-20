import QuotaBarCore
import SwiftUI

/// The provider's real mark, loaded from the SVG resources and painted in the
/// appearance-adjusted brand color. Nothing here is hand-drawn geometry: the
/// marks are the vendors' own, carried as resources.
struct ProviderMark: View {
    let provider: String
    var size: CGFloat = 13
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(nsImage: ProviderMarkImage.image(
            provider: provider,
            dark: colorScheme == .dark,
            side: size))
            .resizable()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

extension Color {
    init(readable rgb: BrandRGB) {
        self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1)
    }

    init(brandHex hex: String) {
        self.init(readable: BrandColors.rgb(fromHex: hex))
    }

    /// The brand color already nudged to clear the contrast floor on this
    /// appearance, so a pale mark never disappears into a light popover.
    static func brand(_ provider: String, dark: Bool) -> Color {
        Color(readable: BrandColors.readableColor(for: provider, darkAppearance: dark))
    }
}
