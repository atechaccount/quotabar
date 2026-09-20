import Foundation

public enum BrandColors {
    // Provider accents referenced from CodexBar's descriptors; no assets or implementation were copied.
    public static let hexByProvider: [String: String] = [
        "claude": "#D97757",
        "codex": "#49A3B0",
        "cursor": "#00BFA5",
        "copilot": "#A855F7",
        "grok": "#10A37F",
        "kimi": "#205DEB",
        "zai": "#E85A6A",
        "agy": "#60BA7E",
        "alibaba": "#FF6A00",
        "opencode-go": "#3B82F6",
        "commandcode": "#A04DFD",
    ]

    public static func hex(for provider: String) -> String {
        hexByProvider[provider] ?? "#7C7C80"
    }
}
