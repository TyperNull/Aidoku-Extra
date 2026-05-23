//
//  NotificationManager.swift
//  Aidoku
//
//  Created by Kiro on 5/23/26.
//

import Foundation
import UserNotifications
import AidokuRunner
import UIKit

@MainActor
class NotificationManager {
    static let shared = NotificationManager()

    // Notification history storage
    struct NotificationHistoryItem: Codable {
        let id: String
        let sourceId: String
        let mangaId: String
        let mangaTitle: String
        let chapterCount: Int
        let chapterTitles: [String]
        let timestamp: Date
        let coverUrl: String?
    }

    private init() {}

    /// Request notification permissions from the user
    func requestAuthorization(showErrorAlert: Bool = false) async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            
            if !granted && showErrorAlert {
                await showPermissionDeniedAlert()
            }
            
            return granted
        } catch {
            LogManager.logger.error("Failed to request notification authorization: \(error)")
            if showErrorAlert {
                await showPermissionDeniedAlert()
            }
            return false
        }
    }
    
    /// Show alert when notification permission is denied
    private func showPermissionDeniedAlert() async {
        let alert = UIAlertController(
            title: NSLocalizedString("NOTIFICATIONS_DISABLED"),
            message: NSLocalizedString("NOTIFICATIONS_DISABLED_TEXT"),
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("OPEN_SETTINGS"),
            style: .default
        ) { _ in
            if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsUrl)
            }
        })
        
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("CANCEL"),
            style: .cancel
        ))
        
        if let topViewController = UIApplication.shared.firstKeyWindow?.rootViewController {
            var presentingVC = topViewController
            while let presented = presentingVC.presentedViewController {
                presentingVC = presented
            }
            presentingVC.present(alert, animated: true)
        }
    }

    /// Check if notifications are authorized
    func checkAuthorizationStatus() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized
    }

    /// Check if notifications are enabled for a specific manga
    func isNotificationEnabled(sourceId: String, mangaId: String) -> Bool {
        UserDefaults.standard.bool(forKey: "Notifications.enabled.\(sourceId).\(mangaId)")
    }

    /// Enable or disable notifications for a specific manga
    func setNotificationEnabled(_ enabled: Bool, sourceId: String, mangaId: String) {
        UserDefaults.standard.set(enabled, forKey: "Notifications.enabled.\(sourceId).\(mangaId)")
    }
    
    /// Check if notification grouping is enabled
    var isGroupingEnabled: Bool {
        UserDefaults.standard.bool(forKey: "Notifications.grouping")
    }
    
    /// Check if rich notifications (with images) are enabled
    var isRichNotificationsEnabled: Bool {
        UserDefaults.standard.bool(forKey: "Notifications.richNotifications")
    }

    /// Send a notification for new chapters
    func sendChapterNotification(manga: AidokuRunner.Manga, chapters: [AidokuRunner.Chapter]) async {
        guard await checkAuthorizationStatus() else { return }
        guard isNotificationEnabled(sourceId: manga.sourceKey, mangaId: manga.key) else { return }

        let content = UNMutableNotificationContent()
        content.title = manga.title

        if chapters.count == 1 {
            let chapter = chapters[0]
            content.body = chapter.formattedTitle(forceMode: .default)
        } else {
            content.body = String(format: NSLocalizedString("NEW_CHAPTERS_AVAILABLE"), chapters.count)
        }

        content.sound = .default
        
        // Add grouping if enabled
        if isGroupingEnabled {
            content.threadIdentifier = "manga-updates"
            content.categoryIdentifier = "MANGA_UPDATE"
        }
        
        // Add rich notification with cover image if enabled
        if isRichNotificationsEnabled, let coverUrl = manga.cover {
            await addCoverAttachment(to: content, coverUrl: coverUrl)
        }

        content.badge = NSNumber(value: await getUnreadNotificationCount() + 1)

        // Add user info for deep linking
        content.userInfo = [
            "sourceId": manga.sourceKey,
            "mangaId": manga.key,
            "type": "newChapter"
        ]

        // Use a unique identifier for each manga
        let identifier = "chapter-\(manga.sourceKey)-\(manga.key)-\(Date().timeIntervalSince1970)"

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)

        do {
            try await UNUserNotificationCenter.current().add(request)
            
            // Save to notification history
            await saveToHistory(
                id: identifier,
                manga: manga,
                chapters: chapters
            )
            
            LogManager.logger.info("Sent notification for \(manga.title): \(chapters.count) new chapter(s)")
        } catch {
            LogManager.logger.error("Failed to send notification: \(error)")
        }
    }
    
    /// Add cover image attachment to notification
    private func addCoverAttachment(to content: UNMutableNotificationContent, coverUrl: String) async {
        guard let url = URL(string: coverUrl) else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            
            // Save to temporary file
            guard let tempDirectory = FileManager.default.temporaryDirectory else { return }
            let tempFile = tempDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
            try data.write(to: tempFile)
            
            // Create attachment
            let attachment = try UNNotificationAttachment(
                identifier: "cover",
                url: tempFile,
                options: [UNNotificationAttachmentOptionsTypeHintKey: "public.jpeg"]
            )
            
            content.attachments = [attachment]
        } catch {
            LogManager.logger.error("Failed to add cover attachment: \(error)")
        }
    }

    /// Get the count of unread notifications (for badge)
    private func getUnreadNotificationCount() async -> Int {
        let deliveredNotifications = await UNUserNotificationCenter.current().deliveredNotifications()
        return deliveredNotifications.count
    }

    /// Clear all notifications
    func clearAllNotifications() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    /// Clear notifications for a specific manga
    func clearNotifications(sourceId: String, mangaId: String) async {
        let deliveredNotifications = await UNUserNotificationCenter.current().deliveredNotifications()
        let identifiersToRemove = deliveredNotifications
            .filter { notification in
                guard
                    let notificationSourceId = notification.request.content.userInfo["sourceId"] as? String,
                    let notificationMangaId = notification.request.content.userInfo["mangaId"] as? String
                else {
                    return false
                }
                return notificationSourceId == sourceId && notificationMangaId == mangaId
            }
            .map { $0.request.identifier }

        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiersToRemove)
    }
    
    // MARK: - Notification History
    
    /// Save notification to history
    private func saveToHistory(id: String, manga: AidokuRunner.Manga, chapters: [AidokuRunner.Chapter]) async {
        var history = getNotificationHistory()
        
        let item = NotificationHistoryItem(
            id: id,
            sourceId: manga.sourceKey,
            mangaId: manga.key,
            mangaTitle: manga.title,
            chapterCount: chapters.count,
            chapterTitles: chapters.map { $0.formattedTitle(forceMode: .default) },
            timestamp: Date(),
            coverUrl: manga.cover
        )
        
        history.insert(item, at: 0)
        
        // Keep only last 100 notifications
        if history.count > 100 {
            history = Array(history.prefix(100))
        }
        
        if let encoded = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(encoded, forKey: "Notifications.history")
        }
    }
    
    /// Get notification history
    func getNotificationHistory() -> [NotificationHistoryItem] {
        guard let data = UserDefaults.standard.data(forKey: "Notifications.history"),
              let history = try? JSONDecoder().decode([NotificationHistoryItem].self, from: data) else {
            return []
        }
        return history
    }
    
    /// Clear notification history
    func clearNotificationHistory() {
        UserDefaults.standard.removeObject(forKey: "Notifications.history")
    }
    
    /// Remove a specific item from history
    func removeFromHistory(id: String) {
        var history = getNotificationHistory()
        history.removeAll { $0.id == id }
        
        if let encoded = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(encoded, forKey: "Notifications.history")
        }
    }
    
    // MARK: - Test Notification
    
    /// Send a test notification to verify notifications are working
    func sendTestNotification() async {
        guard await checkAuthorizationStatus() else { return }
        
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("TEST_NOTIFICATION_TITLE")
        content.body = NSLocalizedString("TEST_NOTIFICATION_BODY")
        content.sound = .default
        
        // Add grouping if enabled
        if isGroupingEnabled {
            content.threadIdentifier = "manga-updates"
            content.categoryIdentifier = "MANGA_UPDATE"
        }
        
        // Add user info
        content.userInfo = [
            "type": "test"
        ]
        
        let identifier = "test-notification-\(Date().timeIntervalSince1970)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            LogManager.logger.info("Sent test notification")
        } catch {
            LogManager.logger.error("Failed to send test notification: \(error)")
        }
    }
}
