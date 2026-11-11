import AppKit
import WebKit
import Combine

@MainActor
public final class ProfileManager: ObservableObject {
    public static let shared = ProfileManager()

    @Published public private(set) var profiles: [Profile] = [
        .personal,
        .work,
        .incognito
    ]

    @Published public private(set) var activeProfileId: UUID = Profile.personal.id
    public private(set) var previousActiveProfileId: UUID?

    public var activeProfile: Profile {
        profiles.first(where: { $0.id == activeProfileId }) ?? Profile.personal
    }

    private var dataStores: [UUID: WKWebsiteDataStore] = [:]

    public init() {}

    public func dataStore(for profile: Profile) -> WKWebsiteDataStore {
        // Ephemeral profiles and E2E test runs never touch the default (user) store.
        // In test mode every profile gets its own nonPersistent store, which keeps
        // per-profile cookie/storage isolation semantics intact without disk state.
        if profile.isEphemeral {
            return .nonPersistent()
        }
        if TestEnvironment.isEnabled {
            if let existing = dataStores[profile.id] {
                return existing
            }
            let store = WKWebsiteDataStore.nonPersistent()
            dataStores[profile.id] = store
            return store
        }
        if profile.id == Profile.personal.id {
            return .default()
        }
        if let existing = dataStores[profile.id] {
            return existing
        }
        let store = WKWebsiteDataStore(forIdentifier: profile.id)
        dataStores[profile.id] = store
        return store
    }

    public func configuration(for profile: Profile) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore(for: profile)
        // WKWebView's default UA omits the "Version/x Safari/605.1.15" suffix, so
        // UA-sniffing sites (Google et al.) treat the browser as unsupported and
        // serve legacy pages. Appending the same token Safari sends — versioned
        // from the installed Safari — makes the UA truthfully identify as WebKit.
        config.applicationNameForUserAgent = "Version/\(Self.safariVersion) Safari/605.1.15"
        config.allowsAirPlayForMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = .all
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        config.defaultWebpagePreferences = preferences
        return config
    }

    /// Version of the installed Safari (e.g. "26.6.2") for the UA suffix.
    /// WebKit exposes no public version API; Safari's bundle is always present on
    /// macOS and tracks the WebKit engine version we actually run.
    private static let safariVersion: String = {
        let version = Bundle(path: "/Applications/Safari.app")?
            .infoDictionary?["CFBundleShortVersionString"] as? String
        return version ?? "26.0"
    }()

    @discardableResult
    public func createProfile(name: String, badge: String? = nil, isEphemeral: Bool = false) -> Profile {
        let badgeText = (badge ?? String(name.prefix(4))).lowercased()
        let profile = Profile(
            name: name,
            badge: badgeText,
            iconName: isEphemeral ? "eyeglasses" : "folder.fill",
            isEphemeral: isEphemeral
        )
        profiles.append(profile)
        return profile
    }

    public func setActiveProfile(id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        if activeProfileId != id {
            previousActiveProfileId = activeProfileId
        }
        activeProfileId = id
    }

    public func profile(named name: String) -> Profile? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return profiles.first {
            $0.name.lowercased() == trimmed ||
            $0.badge.lowercased() == trimmed ||
            $0.id.uuidString.lowercased() == trimmed
        }
    }
}
