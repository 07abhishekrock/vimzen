import Foundation

/// Per-domain settings, persisted globally so they apply across all profiles.
/// Stored as sparse overrides ([host: [key: value]]) — anything unset falls back
/// to the key's default. Lookup walks parent domains: a setting on example.com
/// applies to sub.example.com. IP hosts match exactly (no label stripping).
@MainActor
public final class DomainSettingsStore {
    public static let shared = DomainSettingsStore()

    public enum Key: String, CaseIterable {
        case popupsRequireConfirmation = "popups-require-confirmation"
        case javaScriptEnabled = "javascript"
        case muteAudio = "mute-audio"
        case allowInsecureHttp = "allow-insecure-http"
        case skipDownloadConfirmation = "skip-download-confirmation"

        public var defaultValue: Bool {
            switch self {
            case .javaScriptEnabled: return true
            default: return false
            }
        }
    }

    private var overrides: [String: [String: Bool]] = [:]

    private init() {
        load()
    }

    // MARK: - Lookup

    public func value(_ key: Key, forHost host: String?) -> Bool {
        lookup(key, forHost: host).value
    }

    /// Effective value plus whether an override (on this host or a parent domain) set it.
    private func lookup(_ key: Key, forHost host: String?) -> (value: Bool, overridden: Bool) {
        guard var h = host?.lowercased(), !h.isEmpty else {
            return (key.defaultValue, false)
        }
        let isIP = h.allSatisfy { $0.isNumber || $0 == "." }
        while true {
            if let v = overrides[h]?[key.rawValue] { return (v, true) }
            if isIP { return (key.defaultValue, false) }
            guard let dot = h.firstIndex(of: ".") else { return (key.defaultValue, false) }
            h = String(h[h.index(after: dot)...])
        }
    }

    // MARK: - Mutation

    /// Pass nil to remove the override and restore the default.
    public func set(_ key: Key, _ value: Bool?, forHost host: String) {
        let h = host.lowercased()
        if let value = value {
            overrides[h, default: [:]][key.rawValue] = value
        } else {
            overrides[h]?[key.rawValue] = nil
            if overrides[h]?.isEmpty == true { overrides[h] = nil }
        }
        save()
    }

    /// One-line summary for the :domain toast: key=on / key=off / key=default.
    public func summary(forHost host: String) -> String {
        let parts = Key.allCases.map { key -> String in
            let entry = lookup(key, forHost: host)
            let state = entry.overridden ? (entry.value ? "on" : "off") : "default"
            return "\(key.rawValue)=\(state)"
        }
        return "\(host.lowercased()): " + parts.joined(separator: " · ")
    }

    // MARK: - Persistence

    private var fileURL: URL {
        if let testDir = TestEnvironment.dataDirectory {
            return testDir.appendingPathComponent("domain-settings.json")
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("Vimzen", isDirectory: true)
            .appendingPathComponent("domain-settings.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: [String: Bool]].self, from: data) else { return }
        overrides = decoded
    }

    private func save() {
        let url = fileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(overrides) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
