import Foundation

/// Small value helpers mirrored from quota-axi's `src/lib/time.js` and
/// `src/lib/secret.js` (quota-axi 0.1.51). Kept as free functions, exactly like
/// the JS originals, so each one stays a one-line diff against upstream.
enum NQTime {
    static func nowIso() -> String {
        ISO8601DateFormatter.nqFractional.string(from: Date())
    }

    /// Mirrors `clampPercent` in quota-axi's `lib/time.js`.
    static func clampPercent(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(100, max(0, value.rounded()))
    }

    /// Mirrors `percentRemaining` in quota-axi's `lib/time.js`.
    static func percentRemaining(_ percentUsed: Double?) -> Double? {
        guard let percentUsed else { return nil }
        return clampPercent(100 - percentUsed)
    }

    /// Mirrors `parseEpochOrIso` in quota-axi's `lib/time.js`: accepts a Unix
    /// epoch-seconds number or an ISO/parseable date string.
    static func parseEpochOrIso(_ value: Double?) -> String? {
        guard let value else { return nil }
        return ISO8601DateFormatter.nqFractional.string(from: Date(timeIntervalSince1970: value))
    }

    static func parseEpochOrIso(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        if let date = parseFlexibleDate(value) {
            return ISO8601DateFormatter.nqFractional.string(from: date)
        }
        return value
    }

    /// Mirrors `retryAfterToIso` in quota-axi's `lib/time.js`: a `Retry-After`
    /// header is either a delta in seconds or an HTTP date.
    static func retryAfterToIso(_ value: String?, now: Date = Date()) -> String? {
        guard let raw = value?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        if let seconds = Double(raw), seconds >= 0 {
            return ISO8601DateFormatter.nqFractional.string(from: now.addingTimeInterval(seconds))
        }
        if let date = parseFlexibleDate(raw) {
            return ISO8601DateFormatter.nqFractional.string(from: date)
        }
        return nil
    }

    private static func parseFlexibleDate(_ value: String) -> Date? {
        if let date = ISO8601DateFormatter.nqFractional.date(from: value) { return date }
        if let date = ISO8601DateFormatter.nqPlain.date(from: value) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value)
    }
}

extension ISO8601DateFormatter {
    static let nqFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let nqPlain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

/// Mirrors `src/lib/secret.js`.
enum NQSecret {
    /// Accept a credential value only when it is a literal secret usable
    /// verbatim in a header. `$`/`!` prefixed values are environment, template,
    /// or command references that must never be resolved or executed.
    static func usableLiteralSecret(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        if value.hasPrefix("!") || value.contains("$") { return nil }
        if value.unicodeScalars.contains(where: { $0.value <= 0x1f || $0.value == 0x7f }) { return nil }
        return value
    }

    /// Strip a credential out of text about to be reported.
    static func redactSecret(_ message: String, _ secret: String) -> String {
        message.replacingOccurrences(of: secret, with: "[redacted]")
    }
}
