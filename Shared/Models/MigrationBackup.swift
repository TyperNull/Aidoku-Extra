//
//  MigrationBackup.swift
//  Aidoku
//
//  Created by Kiro on 5/22/26.
//

import Foundation
import AidokuRunner

/// Represents a backup snapshot of manga data before migration
struct MigrationBackup: Codable {
    let id: UUID
    let timestamp: Date
    let expirationDate: Date
    let migrations: [MangaMigrationSnapshot]
    
    struct MangaMigrationSnapshot: Codable {
        let sourceId: String
        let mangaId: String
        let title: String
        let coverUrl: String?
        
        // Backup data
        let mangaData: MangaBackupData
        let chapters: [ChapterBackupData]
        let history: [HistoryBackupData]
        let categories: [String]
        let trackingData: [TrackBackupData]?
        
        // Migration target info
        let targetSourceId: String?
        let targetMangaId: String?
    }
    
    struct MangaBackupData: Codable {
        let title: String
        let author: String?
        let artist: String?
        let description: String?
        let tags: [String]
        let coverUrl: String?
        let url: String?
        let status: Int16
        let nsfw: Int16
        let viewer: Int16
        let lastOpened: Date?
        let lastUpdated: Date?
        let lastRead: Date?
        let dateAdded: Date?
    }
    
    struct ChapterBackupData: Codable {
        let id: String
        let title: String?
        let scanlator: String?
        let url: String?
        let lang: String
        let chapter: Float?
        let volume: Float?
        let dateUploaded: Date?
        let sourceOrder: Int
    }
    
    struct HistoryBackupData: Codable {
        let chapterId: String
        let dateRead: Date
        let progress: Int
        let total: Int
        let completed: Bool
        let scrollPosition: Double?
    }
    
    struct TrackBackupData: Codable {
        let trackerId: Int
        let trackingId: String
        let title: String?
        let lastChapterRead: Float?
        let status: Int16
        let score: Int16
        let startDate: Date?
        let finishDate: Date?
    }
    
    init(migrations: [MangaMigrationSnapshot]) {
        self.id = UUID()
        self.timestamp = Date()
        // Expire after 24 hours
        self.expirationDate = Date().addingTimeInterval(24 * 60 * 60)
        self.migrations = migrations
    }
    
    var isExpired: Bool {
        Date() > expirationDate
    }
}
