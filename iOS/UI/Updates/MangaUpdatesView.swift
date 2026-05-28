//
//  MangaUpdatesView.swift
//  Aidoku (iOS)
//
//  Created by axiel7 on 09/02/2024.
// No navigation points i rewrote the code to use a custom navigation.

import AidokuRunner
import Foundation
enum MangaUpdatesView {
    struct UpdateSection: Hashable {
        let day: Int
        var items: [Item]
    }

    struct Item: Hashable {
        let mangaKey: String
        var updates: [UpdateInfo]
    }

    struct UpdateInfo: Identifiable, Hashable {
        let id: String
        let chapterIdentifier: ChapterIdentifier
        let date: Date
        let manga: AidokuRunner.Manga
        let chapter: Chapter?
        var viewed: Bool
    }
}
