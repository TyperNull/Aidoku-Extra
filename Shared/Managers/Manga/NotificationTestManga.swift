//
//  NotificationTestManga.swift
//  Aidoku
//
//  Dummy library entry used to verify chapter notifications fire on library refresh.
//

import AidokuRunner
import Foundation

enum NotificationTestManga {
    static let sourceId = "aidoku-notification-test"
    static let mangaId = "notification-test-manga"
    private static let chapterCounterKey = "Notifications.testManga.chapterCounter"

    static func isTestManga(sourceId: String, mangaId: String) -> Bool {
        sourceId == Self.sourceId && mangaId == Self.mangaId
    }

    static func isInLibrary() async -> Bool {
        await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.hasLibraryManga(
                sourceId: sourceId,
                mangaId: mangaId,
                context: context
            )
        }
    }

    static func addToLibrary() async {
        let initialChapterNumber = nextChapterNumber()
        let manga = AidokuRunner.Manga(
            sourceKey: sourceId,
            key: mangaId,
            title: NSLocalizedString("NOTIFICATION_TEST_MANGA_TITLE"),
            description: NSLocalizedString("NOTIFICATION_TEST_MANGA_DESCRIPTION"),
            status: .ongoing,
            chapters: [makeChapter(number: initialChapterNumber)]
        )

        await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.addToLibrary(
                manga: manga,
                chapters: manga.chapters ?? [],
                context: context
            )

            let defaultCategory = UserDefaults.standard.string(forKey: "Library.defaultCategory")
            if let defaultCategory, CoreDataManager.shared.hasCategory(title: defaultCategory, context: context) {
                CoreDataManager.shared.addCategoriesToManga(
                    sourceId: sourceId,
                    mangaId: mangaId,
                    categories: [defaultCategory],
                    context: context
                )
            }

            try? context.save()
        }

        NotificationManager.shared.setNotificationEnabled(true, sourceId: sourceId, mangaId: mangaId)
        UserDefaults.standard.set(true, forKey: NotificationManager.globalSettingKey)
        UserDefaults.standard.set(initialChapterNumber, forKey: chapterCounterKey)

        NotificationCenter.default.post(name: .updateLibrary, object: nil)
    }

    static func removeFromLibrary() async {
        await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.removeManga(sourceId: sourceId, mangaId: mangaId, context: context)
            try? context.save()
        }
        UserDefaults.standard.removeObject(forKey: chapterCounterKey)
        NotificationManager.shared.setNotificationEnabled(false, sourceId: sourceId, mangaId: mangaId)
        await NotificationManager.shared.clearNotifications(sourceId: sourceId, mangaId: mangaId)
        NotificationCenter.default.post(name: .updateLibrary, object: nil)
    }

    /// Simulates a new chapter on library refresh. Returns a notification summary when a new chapter was added.
    static func processLibraryRefresh() async -> (
        sourceId: String,
        mangaId: String,
        title: String,
        chapterCount: Int,
        chapters: [AidokuRunner.Chapter],
        coverUrl: String?
    )? {
        guard await isInLibrary() else { return nil }

        let chapterNumber = nextChapterNumber()
        let newChapter = makeChapter(number: chapterNumber)

        return await CoreDataManager.shared.container.performBackgroundTask { context in
            guard
                let libraryObject = CoreDataManager.shared.getLibraryManga(
                    sourceId: sourceId,
                    mangaId: mangaId,
                    context: context
                ),
                let mangaObject = libraryObject.manga
            else {
                return nil
            }

            let existingChapters = CoreDataManager.shared.getChapters(
                sourceId: sourceId,
                mangaId: mangaId,
                context: context
            ).map { $0.toNewChapter() }

            let allChapters = existingChapters + [newChapter]
            let newChapterObjects = CoreDataManager.shared.setChapters(
                allChapters,
                sourceId: sourceId,
                mangaId: mangaId,
                context: context
            )

            guard !newChapterObjects.isEmpty else { return nil }

            for chapterObject in newChapterObjects {
                CoreDataManager.shared.createMangaUpdate(
                    sourceId: sourceId,
                    mangaId: mangaId,
                    chapterObject: chapterObject,
                    context: context
                )
            }

            libraryObject.lastChapter = newChapter.dateUploaded
            libraryObject.lastUpdatedChapters = .now
            libraryObject.lastUpdated = .now

            try? context.save()
            UserDefaults.standard.set(chapterNumber, forKey: chapterCounterKey)

            let title = mangaObject.title.isEmpty
                ? NSLocalizedString("NOTIFICATION_TEST_MANGA_TITLE")
                : mangaObject.title

            return (
                sourceId: sourceId,
                mangaId: mangaId,
                title: title,
                chapterCount: newChapterObjects.count,
                chapters: newChapterObjects.map { $0.toNewChapter() },
                coverUrl: nil
            )
        }
    }

    private static func nextChapterNumber() -> Float {
        let stored = UserDefaults.standard.double(forKey: chapterCounterKey)
        return stored > 0 ? Float(stored + 1) : 1
    }

    private static func makeChapter(number: Float) -> AidokuRunner.Chapter {
        .init(
            key: "test-chapter-\(Int(number))",
            title: String(format: NSLocalizedString("NOTIFICATION_TEST_CHAPTER_TITLE"), Int(number)),
            chapterNumber: number,
            volumeNumber: nil,
            dateUploaded: .now
        )
    }
}
