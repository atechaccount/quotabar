import Foundation

/// Everything provider-specific the UI needs that quota-axi does not report:
/// the brand color, the real provider mark to load, and the vendor QuotaBar is
/// careful to say it does *not* contact.
public struct ProviderBrand: Sendable, Equatable {
    public let hex: String
    /// Base name of the real provider mark carried in `Resources/ProviderMarks`.
    /// `nil` means QuotaBar has no mark for this provider and falls back to its
    /// own glyph rather than inventing artwork.
    public let iconResourceName: String?
    /// Who actually owns the account. Used only to state QuotaBar's boundary.
    public let vendor: String

    public init(hex: String, iconResourceName: String?, vendor: String) {
        self.hex = hex
        self.iconResourceName = iconResourceName
        self.vendor = vendor
    }
}

public struct BrandRGB: Sendable, Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

public enum BrandColors {
    /// The single table. Adding a provider is one line: its brand color, the mark
    /// file to load, and the vendor that owns the account.
    ///
    /// Colors were referenced from each provider's own published branding. The
    /// marks are the vendors' real marks, carried as SVG resources - QuotaBar no
    /// longer hand-draws stand-ins for them.
    public static let brands: [String: ProviderBrand] = [
        "claude": ProviderBrand(hex: "#D97757", iconResourceName: "ProviderIcon-claude", vendor: "Anthropic"),
        "codex": ProviderBrand(hex: "#49A3B0", iconResourceName: "ProviderIcon-codex", vendor: "OpenAI"),
        "cursor": ProviderBrand(hex: "#00BFA5", iconResourceName: "ProviderIcon-cursor", vendor: "Cursor"),
        "copilot": ProviderBrand(hex: "#A855F7", iconResourceName: "ProviderIcon-copilot", vendor: "GitHub"),
        "grok": ProviderBrand(hex: "#10A37F", iconResourceName: "ProviderIcon-grok", vendor: "xAI"),
        "kimi": ProviderBrand(hex: "#205DEB", iconResourceName: "ProviderIcon-kimi", vendor: "Moonshot AI"),
        "zai": ProviderBrand(hex: "#E85A6A", iconResourceName: "ProviderIcon-zai", vendor: "Z.AI"),
        "agy": ProviderBrand(hex: "#60BA7E", iconResourceName: "ProviderIcon-antigravity", vendor: "Google"),
        "alibaba": ProviderBrand(hex: "#FF6A00", iconResourceName: "ProviderIcon-alibaba", vendor: "Alibaba"),
        "opencode-go": ProviderBrand(hex: "#3B82F6", iconResourceName: "ProviderIcon-opencodego", vendor: "OpenCode"),
        "commandcode": ProviderBrand(hex: "#A04DFD", iconResourceName: "ProviderIcon-commandcode", vendor: "Command Code"),
    ]

    /// An unknown provider gets a neutral color and no mark, so QuotaBar shows its
    /// own glyph rather than another provider's artwork.
    public static let fallback = ProviderBrand(
        hex: "#7C7C80", iconResourceName: nil, vendor: "the provider")

    public static func brand(for provider: String) -> ProviderBrand {
        brands[provider] ?? fallback
    }

    public static func hex(for provider: String) -> String {
        brand(for: provider).hex
    }

    // MARK: - Appearance safety

    /// Representative menu bar / menu backgrounds in each appearance.
    public static let lightBackground = BrandRGB(red: 0.96, green: 0.96, blue: 0.96)
    public static let darkBackground = BrandRGB(red: 0.11, green: 0.11, blue: 0.12)

    /// Minimum contrast ratio a mark must reach against the background it is drawn on.
    public static let minimumContrastRatio = 3.0

    public static func rgb(fromHex hex: String) -> BrandRGB {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let value = UInt64(digits, radix: 16) ?? 0x7C_7C_80
        return BrandRGB(
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255)
    }

    public static func hex(from color: BrandRGB) -> String {
        func channel(_ value: Double) -> Int {
            Int((min(max(value, 0), 1) * 255).rounded())
        }
        return String(
            format: "#%02X%02X%02X", channel(color.red), channel(color.green), channel(color.blue))
    }

    /// The same colour with the hue taken out, weighted the way the eye weighs
    /// the channels, so a mark keeps the tonal weight it had rather than turning
    /// into a flat mid grey.
    public static func greyscale(_ color: BrandRGB) -> BrandRGB {
        let luma = 0.299 * color.red + 0.587 * color.green + 0.114 * color.blue
        return BrandRGB(red: luma, green: luma, blue: luma)
    }

    public static func relativeLuminance(_ color: BrandRGB) -> Double {
        func channel(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(color.red)
            + 0.7152 * channel(color.green)
            + 0.0722 * channel(color.blue)
    }

    public static func contrastRatio(_ a: BrandRGB, _ b: BrandRGB) -> Double {
        let first = relativeLuminance(a)
        let second = relativeLuminance(b)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    /// Nudges a brand color toward white on dark backgrounds, or toward black on light
    /// ones, only as far as is needed to clear `minimumContrastRatio`. A color that
    /// already reads well is returned untouched, so brand identity survives.
    public static func readableColor(for provider: String, darkAppearance: Bool) -> BrandRGB {
        readable(
            rgb(fromHex: hex(for: provider)),
            on: darkAppearance ? darkBackground : lightBackground)
    }

    public static func readable(_ color: BrandRGB, on background: BrandRGB) -> BrandRGB {
        guard contrastRatio(color, background) < minimumContrastRatio else { return color }
        let target: BrandRGB = relativeLuminance(background) < 0.5
            ? BrandRGB(red: 1, green: 1, blue: 1)
            : BrandRGB(red: 0, green: 0, blue: 0)

        var best = color
        for step in 1...20 {
            let amount = Double(step) / 20
            let blended = blend(color, toward: target, amount: amount)
            best = blended
            if contrastRatio(blended, background) >= minimumContrastRatio { break }
        }
        return best
    }

    private static func blend(_ color: BrandRGB, toward target: BrandRGB, amount: Double) -> BrandRGB {
        BrandRGB(
            red: color.red + (target.red - color.red) * amount,
            green: color.green + (target.green - color.green) * amount,
            blue: color.blue + (target.blue - color.blue) * amount)
    }
}
