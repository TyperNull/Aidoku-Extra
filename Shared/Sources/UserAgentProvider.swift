//
//  UserAgentProvider.swift
//  Aidoku
//
//  Created by Skitty on 3/24/25.
//

import WebKit

struct UserAgentPreset: Identifiable, Equatable {
    let id: String
    let title: String
    let userAgent: String
}

class UserAgentProvider {
    static let shared = UserAgentProvider()

    static let customUserAgentKey = "General.customUserAgent"

    /// Preset strings that commonly work with Cloudflare-protected sources.
    static let presets: [UserAgentPreset] = [
        UserAgentPreset(
            id: "chrome_windows",
            title: NSLocalizedString("USER_AGENT_CHROME_WINDOWS", comment: ""),
            userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
        ),
        UserAgentPreset(
            id: "chrome_android",
            title: NSLocalizedString("USER_AGENT_CHROME_ANDROID", comment: ""),
            userAgent: "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36"
        ),
        UserAgentPreset(
            id: "firefox_windows",
            title: NSLocalizedString("USER_AGENT_FIREFOX_WINDOWS", comment: ""),
            userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:133.0) Gecko/20100101 Firefox/133.0"
        ),
        UserAgentPreset(
            id: "safari_ios",
            title: NSLocalizedString("USER_AGENT_SAFARI_IOS", comment: ""),
            userAgent: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
        ),
        UserAgentPreset(
            id: "edge_windows",
            title: NSLocalizedString("USER_AGENT_EDGE_WINDOWS", comment: ""),
            userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36 Edg/131.0.0.0"
        )
    ]

    static func storedUserAgent() -> String {
        UserDefaults.standard.string(forKey: customUserAgentKey) ?? ""
    }

    static func setUserAgent(_ value: String?) {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: customUserAgentKey)
        } else {
            UserDefaults.standard.set(trimmed, forKey: customUserAgentKey)
        }
    }

    static func selectionLabel(for stored: String) -> String {
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return NSLocalizedString("USER_AGENT_DEFAULT", comment: "")
        }
        if let preset = presets.first(where: { $0.userAgent == trimmed }) {
            return preset.title
        }
        return NSLocalizedString("USER_AGENT_CUSTOM_LABEL", comment: "")
    }

    private var task: Task<String?, Never>?
    private var userAgent: String?

    private init() {
        task = Task {
            await fetchUserAgent()
        }
    }

    @MainActor
    private func fetchUserAgent() async -> String? {
        let webView = WKWebView()
        do {
            let userAgent = try await webView.evaluateJavaScript("navigator.userAgent") as? String
            self.userAgent = userAgent
            return userAgent
        } catch {
            LogManager.logger.error("Error getting user agent: \(error)")
            return nil
        }
    }

    /// Get the user agent to use (custom if set, otherwise default)
    func getUserAgent() async -> String {
        let customUA = UserDefaults.standard.string(forKey: Self.customUserAgentKey)
        if let customUA, !customUA.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return customUA
        }

        if let userAgent {
            return userAgent
        }
        return await task?.value ?? ""
    }

    /// Get the user agent synchronously (blocking)
    func getUserAgentBlocking() -> String {
        let customUA = UserDefaults.standard.string(forKey: Self.customUserAgentKey)
        if let customUA, !customUA.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return customUA
        }

        if let userAgent {
            return userAgent
        }
        return BlockingTask {
            await self.getUserAgent()
        }.get()
    }
}
