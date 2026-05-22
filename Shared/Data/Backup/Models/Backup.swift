//
//  Backup.swift
//  Aidoku
//
//  Created by Skitty on 2/26/22.
//

import Foundation

struct Backup: Codable, Hashable, Identifiable, Sendable {
    var id: Int { hashValue }

    var library: [BackupLibraryManga]?
    var history: [BackupHistory]?
    var manga: [BackupManga]?
    var chapters: [BackupChapter]?
    var trackItems: [BackupTrackItem]?
    var readingSessions: [BackupReadingSession]?
    var updates: [BackupUpdate]?
    var categories: [BackupCategory]?
    var sources: [BackupSource]?
    var sourceLists: [String]?
    var settings: [String: JsonAnyValue]?
    var date: Date
    var name: String?
    var automatic: Bool?
    var version: String?

    static func load(from url: URL) -> Backup? {
        guard let data = try? Data(contentsOf: url) else { return nil }

        do {
            let backup = try PropertyListDecoder().decode(Backup.self, from: data)
            return backup
        } catch {
            LogManager.logger.error("PropertyListDecoder failed for \(url.lastPathComponent): \(error)")
            
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .secondsSince1970
                let backup = try decoder.decode(Backup.self, from: data)
                return backup
            } catch {
                LogManager.logger.error("JSONDecoder failed for \(url.lastPathComponent): \(error)")
                return nil
            }
        }
    }
}
