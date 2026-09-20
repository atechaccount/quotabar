import Foundation

public enum QuotaParser {
    public static func decode(_ data: Data) throws -> QuotaSnapshot {
        try JSONDecoder().decode(QuotaSnapshot.self, from: data)
    }

    public static func decode(_ string: String) throws -> QuotaSnapshot {
        try decode(Data(string.utf8))
    }

    public static func decodeFile(atPath path: String) throws -> QuotaSnapshot {
        try decode(Data(contentsOf: URL(fileURLWithPath: path)))
    }
}
