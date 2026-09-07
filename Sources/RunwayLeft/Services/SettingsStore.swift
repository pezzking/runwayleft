import Foundation

/// The key-value store behind `UsageManager`'s settings.
///
/// The app passes `UserDefaults.standard`. Tests pass an `InMemorySettingsStore`
/// so nothing is written under `~/Library/Preferences`: cfprefsd keeps an empty
/// plist for every named suite even after `removePersistentDomain(forName:)`.
protocol SettingsStore: AnyObject {
    func object(forKey key: String) -> Any?
    func string(forKey key: String) -> String?
    func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: SettingsStore {}

/// A `SettingsStore` that lives only for the process. Not thread-safe; `UsageManager`
/// touches it from the main thread only.
final class InMemorySettingsStore: SettingsStore {
    private var values: [String: Any]

    init(_ values: [String: Any] = [:]) {
        self.values = values
    }

    func object(forKey key: String) -> Any? {
        values[key]
    }

    func string(forKey key: String) -> String? {
        values[key] as? String
    }

    func set(_ value: Any?, forKey key: String) {
        if let value {
            values[key] = value
        } else {
            values.removeValue(forKey: key)
        }
    }
}
