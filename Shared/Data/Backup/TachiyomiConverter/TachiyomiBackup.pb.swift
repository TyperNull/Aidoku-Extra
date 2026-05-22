//
//  TachiyomiBackup.pb.swift
//  Aidoku
//
//  Generated protobuf structures for Tachiyomi backup format
//  This is a manual Swift implementation since we can't use SwiftProtobuf dependency
//

import Foundation

// MARK: - Tachiyomi Backup Structures

struct TachiyomiBackup {
    var backupManga: [TachiyomiBackupManga] = []
    var backupCategories: [TachiyomiBackupCategory] = []
    var backupBrokenSources: [TachiyomiBrokenBackupSource] = []
    var backupSources: [TachiyomiBackupSource] = []
    
    init(serializedData: Data) throws {
        let decoder = ProtobufDecoder(data: serializedData)
        try decoder.decode(into: &self)
    }
}

struct TachiyomiBackupManga {
    var source: Int64 = 0
    var url: String = ""
    var title: String = ""
    var artist: String = ""
    var hasArtist: Bool = false
    var author: String = ""
    var hasAuthor: Bool = false
    var description_p: String = ""
    var hasDescription: Bool = false
    var genre: [String] = []
    var status: Int32 = 0
    var thumbnailURL: String = ""
    var hasThumbnailURL: Bool = false
    var dateAdded: Int64 = 0
    var viewer: Int32 = 0
    var chapters: [TachiyomiBackupChapter] = []
    var categories: [Int64] = []
    var tracking: [TachiyomiBackupTracking] = []
    var favorite: Bool = true
    var chapterFlags: Int32 = 0
    var brokenHistory: [TachiyomiBrokenBackupHistory] = []
    var viewerFlags: Int32 = 0
    var hasViewerFlags: Bool = false
    var history: [TachiyomiBackupHistory] = []
}

struct TachiyomiBackupChapter {
    var url: String = ""
    var name: String = ""
    var scanlator: String = ""
    var hasScanlator: Bool = false
    var read: Bool = false
    var bookmark: Bool = false
    var lastPageRead: Int32 = 0
    var dateFetch: Int64 = 0
    var dateUpload: Int64 = 0
    var chapterNumber: Float = 0
    var sourceOrder: Int32 = 0
}

struct TachiyomiBackupTracking {
    var syncID: Int32 = 0
    var libraryID: Int64 = 0
    var mediaIDInt: Int32 = 0
    var trackingURL: String = ""
    var title: String = ""
    var lastChapterRead: Float = 0
    var totalChapters: Int32 = 0
    var score: Float = 0
    var status: Int32 = 0
    var startedReadingDate: Int64 = 0
    var finishedReadingDate: Int64 = 0
    var mediaID: Int64 = 0
}

struct TachiyomiBackupCategory {
    var name: String = ""
    var order: Int64 = 0
    var flags: Int64 = 0
}

struct TachiyomiBackupSource {
    var name: String = ""
    var sourceID: Int64 = 0
}

struct TachiyomiBrokenBackupSource {
    var name: String = ""
    var sourceID: Int64 = 0
}

struct TachiyomiBackupHistory {
    var url: String = ""
    var lastRead: Int64 = 0
}

struct TachiyomiBrokenBackupHistory {
    var url: String = ""
    var lastRead: Int64 = 0
}

// MARK: - Simple Protobuf Decoder

class ProtobufDecoder {
    private var data: Data
    private var position: Int = 0
    
    init(data: Data) {
        self.data = data
    }
    
    func decode(into backup: inout TachiyomiBackup) throws {
        while position < data.count {
            let (fieldNumber, wireType) = try readTag()
            
            switch fieldNumber {
            case 1: // backup_manga
                let length = try readVarint()
                let mangaData = data.subdata(in: position..<position + Int(length))
                position += Int(length)
                var manga = TachiyomiBackupManga()
                try ProtobufDecoder(data: mangaData).decode(into: &manga)
                backup.backupManga.append(manga)
                
            case 2: // backup_categories
                let length = try readVarint()
                let categoryData = data.subdata(in: position..<position + Int(length))
                position += Int(length)
                var category = TachiyomiBackupCategory()
                try ProtobufDecoder(data: categoryData).decode(into: &category)
                backup.backupCategories.append(category)
                
            case 100: // backup_broken_sources
                let length = try readVarint()
                let sourceData = data.subdata(in: position..<position + Int(length))
                position += Int(length)
                var source = TachiyomiBrokenBackupSource()
                try ProtobufDecoder(data: sourceData).decode(into: &source)
                backup.backupBrokenSources.append(source)
                
            case 101: // backup_sources
                let length = try readVarint()
                let sourceData = data.subdata(in: position..<position + Int(length))
                position += Int(length)
                var source = TachiyomiBackupSource()
                try ProtobufDecoder(data: sourceData).decode(into: &source)
                backup.backupSources.append(source)
                
            default:
                try skipField(wireType: wireType)
            }
        }
    }
    
