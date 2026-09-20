import Foundation

/// A simple vector mark drawn in code for each provider.
///
/// These are deliberately generic geometric forms, never vendor logo artwork:
/// the goal is a distinct, recognizable silhouette at menu bar size.
public enum BrandMark: String, Sendable, CaseIterable {
    case starburst
    case ring
    case pointer
    case lobes
    case bolt
    case crescent
    case zigzag
    case chevron
    case hexagon
    case brackets
    case quatrefoil
    case dot
}

public struct ProviderBrand: Sendable, Equatable {
    public let hex: String
    public let mark: BrandMark

    public init(hex: String, mark: BrandMark) {
        self.hex = hex
        self.mark = mark
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
    /// The single table. Adding a provider is one line: its brand color and its mark.
    /// Colors were referenced from each provider's own published branding; no assets were copied.
    public static let brands: [String: ProviderBrand] = [
        "claude": ProviderBrand(hex: "#D97757", mark: .starburst),
        "codex": ProviderBrand(hex: "#49A3B0", mark: .ring),
        "cursor": ProviderBrand(hex: "#00BFA5", mark: .pointer),
        "copilot": ProviderBrand(hex: "#A855F7", mark: .lobes),
        "grok": ProviderBrand(hex: "#10A37F", mark: .bolt),
        "kimi": ProviderBrand(hex: "#205DEB", mark: .crescent),
        "zai": ProviderBrand(hex: "#E85A6A", mark: .zigzag),
        "agy": ProviderBrand(hex: "#60BA7E", mark: .chevron),
        "alibaba": ProviderBrand(hex: "#FF6A00", mark: .hexagon),
        "opencode-go": ProviderBrand(hex: "#3B82F6", mark: .brackets),
        "commandcode": ProviderBrand(hex: "#A04DFD", mark: .quatrefoil),
    ]

    public static let fallback = ProviderBrand(hex: "#7C7C80", mark: .dot)

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
