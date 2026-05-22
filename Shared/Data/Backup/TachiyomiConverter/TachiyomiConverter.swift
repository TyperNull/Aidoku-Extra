//
//  TachiyomiConverter.swift
//  Aidoku
//
//  Tachiyomi to Aidoku backup converter
//

import Foundation

/// Converts Tachiyomi backups to Aidoku format
class TachiyomiConverter {
    
    // Tracker ID mappings
    private static let tachiyomiToAidokuTrackers: [Int: String] = [
        1: "myanimelist",
        2: "anilist"
    ]
    
    // Manga viewer type mappings
    private static let viewerMapping: [Int: Int] = [
        1: 2, // LTR -> LTR
        2: 1, // RTL -> RTL
        3: 3, // Vertical -> Vertical
        4: 4, // Webtoon -> Scroll
        5: 4  // Continuous vertical -> Scroll
    ]
    
    // Manga status mappings
    private static let statusMapping: [Int: Int] = [
        0: 0, // Unknown -> Unknown
        1: 1, // Ongoing -> Ongoing
        2: 2, // Completed -> Completed
        3: 0, // Licensed -> Unknown
        4: 2, // Publishing finished -> Completed
        5: 3, // Cancelled -> Cancelled
        6: 4  // Hiatus -> Hiatus
    ]
    
    /// Convert a Tachiyomi backup to Aidoku format
    /// - Parameter data: The decompressed Tachiyomi backup data
    /// - Returns: An Aidoku Backup object
    /// - Throws: Conversion errors
    static func convertToAidoku(from data: Data) throws -> Backup {
        let tachiyomiBackup = try TachiyomiBackup(serializedData: data)
        
        let dateString = ISO8601DateFormatter().string(from: Date())
        var aidokuBackup = Backup(
            library: [],
            history: [],
            manga: [],
            chapters: [],
            trackItems: [],
            readingSessions: nil,
            updates: nil,
            categories: tachiyomiBackup.backupCategories.map { BackupCategory(title: $0.name) },
            sources: [],
            sourceLists: nil,
            settings: nil,
            date: Date(),
            name: "Converted Tachiyomi Backup \(dateString.prefix(10))",
            automatic: false,
            version: "0.0.1"
        )
        
        // Create category lookup map
        let categoriesMap = Dictionary(
            uniqueKeysWithValues: tachiyomiBackup.backupCategories.map {
                (String($0.order), $0.name)
            }
        )
        
        // Track unique sources
        var sources = Set<String>()
        
        // Convert each manga
        for tachiyomiManga in tachiyomiBackup.backupManga {
            // Find the source for this manga
            let source = findSource(
                sourceId: tachiyomiManga.source,
                in: tachiyomiBackup.backupSources,
                brokenSources: tachiyomiBackup.backupBrokenSources
            )
            
            let aidokuSourceId = source.name.lowercased()
            sources.insert(aidokuSourceId)
            
            // Convert manga
            let aidokuManga = convertManga(tachiyomiManga, sourceId: aidokuSourceId)
            aidokuBackup.manga?.append(aidokuManga)
            
            // Add to library if it has a date added
            if tachiyomiManga.dateAdded != 0 {
                let categories = tachiyomiManga.categories.compactMap {
                    categoriesMap[String($0)]
                }
                
                let libraryEntry = BackupLibraryManga(
                    sourceId: aidokuSourceId,
                    mangaId: aidokuManga.id,
                    lastOpened: nil,
                    lastUpdated: nil,
                    lastRead: nil,
                    dateAdded: Date(timeIntervalSince1970: TimeInterval(tachiyomiManga.dateAdded) / 1000),
                    categories: categories.isEmpty ? nil : categories
                )
                aidokuBackup.library?.append(libraryEntry)
            }
            
            // Convert chapters and history
            for tachiyomiChapter in tachiyomiManga.chapters {
                let aidokuChapter = convertChapter(
                    tachiyomiChapter,
                    mangaId: tachiyomiManga.url,
                    sourceId: aidokuSourceId
                )
                aidokuBackup.chapters?.append(aidokuChapter)
                
                // Find history for this chapter
                let historyEntry = findHistory(
                    for: tachiyomiChapter.url,
                    in: tachiyomiManga.history,
                    brokenHistory: tachiyomiManga.brokenHistory
                )
                
                let dateRead = historyEntry.map {
                    Date(timeIntervalSince1970: TimeInterval($0) / 1000)
                } ?? Date(timeIntervalSince1970: 0)
                
                let history = BackupHistory(
                    sourceId: aidokuSourceId,
                    mangaId: aidokuManga.id,
                    chapterId: aidokuChapter.id,
                    progress: tachiyomiChapter.lastPageRead,
                    total: nil,
                    completed: tachiyomiChapter.read,
                    dateRead: dateRead
                )
                aidokuBackup.history?.append(history)
            }
            
            // Convert tracking
            for tracking in tachiyomiManga.tracking where tracking.syncID <= 2 {
                guard let trackerId = tachiyomiToAidokuTrackers[Int(tracking.syncID)] else {
                    continue
                }
                
                // Extract ID from tracking URL
                // Format: https://anilist.co/manga/31706/Title or https://myanimelist.net/manga/1706/Title
                let urlComponents = tracking.trackingURL.split(separator: "/")
                guard urlComponents.count >= 5 else { continue }
                let id = String(urlComponents[4])
                
                let trackItem = BackupTrackItem(
                    trackerId: trackerId,
                    id: id,
                    mangaId: aidokuManga.id,
                    sourceId: aidokuSourceId,
                    title: aidokuManga.title
                )
                aidokuBackup.trackItems?.append(trackItem)
            }
        }
        
        aidokuBackup.sources = sources.map { BackupSource(id: $0) }
        
        return aidokuBackup
    }
    
