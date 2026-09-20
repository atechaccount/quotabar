import Foundation

/// Where preferences are read and written.
///
/// The app uses `UserDefaults.standard`. Tests and the offscreen render check
/// use `InMemoryPreferenceStore` instead: a scratch `UserDefaults` suite leaves
/// a real plist behind in `~/Library/Preferences` for every run, which is both
/// litter on the user's disk and a write outside the repository.
protocol PreferenceStore: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
    func string(forKey key: String) -> String?
    func double(forKey key: String) -> Double
    func bool(forKey key: String) -> Bool
    func stringArray(forKey key: String) -> [String]?
}

extension UserDefaults: PreferenceStore {}

final class InMemoryPreferenceStore: PreferenceStore {
    private var values: [String: Any] = [:]

    init(_ values: [String: Any] = [:]) {
        self.values = values
    }

    func object(forKey key: String) -> Any? { values[key] }

    func set(_ value: Any?, forKey key: String) {
        if let value {
            values[key] = value
        } else {
            values.removeValue(forKey: key)
        }
    }

    func string(forKey key: String) -> String? { values[key] as? String }
    func double(forKey key: String) -> Double { values[key] as? Double ?? 0 }
    func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
    func stringArray(forKey key: String) -> [String]? { values[key] as? [String] }
}