    func decode(into manga: inout TachiyomiBackupManga) throws {
        while position < data.count {
            let (fieldNumber, wireType) = try readTag()
            
            switch fieldNumber {
            case 1: manga.source = try readVarint64()
            case 2: manga.url = try readString()
            case 3: manga.title = try readString()
            case 4:
                manga.artist = try readString()
                manga.hasArtist = true
            case 5:
                manga.author = try readString()
                manga.hasAuthor = true
            case 6:
                manga.description_p = try readString()
                manga.hasDescription = true
            case 7: manga.genre.append(try readString())
            case 8: manga.status = try readVarint32()
            case 9:
                manga.thumbnailURL = try readString()
                manga.hasThumbnailURL = true
            case 13: manga.dateAdded = try readVarint64()
            case 14: manga.viewer = try readVarint32()
            case 16:
                let length = try readVarint()
                let chapterData = data.subdata(in: position..<position + Int(length))
                position += Int(length)
                var chapter = TachiyomiBackupChapter()
                try ProtobufDecoder(data: chapterData).decode(into: &chapter)
                manga.chapters.append(chapter)
            case 17: manga.categories.append(try readVarint64())
            case 18:
                let length = try readVarint()
                let trackingData = data.subdata(in: position..<position + Int(length))
                position += Int(length)
                var tracking = TachiyomiBackupTracking()
                try ProtobufDecoder(data: trackingData).decode(into: &tracking)
                manga.tracking.append(tracking)
            case 100: manga.favorite = try readVarint() != 0
            case 101: manga.chapterFlags = try readVarint32()
            case 102:
                let length = try readVarint()
                let historyData = data.subdata(in: position..<position + Int(length))
                position += Int(length)
                var history = TachiyomiBrokenBackupHistory()
                try ProtobufDecoder(data: historyData).decode(into: &history)
                manga.brokenHistory.append(history)
            case 103:
                manga.viewerFlags = try readVarint32()
                manga.hasViewerFlags = true
            case 104:
                let length = try readVarint()
                let historyData = data.subdata(in: position..<position + Int(length))
                position += Int(length)
                var history = TachiyomiBackupHistory()
                try ProtobufDecoder(data: historyData).decode(into: &history)
                manga.history.append(history)
            default:
                try skipField(wireType: wireType)
            }
        }
    }
    
    func decode(into chapter: inout TachiyomiBackupChapter) throws {
        while position < data.count {
            let (fieldNumber, wireType) = try readTag()
            
            switch fieldNumber {
            case 1: chapter.url = try readString()
            case 2: chapter.name = try readString()
            case 3:
                chapter.scanlator = try readString()
                chapter.hasScanlator = true
            case 4: chapter.read = try readVarint() != 0
            case 5: chapter.bookmark = try readVarint() != 0
            case 6: chapter.lastPageRead = try readVarint32()
            case 7: chapter.dateFetch = try readVarint64()
            case 8: chapter.dateUpload = try readVarint64()
            case 9: chapter.chapterNumber = try readFloat()
            case 10: chapter.sourceOrder = try readVarint32()
            default:
                try skipField(wireType: wireType)
            }
        }
    }
    
