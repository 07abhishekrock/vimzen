import AppKit
import WebKit

@MainActor
public enum SecurityManager {

    private static func normalizeDomain(_ input: String) -> String {
        input.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^(https?://)?(www\\.)?", with: "", options: .regularExpression)
            .components(separatedBy: "/").first ?? input
    }

    // MARK: - Clear Cookies

    public static func clearCookies(
        domain: String?,
        profile: Profile,
        tabManager: TabManager
    ) {
        let store = ProfileManager.shared.dataStore(for: profile)
        let cookieStore = store.httpCookieStore

        let isAll = (domain?.lowercased() == "all")
        let targetDomain: String?
        if isAll {
            targetDomain = nil
        } else if let explicit = domain, !explicit.isEmpty {
            targetDomain = normalizeDomain(explicit)
        } else if let host = tabManager.activeTab?.url?.host {
            targetDomain = normalizeDomain(host)
        } else {
            PluginRegistry.shared.showToast(
                NotificationToast(message: "No active domain to clear (specify domain or 'all')", duration: 2.5)
            )
            return
        }

        Task { @MainActor in
            let cookies = await cookieStore.allCookies()
            var deletedCount = 0

            for cookie in cookies {
                if let target = targetDomain {
                    let cookieDomain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
                    if cookieDomain == target || cookieDomain.hasSuffix("." + target) {
                        await cookieStore.deleteCookie(cookie)
                        deletedCount += 1
                    }
                } else {
                    // "all"
                    await cookieStore.deleteCookie(cookie)
                    deletedCount += 1
                }
            }

            let msg = isAll
                ? "Cleared all cookies (\(deletedCount) total) [\(profile.name)]"
                : "Cleared \(deletedCount) cookie\(deletedCount == 1 ? "" : "s") for \(targetDomain ?? "")"

            PluginRegistry.shared.showToast(NotificationToast(message: msg, duration: 2.5))
        }
    }

    // MARK: - Clear Storage (localStorage, IndexedDB, etc.)

    public static func clearStorage(
        domain: String?,
        profile: Profile,
        tabManager: TabManager
    ) {
        let store = ProfileManager.shared.dataStore(for: profile)
        let isAll = (domain?.lowercased() == "all")
        let targetDomain: String?

        if isAll {
            targetDomain = nil
        } else if let explicit = domain, !explicit.isEmpty {
            targetDomain = normalizeDomain(explicit)
        } else if let host = tabManager.activeTab?.url?.host {
            targetDomain = normalizeDomain(host)
        } else {
            PluginRegistry.shared.showToast(
                NotificationToast(message: "No active domain to clear (specify domain or 'all')", duration: 2.5)
            )
            return
        }

        let storageTypes = Set([
            WKWebsiteDataTypeLocalStorage,
            WKWebsiteDataTypeSessionStorage,
            WKWebsiteDataTypeIndexedDBDatabases,
            WKWebsiteDataTypeWebSQLDatabases
        ])

        Task { @MainActor in
            let records = await store.dataRecords(ofTypes: storageTypes)
            let matching: [WKWebsiteDataRecord]

            if let target = targetDomain {
                matching = records.filter {
                    let name = $0.displayName.lowercased()
                    return name == target || name.hasSuffix("." + target) || name.contains(target)
                }
            } else {
                matching = records
            }

            await store.removeData(ofTypes: storageTypes, for: matching)

            let msg = isAll
                ? "Cleared local storage & IndexedDB for all sites [\(profile.name)]"
                : "Cleared storage for \(targetDomain ?? "")"

            PluginRegistry.shared.showToast(NotificationToast(message: msg, duration: 2.5))
        }
    }

    // MARK: - Forget Domain (Nukes cookies, storage, cache & history)

    public static func forget(
        domain: String?,
        profile: Profile,
        tabManager: TabManager
    ) {
        let store = ProfileManager.shared.dataStore(for: profile)
        let cookieStore = store.httpCookieStore

        let targetDomain: String
        if let explicit = domain, !explicit.isEmpty {
            targetDomain = normalizeDomain(explicit)
        } else if let host = tabManager.activeTab?.url?.host {
            targetDomain = normalizeDomain(host)
        } else {
            PluginRegistry.shared.showToast(
                NotificationToast(message: "No active domain to forget (specify domain)", duration: 2.5)
            )
            return
        }

        Task { @MainActor in
            // 1. Delete WebKit website data (storage, cache, service workers)
            let allTypes = WKWebsiteDataStore.allWebsiteDataTypes()
            let records = await store.dataRecords(ofTypes: allTypes)
            let matching = records.filter {
                let name = $0.displayName.lowercased()
                return name == targetDomain || name.hasSuffix("." + targetDomain) || name.contains(targetDomain)
            }
            await store.removeData(ofTypes: allTypes, for: matching)

            // 2. Delete all matching cookies
            let cookies = await cookieStore.allCookies()
            for cookie in cookies {
                let cookieDomain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
                if cookieDomain == targetDomain || cookieDomain.hasSuffix("." + targetDomain) {
                    await cookieStore.deleteCookie(cookie)
                }
            }

            // 3. Clear SQLite history for this domain in active profile
            HistoryStore.shared.clear(profileId: profile.id, scope: .domain(targetDomain))

            PluginRegistry.shared.showToast(
                NotificationToast(
                    message: "Forgot \(targetDomain) (cookies, storage & history purged)",
                    duration: 3.0
                )
            )
        }
    }
}
