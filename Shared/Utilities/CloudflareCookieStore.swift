//
//  CloudflareCookieStore.swift
//  Aidoku
//

import Foundation
import WebKit

/// Persists and syncs Cloudflare clearance cookies between URLSession and WKWebView.
enum CloudflareCookieStore {
    private static let persistedCookiesKey = "Cloudflare.persistedCookies"

    private static let cloudflareCookieNames: Set<String> = [
        "cf_clearance",
        "__cf_bm",
        "__cflb",
        "__cfduid"
    ]

    // MARK: - Public API

    /// Clears persisted Cloudflare cookies (e.g. when clearing network cache).
    static func clearPersistedCookies() {
        UserDefaults.standard.removeObject(forKey: persistedCookiesKey)
    }

    /// Restores saved cookies into `HTTPCookieStorage` on app launch.
    static func restorePersistedCookies() {
        HTTPCookieStorage.shared.cookieAcceptPolicy = .always
        for cookie in loadPersistedCookies() where !cookie.isExpired {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
    }

    static func hasValidClearance(for url: URL) -> Bool {
        cookies(for: url).contains { $0.name == "cf_clearance" && !$0.isExpired }
    }

    /// Cookies applicable to `url` from shared storage and persisted backup.
    static func cookies(for url: URL) -> [HTTPCookie] {
        var byName: [String: HTTPCookie] = [:]
        for cookie in HTTPCookieStorage.shared.cookies(for: url) ?? [] {
            byName[cookie.name] = cookie
        }
        for cookie in loadPersistedCookies() where cookie.matches(url: url) && !cookie.isExpired {
            byName[cookie.name] = cookie
        }
        return Array(byName.values)
    }

    /// Saves clearance cookies from a WebView session for future requests.
    static func saveCookies(from webViewCookies: [HTTPCookie], for url: URL) {
        let relevant = relevantCookies(from: webViewCookies, for: url)
        guard !relevant.isEmpty else { return }

        for cookie in relevant {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
        persistCookies(relevant, for: url)
    }

    @MainActor
    static func injectCookies(into webView: WKWebView, for url: URL) async {
        let cookies = cookies(for: url)
        guard !cookies.isEmpty else { return }

        let store = webView.configuration.websiteDataStore.httpCookieStore
        for cookie in cookies {
            await store.setCookie(cookie)
        }
    }

    /// Whether the WebView obtained a usable Cloudflare clearance cookie.
    static func foundClearance(
        in webViewCookies: [HTTPCookie],
        for url: URL
    ) -> HTTPCookie? {
        let oldCookie = cookies(for: url).first { $0.name == "cf_clearance" }

        return webViewCookies.first { cookie in
            guard cookie.name == "cf_clearance", cookie.matches(url: url) else { return false }
            guard let oldCookie else { return true }
            // Accept unchanged cookie if still valid (returning visitor / app restart).
            if cookie.value == oldCookie.value {
                return !oldCookie.isExpired
            }
            return true
        }
    }

    // MARK: - Persistence

    private static func persistCookies(_ cookies: [HTTPCookie], for url: URL) {
        guard let host = url.host?.lowercased() else { return }

        var allHosts = loadPersistedCookieArchive()
        var hostCookies = allHosts[host] ?? [:]

        for cookie in cookies where cloudflareCookieNames.contains(cookie.name) || cookie.matches(url: url) {
            if let encoded = encode(cookie) {
                hostCookies[cookie.name] = encoded
            }
        }

        allHosts[host] = hostCookies
        savePersistedCookieArchive(allHosts)
    }

    private static func loadPersistedCookies() -> [HTTPCookie] {
        loadPersistedCookieArchive().values.flatMap(\.values).compactMap(decode)
    }

    private static func loadPersistedCookieArchive() -> [String: [String: [String: String]]] {
        guard let data = UserDefaults.standard.data(forKey: persistedCookiesKey) else { return [:] }
        return (try? JSONDecoder().decode([String: [String: [String: String]]].self, from: data)) ?? [:]
    }

    private static func savePersistedCookieArchive(_ archive: [String: [String: [String: String]]]) {
        let pruned = pruneExpired(from: archive)
        guard let data = try? JSONEncoder().encode(pruned) else { return }
        UserDefaults.standard.set(data, forKey: persistedCookiesKey)
    }

    private static func pruneExpired(
        from archive: [String: [String: [String: String]]]
    ) -> [String: [String: [String: String]]] {
        archive.mapValues { cookies in
            cookies.filter { _, encoded in
                guard let cookie = decode(encoded) else { return false }
                return !cookie.isExpired
            }
        }.filter { !$0.value.isEmpty }
    }

    private static func encode(_ cookie: HTTPCookie) -> [String: String]? {
        guard let properties = cookie.properties else { return nil }
        var encoded: [String: String] = [:]
        for (key, value) in properties {
            switch value {
            case let string as String:
                encoded[key.rawValue] = string
            case let date as Date:
                encoded[key.rawValue] = String(date.timeIntervalSince1970)
            case let number as NSNumber:
                encoded[key.rawValue] = number.stringValue
            default:
                break
            }
        }
        return encoded.isEmpty ? nil : encoded
    }

    private static func decode(_ encoded: [String: String]) -> HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [:]
        for (key, value) in encoded {
            let propertyKey = HTTPCookiePropertyKey(key)
            if propertyKey == .expires, let interval = TimeInterval(value) {
                properties[propertyKey] = Date(timeIntervalSince1970: interval)
            } else if propertyKey == .maximumAge, let age = Int(value) {
                properties[propertyKey] = age
            } else if propertyKey == .version, let version = Int(value) {
                properties[propertyKey] = version
            } else if propertyKey == .discard || propertyKey == .secure {
                properties[propertyKey] = value == "TRUE" || value == "1"
            } else {
                properties[propertyKey] = value
            }
        }
        return HTTPCookie(properties: properties)
    }

    private static func relevantCookies(
        from webViewCookies: [HTTPCookie],
        for url: URL
    ) -> [HTTPCookie] {
        webViewCookies.filter { cookie in
            cloudflareCookieNames.contains(cookie.name) || cookie.matches(url: url)
        }
    }
}

private extension HTTPCookie {
    var isExpired: Bool {
        if let expiresDate {
            return expiresDate < Date()
        }
        return false
    }

    func matches(url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let domain = domain.lowercased().hasPrefix(".") ? String(domain.dropFirst()) : domain.lowercased()
        return host == domain || host.hasSuffix("." + domain) || domain.hasSuffix(host)
    }
}

private extension WKHTTPCookieStore {
    func setCookie(_ cookie: HTTPCookie) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            setCookie(cookie) {
                continuation.resume()
            }
        }
    }
}