    // MARK: - Helper Methods
    
    private static func findSource(
        sourceId: Int64,
        in sources: [TachiyomiBackupSource],
        brokenSources: [TachiyomiBrokenBackupSource]
    ) -> (name: String, id: Int64) {
        if let source = sources.first(where: { $0.sourceID == sourceId }) {
            return (source.name, source.sourceID)
        }
        if let source = brokenSources.first(where: { $0.sourceID == sourceId }) {
            return (source.name, source.sourceID)
        }
        return ("tachiyomi_\(sourceId)", sourceId)
    }
    
    private static func convertManga(_ tachiyomiManga: TachiyomiBackupManga, sourceId: String) -> BackupManga {
        BackupManga(
            sourceId: sourceId,
            id: tachiyomiManga.url,
            title: tachiyomiManga.title,
            author: tachiyomiManga.hasAuthor ? tachiyomiManga.author : nil,
            artist: tachiyomiManga.hasArtist ? tachiyomiManga.artist : nil,
            desc: tachiyomiManga.hasDescription ? tachiyomiManga.description_p : nil,
            tags: tachiyomiManga.genre.isEmpty ? nil : tachiyomiManga.genre,
            cover: tachiyomiManga.hasThumbnailURL ? tachiyomiManga.thumbnailURL : nil,
            url: tachiyomiManga.url,
            status: statusMapping[Int(tachiyomiManga.status)] ?? 0,
            nsfw: 0,
            viewer: viewerMapping[Int(tachiyomiManga.viewer)] ?? 0
        )
    }
    
    private static func convertChapter(
        _ tachiyomiChapter: TachiyomiBackupChapter,
        mangaId: String,
        sourceId: String
    ) -> BackupChapter {
        BackupChapter(
            sourceId: sourceId,
            mangaId: mangaId,
            id: tachiyomiChapter.url,
            title: tachiyomiChapter.name.isEmpty ? nil : tachiyomiChapter.name,
            scanlator: tachiyomiChapter.hasScanlator ? tachiyomiChapter.scanlator : nil,
            lang: "",
            chapter: tachiyomiChapter.chapterNumber == 0 ? nil : Double(tachiyomiChapter.chapterNumber),
            volume: nil,
            dateUploaded: tachiyomiChapter.dateUpload != 0 
                ? Date(timeIntervalSince1970: TimeInterval(tachiyomiChapter.dateUpload) / 1000)
                : nil,
            sourceOrder: Int(tachiyomiChapter.sourceOrder)
        )
    }
    
    private static func findHistory(
        for url: String,
        in history: [TachiyomiBackupHistory],
        brokenHistory: [TachiyomiBrokenBackupHistory]
    ) -> Int64? {
        if let entry = history.first(where: { $0.url == url }) {
            return entry.lastRead
        }
        if let entry = brokenHistory.first(where: { $0.url == url }) {
            return entry.lastRead
        }
        return nil
    }
}
