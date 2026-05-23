//
//  NotificationsView.swift
//  Aidoku
//
//  Created by Kiro on 5/23/26.
//

import SwiftUI
import AidokuRunner

struct NotificationsView: View {
    @State private var notificationsEnabled = false
    @State private var groupingEnabled = UserDefaults.standard.bool(forKey: "Notifications.grouping")
    @State private var richNotificationsEnabled = UserDefaults.standard.bool(forKey: "Notifications.richNotifications")
    @State private var showHistory = false
    
    @EnvironmentObject private var path: NavigationCoordinator
    
    var body: some View {
        List {
            Section {
                if notificationsEnabled {
                    HStack {
                        Text(NSLocalizedString("NOTIFICATIONS_ENABLED"))
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                    
                    Button {
                        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(settingsUrl)
                        }
                    } label: {
                        HStack {
                            Text(NSLocalizedString("OPEN_SETTINGS"))
                            Spacer()
                            Image(systemName: "arrow.up.forward.app")
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    Button {
                        Task {
                            let granted = await NotificationManager.shared.requestAuthorization(showErrorAlert: true)
                            notificationsEnabled = granted
                        }
                    } label: {
                        HStack {
                            Text(NSLocalizedString("ENABLE_NOTIFICATIONS"))
                            Spacer()
                            Image(systemName: "bell.badge")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } header: {
                Text(NSLocalizedString("PERMISSIONS"))
            } footer: {
                Text(NSLocalizedString("NOTIFICATIONS_PERMISSION_TEXT"))
            }
            
            Section {
                Toggle(NSLocalizedString("GROUP_NOTIFICATIONS"), isOn: $groupingEnabled)
                    .onChange(of: groupingEnabled) { newValue in
                        UserDefaults.standard.set(newValue, forKey: "Notifications.grouping")
                    }
                
                Toggle(NSLocalizedString("RICH_NOTIFICATIONS"), isOn: $richNotificationsEnabled)
                    .onChange(of: richNotificationsEnabled) { newValue in
                        UserDefaults.standard.set(newValue, forKey: "Notifications.richNotifications")
                    }
            } header: {
                Text(NSLocalizedString("NOTIFICATION_STYLE"))
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("GROUP_NOTIFICATIONS_TEXT"))
                    Text(NSLocalizedString("RICH_NOTIFICATIONS_TEXT"))
                }
            }
            
            Section {
                NavigationLink {
                    NotificationHistoryView()
                } label: {
                    HStack {
                        Text(NSLocalizedString("NOTIFICATION_HISTORY"))
                        Spacer()
                        let count = NotificationManager.shared.getNotificationHistory().count
                        if count > 0 {
                            Text("\(count)")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Button(role: .destructive) {
                    confirmClearHistory()
                } label: {
                    Text(NSLocalizedString("CLEAR_NOTIFICATION_HISTORY"))
                }
            } header: {
                Text(NSLocalizedString("HISTORY"))
            }
            
            Section {
                Text(NSLocalizedString("NOTIFICATIONS_INFO_TEXT"))
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            
            Section {
                Button {
                    sendTestNotification()
                } label: {
                    HStack {
                        Text(NSLocalizedString("SEND_TEST_NOTIFICATION"))
                        Spacer()
                        Image(systemName: "paperplane")
                            .foregroundColor(.secondary)
                    }
                }
                .disabled(!notificationsEnabled)
            } header: {
                Text(NSLocalizedString("ADVANCED"))
            } footer: {
                Text(NSLocalizedString("TEST_NOTIFICATION_TEXT"))
            }
        }
        .navigationTitle(NSLocalizedString("NOTIFICATIONS"))
        .task {
            notificationsEnabled = await NotificationManager.shared.checkAuthorizationStatus()
        }
    }
    
    private func confirmClearHistory() {
        let alert = UIAlertController(
            title: NSLocalizedString("CLEAR_NOTIFICATION_HISTORY"),
            message: NSLocalizedString("CLEAR_NOTIFICATION_HISTORY_TEXT"),
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("CLEAR"),
            style: .destructive
        ) { _ in
            NotificationManager.shared.clearNotificationHistory()
        })
        
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("CANCEL"),
            style: .cancel
        ))
        
        path.present(alert, animated: true)
    }
    
    private func sendTestNotification() {
        Task {
            await NotificationManager.shared.sendTestNotification()
            
            // Show confirmation
            let alert = UIAlertController(
                title: NSLocalizedString("TEST_NOTIFICATION_SENT"),
                message: NSLocalizedString("TEST_NOTIFICATION_SENT_TEXT"),
                preferredStyle: .alert
            )
            
            alert.addAction(UIAlertAction(
                title: NSLocalizedString("OK"),
                style: .default
            ))
            
            await MainActor.run {
                path.present(alert, animated: true)
            }
        }
    }
}

struct NotificationHistoryView: View {
    @State private var history: [NotificationManager.NotificationHistoryItem] = []
    
    var body: some View {
        List {
            if history.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "bell.slash")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text(NSLocalizedString("NO_NOTIFICATION_HISTORY"))
                            .font(.headline)
                        Text(NSLocalizedString("NO_NOTIFICATION_HISTORY_TEXT"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
            } else {
                ForEach(history, id: \.id) { item in
                    NotificationHistoryRow(item: item)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                removeItem(item)
                            } label: {
                                Label(NSLocalizedString("DELETE"), systemImage: "trash")
                            }
                        }
                }
            }
        }
        .navigationTitle(NSLocalizedString("NOTIFICATION_HISTORY"))
        .onAppear {
            loadHistory()
        }
    }
    
    private func loadHistory() {
        history = NotificationManager.shared.getNotificationHistory()
    }
    
    private func removeItem(_ item: NotificationManager.NotificationHistoryItem) {
        NotificationManager.shared.removeFromHistory(id: item.id)
        loadHistory()
    }
}

struct NotificationHistoryRow: View {
    let item: NotificationManager.NotificationHistoryItem
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Cover image
            if let coverUrl = item.coverUrl {
                SourceImageView(
                    imageUrl: coverUrl,
                    width: 50,
                    height: 70,
                    downsampleWidth: 100
                )
                .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 50, height: 70)
                    .overlay(
                        Image(systemName: "book.fill")
                            .foregroundColor(.secondary)
                    )
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.mangaTitle)
                    .font(.headline)
                    .lineLimit(2)
                
                if item.chapterCount == 1 {
                    Text(item.chapterTitles.first ?? "")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else {
                    Text(String(format: NSLocalizedString("NEW_CHAPTERS_AVAILABLE"), item.chapterCount))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Text(item.timestamp, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button {
                openManga()
            } label: {
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
    
    private func openManga() {
        guard let source = SourceManager.shared.source(for: item.sourceId) else {
            return
        }
        
        Task { @MainActor in
            do {
                let manga = try await source.getMangaUpdate(
                    manga: AidokuRunner.Manga(
                        sourceKey: item.sourceId,
                        key: item.mangaId,
                        title: item.mangaTitle
                    ),
                    needsDetails: true,
                    needsChapters: false
                )
                
                if let navigationController = (UIApplication.shared.firstKeyWindow?.rootViewController as? UITabBarController)?
                    .selectedViewController as? UINavigationController {
                    navigationController.pushViewController(
                        MangaViewController(
                            source: source,
                            manga: manga,
                            parent: navigationController.topViewController,
                            chapterKey: nil,
                            openAction: nil
                        ),
                        animated: true
                    )
                }
            } catch {
                LogManager.logger.error("Failed to open manga from history: \(error)")
            }
        }
    }
}