    func decode(into tracking: inout TachiyomiBackupTracking) throws {
        while position < data.count {
            let (fieldNumber, wireType) = try readTag()
            
            switch fieldNumber {
            case 1: tracking.syncID = try readVarint32()
            case 2: tracking.libraryID = try readVarint64()
            case 3: tracking.mediaIDInt = try readVarint32()
            case 4: tracking.trackingURL = try readString()
            case 5: tracking.title = try readString()
            case 6: tracking.lastChapterRead = try readFloat()
            case 7: tracking.totalChapters = try readVarint32()
            case 8: tracking.score = try readFloat()
            case 9: tracking.status = try readVarint32()
            case 10: tracking.startedReadingDate = try readVarint64()
            case 11: tracking.finishedReadingDate = try readVarint64()
            case 100: tracking.mediaID = try readVarint64()
            default:
                try skipField(wireType: wireType)
            }
        }
    }
    
    func decode(into category: inout TachiyomiBackupCategory) throws {
        while position < data.count {
            let (fieldNumber, wireType) = try readTag()
            
            switch fieldNumber {
            case 1: category.name = try readString()
            case 2: category.order = try readVarint64()
            case 100: category.flags = try readVarint64()
            default:
                try skipField(wireType: wireType)
            }
        }
    }
    
    func decode(into source: inout TachiyomiBackupSource) throws {
        while position < data.count {
            let (fieldNumber, wireType) = try readTag()
            
            switch fieldNumber {
            case 1: source.name = try readString()
            case 2: source.sourceID = try readVarint64()
            default:
                try skipField(wireType: wireType)
            }
        }
    }
    
    func decode(into source: inout TachiyomiBrokenBackupSource) throws {
        while position < data.count {
            let (fieldNumber, wireType) = try readTag()
            
            switch fieldNumber {
            case 0: source.name = try readString()
            case 1: source.sourceID = try readVarint64()
            default:
                try skipField(wireType: wireType)
            }
        }
    }
    
    func decode(into history: inout TachiyomiBackupHistory) throws {
        while position < data.count {
            let (fieldNumber, wireType) = try readTag()
            
            switch fieldNumber {
            case 1: history.url = try readString()
            case 2: history.lastRead = try readVarint64()
            default:
                try skipField(wireType: wireType)
            }
        }
    }
    
    func decode(into history: inout TachiyomiBrokenBackupHistory) throws {
        while position < data.count {
            let (fieldNumber, wireType) = try readTag()
            
            switch fieldNumber {
            case 0: history.url = try readString()
            case 1: history.lastRead = try readVarint64()
            default:
                try skipField(wireType: wireType)
            }
        }
    }
    
    // MARK: - Protobuf Reading Primitives
    
    private func readTag() throws -> (fieldNumber: Int, wireType: Int) {
        let tag = try readVarint()
        return (Int(tag >> 3), Int(tag & 0x7))
    }
    
    private func readVarint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        
        while position < data.count {
            let byte = data[position]
            position += 1
            
            result |= UInt64(byte & 0x7F) << shift
            
            if (byte & 0x80) == 0 {
                return result
            }
            
            shift += 7
        }
        
        throw ProtobufError.truncated
    }
    
    private func readVarint32() throws -> Int32 {
        Int32(truncatingIfNeeded: try readVarint())
    }
    
    private func readVarint64() throws -> Int64 {
        Int64(bitPattern: try readVarint())
    }
    
    private func readString() throws -> String {
        let length = try readVarint()
        guard position + Int(length) <= data.count else {
            throw ProtobufError.truncated
        }
        
        let stringData = data.subdata(in: position..<position + Int(length))
        position += Int(length)
        
        guard let string = String(data: stringData, encoding: .utf8) else {
            throw ProtobufError.invalidUTF8
        }
        
        return string
    }
    
    private func readFloat() throws -> Float {
        guard position + 4 <= data.count else {
            throw ProtobufError.truncated
        }
        
        let bytes = data.subdata(in: position..<position + 4)
        position += 4
        
        var value: Float = 0
        _ = withUnsafeMutableBytes(of: &value) { tempBuffer in
            bytes.copyBytes(to: tempBuffer)
        }
        return value
    }
    
    private func skipField(wireType: Int) throws {
        switch wireType {
        case 0: // Varint
            _ = try readVarint()
        case 1: // 64-bit
            position += 8
        case 2: // Length-delimited
            let length = try readVarint()
            position += Int(length)
        case 5: // 32-bit
            position += 4
        default:
            throw ProtobufError.unknownWireType
        }
    }
    
    enum ProtobufError: Error {
        case truncated
        case invalidUTF8
        case unknownWireType
    }
}
