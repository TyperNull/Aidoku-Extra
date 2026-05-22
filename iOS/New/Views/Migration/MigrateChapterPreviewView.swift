//
//  MigrateChapterPreviewView.swift
//  Aidoku
//
//  Shows old→new chapter mapping for a pending migration so the user can
//  confirm which read chapters will be transferred before any destructive
//  changes occur.
//

import AidokuRunner
import SwiftUI

struct MigrateChapterPreviewView: View {
    let copy: Bool
    let fromSeries: [AidokuRunner.Manga]
    let toSeries: [MangaIdentifier: AidokuRunner.Manga?]
    @State private var preloadedChapters: [MangaIdentifier: [AidokuRunner.Chapter]]

    @State private var previews: [MangaIdentifier: PreviewItem] = [:]
    @State private var loadedCount: Int = 0
    @State private var isLoading: Bool = true
    @State private var didFirstLoad: Bool = false

    @EnvironmentObject private var path: NavigationCoordinator

    private let sourceNames: [String: String]

    init(
        copy: Bool,
        fromSeries: [AidokuRunner.Manga],
        toSeries: [MangaIdentifier: AidokuRunner.Manga?],
        withChapters: [MangaIdentifier: [AidokuRunner.Chapter]]
    ) {
        self.copy = copy
        self.fromSeries = fromSeries
        self.toSeries = toSeries
        self._preloadedChapters = State(initialValue: withChapters)

        var sourceNames: [String: String] = [:]
        for source in SourceManager.shared.sources {
            sourceNames[source.key] = source.name
        }
        self.sourceNames = sourceNames
    }

    struct PreviewItem: Equatable {
        let toManga: AidokuRunner.Manga
        let totalReadOldChapters: Int
        let matches: [Match]
        let unmatched: [AidokuRunner.Chapter]

