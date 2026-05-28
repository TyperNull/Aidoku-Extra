//
//  NotificationsView.swift
//  Aidoku
//
//  Created by typernull on 5/23/26.
//

import SwiftUI
import AidokuRunner

struct NotificationsView: View {
    @State private var notificationsEnabled = false
    @State private var groupingEnabled = UserDefaults.standard.bool(forKey: "Notifications.grouping")
    @State private var richNotificationsEnabled = UserDefaults.standard.bool(forKey: "Notifications.richNotifications")
    @State private var showHistory = false
    @State private var testMangaInLibrary = false
    
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
                if testMangaInLibrary {
                    HStack {
                        Text(NSLocalizedString("NOTIFICATION_TEST_MANGA_IN_LIBRARY"))
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }

                    Button(role: .destructive) {
                        Task {
                            await NotificationTestManga.removeFromLibrary()
                            testMangaInLibrary = false
                        }
                    } label: {
                        Text(NSLocalizedString("REMOVE_NOTIFICATION_TEST_MANGA"))
                    }
                } else {
                    Button {
                        Task {
                            await NotificationTestManga.addToLibrary()
                            testMangaInLibrary = true
                        }
                    } label: {
                        HStack {
                            Text(NSLocalizedString("ADD_NOTIFICATION_TEST_MANGA"))
                            Spacer()
                            Image(systemName: "books.vertical")
                                .foregroundColor(.secondary)
                        }
                    }
                }

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
                Text(
                    testMangaInLibrary
                        ? NSLocalizedString("NOTIFICATION_TEST_MANGA_FOOTER_ACTIVE")
                        : NSLocalizedString("NOTIFICATION_TEST_MANGA_FOOTER")
                )
            }
        }
        .navigationTitle(NSLocalizedString("NOTIFICATIONS"))
        .task {
            notificationsEnabled = await NotificationManager.shared.checkAuthorizationStatus()
            testMangaInLibrary = await NotificationTestManga.isInLibrary()
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
    @State private var updateSections: [MangaUpdatesView.UpdateSection] = []
    @State private var showClearConfirm = false
    
    var body: some View {
        List {
            if history.isEmpty && updateSections.isEmpty {
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
                if !history.isEmpty {
                    Section {
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

                if !updateSections.isEmpty {
                    ForEach(updateSections, id: \.day) { entry in
                        Section {
                            let items = entry.items
                            ForEach(items, id: \.mangaKey) { item in
                                let updates = item.updates
                                if !updates.isEmpty {
                                    Button {
                                        openManga(from: updates)
                                    } label: {
                                        MangaUpdateItemView(updates: updates)
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            removeUpdatesItem(item: item, day: entry.day)
                                        } label: {
                                            Label(NSLocalizedString("DELETE"), systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        } header: {
                            Text(Date.makeRelativeDate(days: entry.day))
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("NOTIFICATION_HISTORY"))
        .onAppear {
            loadHistory()
            Task {
                await loadUpdates()
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    showClearConfirm = true
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .alert(
            NSLocalizedString("CLEAR_NOTIFICATION_HISTORY"),
            isPresented: $showClearConfirm
        ) {
            Button(NSLocalizedString("CLEAR"), role: .destructive) {
                Task {
                    await clearAll()
                }
            }
            Button(NSLocalizedString("CANCEL"), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("CLEAR_NOTIFICATION_HISTORY_TEXT"))
        }
    }
    
    private func loadHistory() {
        history = NotificationManager.shared.getNotificationHistory()
    }
    
    private func removeItem(_ item: NotificationManager.NotificationHistoryItem) {
        NotificationManager.shared.removeFromHistory(id: item.id)
        loadHistory()
    }

    private func clearAll() async {
        NotificationManager.shared.clearNotificationHistory()
        await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.clearUpdates(context: context)
        }
        await MainActor.run {
            history = []
            updateSections = []
        }
    }

    private func loadUpdates() async {
        // Build a set of (sourceId, mangaId) keys that already have notifications,
        // so we only merge in updates for manga that never produced a notification.
        let existingKeys = Set(history.map { "\($0.sourceId)|\($0.mangaId)" })

        let limit = 50

        let newUpdates: [MangaUpdatesView.UpdateInfo] = await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.getRecentMangaUpdates(limit: limit, offset: 0, context: context).compactMap { object -> MangaUpdatesView.UpdateInfo? in
                guard let mangaObj = CoreDataManager.shared.getManga(
                    sourceId: object.sourceId ?? "",
                    mangaId: object.mangaId ?? "",
                    context: context
                ) else {
                    return nil
                }

                let sourceId = object.sourceId ?? ""
                let mangaId = object.mangaId ?? ""
                let key = "\(sourceId)|\(mangaId)"
                if existingKeys.contains(key) {
                    return nil
                }

                return MangaUpdatesView.UpdateInfo(
                    id: object.id,
                    chapterIdentifier: .init(
                        sourceKey: sourceId,
                        mangaKey: mangaId,
                        chapterKey: object.chapterId ?? ""
                    ),
                    date: object.date ?? Date(),
                    manga: mangaObj.toNewManga(),
                    chapter: object.chapter?.toChapter(),
                    viewed: object.viewed
                )
            }
        }

        guard !newUpdates.isEmpty else {
            await MainActor.run {
                updateSections = []
            }
            return
        }

        // Group updates by day and manga, matching MangaUpdatesView behavior.
        let groupedByManga: [String: [MangaUpdatesView.UpdateInfo]] = Dictionary(grouping: newUpdates, by: { $0.manga.uniqueKey })
        var updatesDict: [Int: [String: [MangaUpdatesView.UpdateInfo]]] = [:]

        for (mangaKey, infos) in groupedByManga {
            for info in infos.sorted(by: { $0.date < $1.date }) {
                let day = Calendar.autoupdatingCurrent.dateComponents(
                    Set([Calendar.Component.day]),
                    from: info.date,
                    to: Date.endOfDay()
                ).day ?? 0

                var updatesOfTheDay = updatesDict[day] ?? [:]
                var newValue = updatesOfTheDay[mangaKey] ?? []
                newValue.append(info)
                updatesOfTheDay[mangaKey] = newValue
                updatesDict[day] = updatesOfTheDay
            }
        }

        let sections: [MangaUpdatesView.UpdateSection] = updatesDict
            .map { day, value in
                .init(
                    day: day,
                    items: value
                        .map { .init(mangaKey: $0.key, updates: $0.value) }
                        .sorted { ($0.updates.first?.date ?? Date()) > ($1.updates.first?.date ?? Date()) }
                )
            }
            .sorted { $0.day < $1.day }

        await MainActor.run {
            updateSections = sections
        }
    }

    private func openManga(from updates: [MangaUpdatesView.UpdateInfo]) {
        guard let manga = updates.first?.manga else { return }
        guard let source = SourceManager.shared.source(for: manga.sourceKey) else {
            return
        }

        Task { @MainActor in
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
        }
    }

    private func removeUpdatesItem(item: MangaUpdatesView.Item, day: Int) {
        let identifiers = item.updates.map { $0.chapterIdentifier }

        // Update local state
        var newSections = updateSections
        if let sectionIndex = newSections.firstIndex(where: { $0.day == day }) {
            var section = newSections[sectionIndex]
            section.items.removeAll(where: { $0.mangaKey == item.mangaKey })
            if section.items.isEmpty {
                newSections.remove(at: sectionIndex)
            } else {
                newSections[sectionIndex] = section
            }
        }

        updateSections = newSections

        Task {
            await CoreDataManager.shared.container.performBackgroundTask { context in
                CoreDataManager.shared.removeMangaUpdates(
                    updates: identifiers,
                    context: context
                )
                try? context.save()
            }
        }
    }
}

struct NotificationHistoryRow: View {
    let item: NotificationManager.NotificationHistoryItem
    
    var body: some View {
        Button {
            openManga()
        } label: {
            HStack(alignment: .center, spacing: 12) {
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
                
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                    .imageScale(.medium)
                    .padding(10)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
    
    private func openManga() {
        guard let source = SourceManager.shared.source(for: item.sourceId) else { return }
        guard let navigationController = (UIApplication.shared.firstKeyWindow?.rootViewController as? UITabBarController)?
            .selectedViewController as? UINavigationController else { return }

        // Push immediately so UI feels responsive; MangaView will fetch details/chapters asynchronously.
        let manga = AidokuRunner.Manga(
            sourceKey: item.sourceId,
            key: item.mangaId,
            title: item.mangaTitle
        )

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
}
