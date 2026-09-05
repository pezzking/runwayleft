import Foundation

/// Stores secrets as owner-only files under Application Support.
///
/// Not the Keychain on purpose: this app is ad-hoc signed, so its designated
/// requirement changes on every rebuild and each install would trigger a
/// Keychain access prompt. A 0600 file matches how `~/.codex/auth.json` and
/// `~/.claude` already hold credentials this app reads. Move to the Keychain
/// once the app has a stable signing identity.
struct CredentialStore {
    let directory: URL

    init(directory: URL? = nil) {
        if let directory = directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            self.directory = base.appendingPathComponent("RunwayLeft", isDirectory: true)
        }
    }

    private func url(for name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    func load(_ name: String) -> String? {
        guard let data = try? Data(contentsOf: url(for: name)),
              let text = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func save(_ value: String, as name: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            delete(name)
            return
        }
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let target = url(for: name)
        try? Data(trimmed.utf8).write(to: target, options: .atomic)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
    }

    func delete(_ name: String) {
        try? FileManager.default.removeItem(at: url(for: name))
    }

    static let liteLLMKeyFile = "litellm.key"
}
