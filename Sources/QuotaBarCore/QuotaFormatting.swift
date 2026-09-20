import Foundation

public enum QuotaFormatting {
    public static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    public static func date(from value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }
        return ISO8601DateFormatter().date(from: value)
    }

    public static func age(since date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 5 { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h \(minutes % 60)m ago" }
        return "\(hours / 24)d \(hours % 24)h ago"
    }

    public static func resetDescription(_ date: Date, now: Date = Date()) -> String {
        let seconds = Int(date.timeIntervalSince(now))
        guard seconds > 0 else { return "reset due" }
        let minutes = max(1, seconds / 60)
        if minutes < 60 { return "resets in \(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "resets in \(hours)h \(minutes % 60)m" }
        return "resets in \(hours / 24)d \(hours % 24)h"
    }

    /// The one countdown line in the interface: "Resets in 4h 54m" for a raw
    /// reset stamp, and nil when the provider reports no reset time at all.
    ///
    /// Nil rather than a placeholder, so a caller with no room for one - the
    /// overview rows - can simply draw nothing, while the provider pages, which
    /// have a reserved line to fill, say so in words.
    public static func resetLine(from raw: String?, now: Date = Date()) -> String? {
        guard let date = date(from: raw) else { return nil }
        let sentence = resetDescription(date, now: now)
        guard let first = sentence.first else { return nil }
        return first.uppercased() + sentence.dropFirst()
    }
}

public extension QuotaFormatting {
    /// "every 5h" / "every 7d" - makes it obvious which windows come back often.
    static func cadence(windowSeconds: Double?) -> String? {
        guard let windowSeconds, windowSeconds > 0 else { return nil }
        let seconds = Int(windowSeconds.rounded())
        if seconds % 604_800 == 0 { return "every \(seconds / 604_800)w" }
        if seconds % 86_400 == 0 { return "every \(seconds / 86_400)d" }
        if seconds % 3_600 == 0 { return "every \(seconds / 3_600)h" }
        return "every \(max(1, seconds / 60))m"
    }
}
