import Foundation

/// MRU list of executed Ex-commands (canonical names, most recent first),
/// persisted globally and capped at 5 — the command bar's empty-query state.
@MainActor
public final class CommandHistoryStore {
    public static let shared = CommandHistoryStore()

    private let maxEntries = 5
    private var recent: [String] = []

    private init() {
        load()
    }

    public func recentCommands() -> [String] {
        recent
    }

    public func record(_ name: String) {
        recent.removeAll { $0 == name }
        recent.insert(name, at: 0)
        if recent.count > maxEntries {
            recent = Array(recent.prefix(maxEntries))
        }
        save()
    }

    // MARK: - Persistence

    private var fileURL: URL {
        if let testDir = TestEnvironment.dataDirectory {
            return testDir.appendingPathComponent("command-history.json")
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("Vimzen", isDirectory: true)
            .appendingPathComponent("command-history.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else { return }
        recent = Array(decoded.prefix(maxEntries))
    }

    private func save() {
        let url = fileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(recent) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
