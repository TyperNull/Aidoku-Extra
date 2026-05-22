//
//  MigrationBackupManager.swift
//  Aidoku
//
//  Created by Kiro on 5/22/26.
//

import Foundation
import CoreData
import AidokuRunner

final class MigrationBackupManager: Sendable {
    static let shared = MigrationBackupManager()
    
    private let backupDirectory: URL = {
        let appSupport = FileManager.default.applicationSupportDirectory
        let backupDir = appSupport.appendingPathComponent("MigrationBackups")
        try? FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        return backupDir
    }()
    
    private init() {
        // Clean up expired backups on initialization
        Task {
            await cleanupExpiredBackups()
        }
    }
    
    // MARK: - Create Backup
    
    /// Creates a backup snapshot before migration
    func createBackup(
        fromSeries: [AidokuRunner.Manga],
        toSeries: [MangaIdentifier: AidokuRunner.Manga?]
    ) async -> MigrationBackup? {
        let snapshots = await CoreDataManager.shared.container.performBackgroundTask { @Sendable context in
            var snapshots: [MigrationBackup.MangaMigrationSnapshot] = []
            
            for manga in fromSeries {
                guard let snapshot = self.createSnapshot(
                    for: manga,
                    targetManga: toSeries[manga.identifier] ?? nil,
                    context: context
                ) else {
                    continue
                }
                snapshots.append(snapshot)
            }
            
            return snapshots
        }
        
        guard !snapshots.isEmpty else { return nil }
        
        let backup = MigrationBackup(migrations: snapshots)
        
        // Save backup to disk
        do {
            let fileURL = backupDirectory.appendingPathComponent("\(backup.id.uuidString).json")
            let data = try JSONEncoder().encode(backup)
            try data.write(to: fileURL)
            
            LogManager.logger.info("Migration backup created: \(backup.id.uuidString)")
            return backup
        } catch {
            LogManager.logger.error("Failed to save migration backup: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func createSnapshot(
        for manga: AidokuRunner.Manga,
        targetManga: AidokuRunner.Manga?,
        context: NSManagedObjectContext
    ) -> MigrationBackup.MangaMigrationSnapshot? {
        let sourceId = manga.sourceKey
        let mangaId = manga.key
        
        // Get manga object
        guard let mangaObject = CoreDataManager.shared.getManga(
            sourceId: sourceId,
            mangaId: mangaId,
            context: context
        ) else {
            return nil
        }
        
        // Backup manga data
        let mangaData = MigrationBackup.MangaBackupData(
            title: mangaObject.title ?? "",
            author: mangaObject.author,
            artist: mangaObject.artist,
            description: mangaObject.desc,
            tags: mangaObject.tags ?? [],
            coverUrl: mangaObject.cover,
            url: mangaObject.url,
            status: mangaObject.status,
            nsfw: mangaObject.nsfw,
            viewer: mangaObject.viewer,
            lastOpened: CoreDataManager.shared.getLibraryManga(
                sourceId: sourceId,
                mangaId: mangaId,
                context: context
            )?.lastOpened,
            lastUpdated: CoreDataManager.shared.getLibraryManga(
                sourceId: sourceId,
                mangaId: mangaId,
                context: context
            )?.lastUpdated,
            lastRead: CoreDataManager.shared.getLibraryManga(
                sourceId: sourceId,
                mangaId: mangaId,
                context: context
            )?.lastRead,
            dateAdded: CoreDataManager.shared.getLibraryManga(
                sourceId: sourceId,
                mangaId: mangaId,
                context: context
            )?.dateAdded
        )
        
        // Backup chapters
        let chapterObjects = CoreDataManager.shared.getChapters(
            sourceId: sourceId,
            mangaId: mangaId,
            context: context
        )
        let chapters = chapterObjects.map { chapterObj in
            MigrationBackup.ChapterBackupData(
                id: chapterObj.id,
                title: chapterObj.title,
                scanlator: chapterObj.scanlator,
                url: chapterObj.url,
                lang: chapterObj.lang ?? "",
                chapter: chapterObj.chapter?.floatValue,
                volume: chapterObj.volume?.floatValue,
                dateUploaded: chapterObj.dateUploaded,
                sourceOrder: Int(chapterObj.sourceOrder)
            )
        }
        
        // Backup history
        let historyObjects = CoreDataManager.shared.getHistoryForManga(
            sourceId: sourceId,
            mangaId: mangaId,
            context: context
        )
        let history = historyObjects.map { historyObj in
            MigrationBackup.HistoryBackupData(
                chapterId: historyObj.chapterId,
                dateRead: historyObj.dateRead ?? Date.distantPast,
                progress: Int(historyObj.progress),
                total: Int(historyObj.total),
                completed: historyObj.completed,
                scrollPosition: historyObj.scrollPosition?.doubleValue
            )
        }
        
        // Backup categories
        let libraryObject = CoreDataManager.shared.getLibraryManga(
            sourceId: sourceId,
            mangaId: mangaId,
            context: context
        )
        let categories = (libraryObject?.categories?.allObjects as? [CategoryObject])?.map { $0.title } ?? []
        
        // Backup tracking data
        let trackObjects = CoreDataManager.shared.getTracks(
            sourceId: sourceId,
            mangaId: mangaId,
            context: context
        )
        let trackingData = trackObjects.map { trackObj in
            MigrationBackup.TrackBackupData(
                trackerId: Int(trackObj.trackerId),
                trackingId: trackObj.trackingId,
                title: trackObj.title,
                lastChapterRead: trackObj.lastChapterRead?.floatValue,
                status: trackObj.status,
                score: trackObj.score,
                startDate: trackObj.startDate,
                finishDate: trackObj.finishDate
            )
        }
        
        return MigrationBackup.MangaMigrationSnapshot(
            sourceId: sourceId,
            mangaId: mangaId,
            title: manga.title,
            coverUrl: manga.cover,
            mangaData: mangaData,
            chapters: chapters,
            history: history,
            categories: categories,
            trackingData: trackingData.isEmpty ? nil : trackingData,
            targetSourceId: targetManga?.sourceKey,
            targetMangaId: targetManga?.key
        )
    }
    
    // MARK: - Restore Backup
    
    /// Restores manga data from a backup
    func restoreBackup(_ backup: MigrationBackup) async -> Bool {
        guard !backup.isExpired else {
            LogManager.logger.warning("Cannot restore expired backup: \(backup.id.uuidString)")
            return false
        }
        
        let success = await CoreDataManager.shared.container.performBackgroundTask { @Sendable context in
            var allSucceeded = true
            
            for snapshot in backup.migrations {
                if !self.restoreSnapshot(snapshot, context: context) {
                    allSucceeded = false
                }
            }
            
            do {
                try context.save()
            } catch {
                LogManager.logger.error("Failed to save restored backup: \(error.localizedDescription)")
                return false
            }
            
            return allSucceeded
        }
        
        if success {
            // Delete the backup file after successful restore
            await deleteBackup(backup.id)
            NotificationCenter.default.post(name: NSNotification.Name("MigrationRestored"), object: nil)
        }
        
        return success
    }
    
    private func restoreSnapshot(
        _ snapshot: MigrationBackup.MangaMigrationSnapshot,
        context: NSManagedObjectContext
    ) -> Bool {
        // If migration was performed (not copy), remove the target manga
        if let targetSourceId = snapshot.targetSourceId,
           let targetMangaId = snapshot.targetMangaId,
           targetSourceId != snapshot.sourceId || targetMangaId != snapshot.mangaId {
            CoreDataManager.shared.removeManga(
                sourceId: targetSourceId,
                mangaId: targetMangaId,
                context: context
            )
        }
        
        // Restore or create the original manga
        let mangaObject = CoreDataManager.shared.getManga(
            sourceId: snapshot.sourceId,
            mangaId: snapshot.mangaId,
            context: context
        ) ?? {
            let obj = MangaObject(context: context)
            obj.sourceId = snapshot.sourceId
            obj.id = snapshot.mangaId
            return obj
        }()
        
        // Restore manga data
        let data = snapshot.mangaData
        mangaObject.title = data.title
        mangaObject.author = data.author
        mangaObject.artist = data.artist
        mangaObject.desc = data.description
        mangaObject.tags = data.tags
        mangaObject.cover = data.coverUrl
        mangaObject.url = data.url
        mangaObject.status = data.status
        mangaObject.nsfw = data.nsfw
        mangaObject.viewer = data.viewer
        
        // Restore library entry
        let libraryObject = CoreDataManager.shared.getLibraryManga(
            sourceId: snapshot.sourceId,
            mangaId: snapshot.mangaId,
            context: context
        ) ?? {
            let obj = LibraryMangaObject(context: context)
            obj.manga = mangaObject
            return obj
        }()
        
        if let lastOpened = data.lastOpened {
            libraryObject.lastOpened = lastOpened
        }
        if let lastUpdated = data.lastUpdated {
            libraryObject.lastUpdated = lastUpdated
        }
        if let lastRead = data.lastRead {
            libraryObject.lastRead = lastRead
        }
        if let dateAdded = data.dateAdded {
            libraryObject.dateAdded = dateAdded
        }
        
        // Restore chapters
        CoreDataManager.shared.removeChapters(
            sourceId: snapshot.sourceId,
            mangaId: snapshot.mangaId,
            context: context
        )
        
        for (index, chapterData) in snapshot.chapters.enumerated() {
            let chapterObj = ChapterObject(context: context)
            chapterObj.sourceId = snapshot.sourceId
            chapterObj.mangaId = snapshot.mangaId
            chapterObj.id = chapterData.id
            chapterObj.title = chapterData.title
            chapterObj.scanlator = chapterData.scanlator
            chapterObj.url = chapterData.url
            chapterObj.lang = chapterData.lang
            chapterObj.chapter = chapterData.chapter.map { NSNumber(value: $0) }
            chapterObj.volume = chapterData.volume.map { NSNumber(value: $0) }
            chapterObj.dateUploaded = chapterData.dateUploaded
            chapterObj.sourceOrder = Int16(chapterData.sourceOrder)
            chapterObj.manga = mangaObject
        }
        
        // Restore history
        CoreDataManager.shared.removeHistory(
            sourceId: snapshot.sourceId,
            mangaId: snapshot.mangaId,
            context: context
        )
        
        for historyData in snapshot.history {
            let historyObj = HistoryObject(context: context)
            historyObj.sourceId = snapshot.sourceId
            historyObj.mangaId = snapshot.mangaId
            historyObj.chapterId = historyData.chapterId
            historyObj.dateRead = historyData.dateRead
            historyObj.progress = Int16(historyData.progress)
            historyObj.total = Int16(historyData.total)
            historyObj.completed = historyData.completed
            historyObj.scrollPosition = historyData.scrollPosition.map { NSNumber(value: $0) }
        }
        
        // Restore categories
        libraryObject.categories = nil
        for categoryTitle in snapshot.categories {
            if let categoryObj = CoreDataManager.shared.getCategory(title: categoryTitle, context: context) {
                libraryObject.addToCategories(categoryObj)
            }
        }
        
        // Restore tracking data
        if let trackingData = snapshot.trackingData {
            CoreDataManager.shared.removeTracks(
                sourceId: snapshot.sourceId,
                mangaId: snapshot.mangaId,
                context: context
            )
            
            for trackData in trackingData {
                let trackObj = TrackObject(context: context)
                trackObj.sourceId = snapshot.sourceId
                trackObj.mangaId = snapshot.mangaId
                trackObj.trackerId = Int16(trackData.trackerId)
                trackObj.trackingId = trackData.trackingId
                trackObj.title = trackData.title
                trackObj.lastChapterRead = trackData.lastChapterRead.map { NSNumber(value: $0) }
                trackObj.status = trackData.status
                trackObj.score = trackData.score
                trackObj.startDate = trackData.startDate
                trackObj.finishDate = trackData.finishDate
            }
        }
        
        return true
    }
    
    // MARK: - Backup Management
    
    /// Lists all available backups
    func listBackups() async -> [MigrationBackup] {
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: backupDirectory,
                includingPropertiesForKeys: nil
            )
            
            var backups: [MigrationBackup] = []
            for file in files where file.pathExtension == "json" {
                if let data = try? Data(contentsOf: file),
                   let backup = try? JSONDecoder().decode(MigrationBackup.self, from: data) {
                    backups.append(backup)
                }
            }
            
            return backups.sorted { $0.timestamp > $1.timestamp }
        } catch {
            LogManager.logger.error("Failed to list backups: \(error.localizedDescription)")
            return []
        }
    }
    
    /// Deletes a specific backup
    func deleteBackup(_ id: UUID) async {
        let fileURL = backupDirectory.appendingPathComponent("\(id.uuidString).json")
        try? FileManager.default.removeItem(at: fileURL)
    }
    
    /// Cleans up expired backups
    func cleanupExpiredBackups() async {
        let backups = await listBackups()
        for backup in backups where backup.isExpired {
            await deleteBackup(backup.id)
            LogManager.logger.info("Deleted expired backup: \(backup.id.uuidString)")
        }
    }
}
