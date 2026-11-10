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

    public var activeProfile: Profile {
        profiles.first(where: { $0.id == activeProfileId }) ?? Profile.personal
    }

    private var dataStores: [UUID: WKWebsiteDataStore] = [:]

    public init() {}

    public func dataStore(for profile: Profile) -> WKWebsiteDataStore {
        if profile.isEphemeral {
            return .nonPersistent()
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
        config.allowsAirPlayForMediaPlayback = true
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        config.defaultWebpagePreferences = preferences
        return config
    }

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