        struct Match: Hashable {
            let oldChapter: AidokuRunner.Chapter
            let newChapter: AidokuRunner.Chapter
        }
    }

    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack {
                        ProgressView()
                        Text(String(format: NSLocalizedString("MIGRATION_PREVIEW_LOADING_%i_OF_%i"), loadedCount, totalToLoad))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            ForEach(fromSeries, id: \.identifier) { manga in
                if let preview = previews[manga.identifier] {
                    Section {
                        previewRows(for: preview)
                    } header: {
                        sectionHeader(from: manga, to: preview.toManga, matched: preview.matches.count, total: preview.totalReadOldChapters)
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("CHAPTER_MATCHING_PREVIEW"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isLoading {
                    ProgressView()
                } else {
                    Button(copy ? NSLocalizedString("COPY") : NSLocalizedString("MIGRATE")) {
                        startMigration()
                    }
                }
            }
        }
        .onAppear {
            guard !didFirstLoad else { return }
            didFirstLoad = true
            Task { await loadPreviews() }
        }
    }

    private var totalToLoad: Int {
        fromSeries.compactMap { toSeries[$0.identifier] ?? nil }.count
    }

    @ViewBuilder
    private func sectionHeader(
        from oldManga: AidokuRunner.Manga,
        to newManga: AidokuRunner.Manga,
        matched: Int,
        total: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(oldManga.title)
                .font(.subheadline)
                .foregroundStyle(.primary)
            HStack(spacing: 4) {
                Text(sourceNames[oldManga.sourceKey] ?? oldManga.sourceKey)
                Image(systemName: "arrow.right")
                Text(sourceNames[newManga.sourceKey] ?? newManga.sourceKey)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            Text(String(format: NSLocalizedString("MIGRATION_PREVIEW_MATCHED_%i_OF_%i"), matched, total))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .textCase(nil)
    }

    @ViewBuilder
    private func previewRows(for preview: PreviewItem) -> some View {
        if preview.totalReadOldChapters == 0 {
            Text(NSLocalizedString("MIGRATION_PREVIEW_NO_READ_CHAPTERS"))
                .foregroundStyle(.secondary)
                .font(.footnote)
        } else {
            ForEach(preview.matches, id: \.self) { match in
                HStack(spacing: 8) {
                    Text(displayName(for: match.oldChapter))
                        .lineLimit(1)
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                    Text(displayName(for: match.newChapter))
                        .lineLimit(1)
                        .foregroundStyle(.green)
                    Spacer()
                }
                .font(.footnote)
            }
            ForEach(preview.unmatched, id: \.key) { chapter in
                HStack(spacing: 8) {
                    Text(displayName(for: chapter))
                        .lineLimit(1)
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                    Text(NSLocalizedString("MIGRATION_PREVIEW_NO_MATCH"))
                        .foregroundStyle(.red)
                    Spacer()
                }
                .font(.footnote)
            }
        }
    }

    private func displayName(for chapter: AidokuRunner.Chapter) -> String {
        if let title = chapter.title, !title.isEmpty {
            return title
        }
        if let num = chapter.chapterNumber {
            return String(format: NSLocalizedString("CH_X"), Double(num))
        }
        if let vol = chapter.volumeNumber {
            return String(format: NSLocalizedString("VOL_X"), Double(vol))
        }
        return chapter.key
    }
}

extension MigrateChapterPreviewView {
    func loadPreviews() async {
        for oldManga in fromSeries {
            guard
                let newMangaOptional = toSeries[oldManga.identifier],
                let newManga = newMangaOptional
            else { continue }

            // load new chapters (may already be cached)
            let newChapters: [AidokuRunner.Chapter]
            if let cached = preloadedChapters[oldManga.identifier] {
                newChapters = cached
            } else if let source = SourceManager.shared.source(for: newManga.sourceKey) {
                let updated = try? await source.getMangaUpdate(
                    manga: newManga,
                    needsDetails: false,
                    needsChapters: true
                )
                let fetched = updated?.chapters ?? []
                newChapters = fetched
                await MainActor.run {
                    preloadedChapters[oldManga.identifier] = fetched
                }
            } else {
                newChapters = []
            }

            // load old read chapters from history
            let oldReadChapters = await CoreDataManager.shared.container.performBackgroundTask { context in
                CoreDataManager.shared.getHistoryForManga(
                    sourceId: oldManga.sourceKey,
                    mangaId: oldManga.key,
                    context: context
                )
                .filter { $0.completed }
                .compactMap { $0.chapter?.toNewChapter() }
                .sorted { ($0.chapterNumber ?? 0) < ($1.chapterNumber ?? 0) }
            }

            let preview = Self.buildPreview(
                toManga: newManga,
                oldReadChapters: oldReadChapters,
                newChapters: newChapters
            )

            await MainActor.run {
                previews[oldManga.identifier] = preview
                loadedCount += 1
            }
        }

        await MainActor.run {
            isLoading = false
        }
    }

    /// Computes the chapter mapping using the same rules as `MangaManager.migrate()`.
    static func buildPreview(
        toManga: AidokuRunner.Manga,
        oldReadChapters: [AidokuRunner.Chapter],
        newChapters: [AidokuRunner.Chapter]
    ) -> PreviewItem {
        let readChapterNumbers = Set(oldReadChapters.compactMap { $0.chapterNumber })
        let readVolumeNumbers = Set(oldReadChapters.compactMap { $0.volumeNumber })

        var matches: [PreviewItem.Match] = []
        var unmatched: [AidokuRunner.Chapter] = []

        // mirror migrate(): prefer chapter-number matching, fall back to volume matching
        let useChapterMatching = !readChapterNumbers.isEmpty
        let useVolumeMatching = !useChapterMatching && !readVolumeNumbers.isEmpty

        for oldChapter in oldReadChapters {
            let match: AidokuRunner.Chapter? = {
                if useChapterMatching, let num = oldChapter.chapterNumber {
                    return newChapters.first { $0.chapterNumber == num }
                }
                if useVolumeMatching, let vol = oldChapter.volumeNumber {
                    return newChapters.first { $0.volumeNumber == vol }
                }
                return nil
            }()
            if let match {
                matches.append(.init(oldChapter: oldChapter, newChapter: match))
            } else {
                unmatched.append(oldChapter)
            }
        }

        return PreviewItem(
            toManga: toManga,
            totalReadOldChapters: oldReadChapters.count,
            matches: matches,
            unmatched: unmatched
        )
    }

    func startMigration() {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }
        let copy = self.copy
        let fromSeries = self.fromSeries
        let toSeries = self.toSeries
        let withChapters = self.preloadedChapters
        appDelegate.showLoadingIndicator(style: .progress) {
            Task {
                UIApplication.shared.isIdleTimerDisabled = true

                await MangaManager.shared.migrate(
                    copy: copy,
                    fromSeries: fromSeries,
                    toSeries: toSeries,
                    withChapters: withChapters,
                    progressReport: { progress in
                        Task { @MainActor in
                            if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
                                appDelegate.indicatorProgress = progress
                            }
                        }
                    }
                )

                NotificationCenter.default.post(name: .updateLibrary, object: nil)
                NotificationCenter.default.post(name: .updateHistory, object: nil)

                UIApplication.shared.isIdleTimerDisabled = false

                await appDelegate.hideLoadingIndicator()

                path.dismiss()
            }
        }
    }
}
