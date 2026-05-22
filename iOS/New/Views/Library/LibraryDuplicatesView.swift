//
//  LibraryDuplicatesView.swift
//  Aidoku
//
//  Finds library entries with the same normalized title across DIFFERENT sources
//  and lets the user delete duplicates to keep the library clean.
//  Note: Only shows duplicates from different sources, not duplicates within the same source.
//

import AidokuRunner
import SwiftUI

@available(iOS 16.0, *)
struct LibraryDuplicatesView: View {
    @State private var groups: [DuplicateGroup] = []
    @State private var selected: Set<DuplicateItem.ID> = []
    @State private var isLoading = true
    @State private var didFirstLoad = false
    @State private var showingDeleteConfirm = false

    @EnvironmentObject private var path: NavigationCoordinator

    private let sourceNames: [String: String]

    init() {
        var sourceNames: [String: String] = [:]
        for source in SourceManager.shared.sources {
            sourceNames[source.key] = source.name
        }
        self.sourceNames = sourceNames
    }

    struct DuplicateItem: Identifiable, Hashable {
        var id: String { "\(sourceId):\(mangaId)" }
        let sourceId: String
        let mangaId: String
        let title: String
        let cover: String?
        let chapterCount: Int
        let lastOpened: Date?
        let dateAdded: Date?
    }

    struct DuplicateGroup: Identifiable, Equatable {
        var id: String { normalizedTitle }
        let normalizedTitle: String
        let displayTitle: String
        let items: [DuplicateItem]
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
            } else if groups.isEmpty {
                UnavailableView(
                    NSLocalizedString("NO_DUPLICATES_FOUND"),
                    systemImage: "checkmark.seal",
                    description: Text(NSLocalizedString("NO_DUPLICATES_FOUND_TEXT"))
                )
            } else {
                List {
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.items) { item in
                                row(for: item)
                            }
                        } header: {
                            Text(group.displayTitle)
                                .textCase(nil)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable {
                    await loadDuplicates()
                }
            }
        }
        .navigationTitle(NSLocalizedString("FIND_DUPLICATES"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isLoading && !groups.isEmpty {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("DELETE")) {
                        showingDeleteConfirm = true
                    }
                    .disabled(selected.isEmpty)
                    .tint(.red)
                }
            }
        }
        .alert(
            String(format: NSLocalizedString("DELETE_%i_DUPLICATES?"), selected.count),
            isPresented: $showingDeleteConfirm
        ) {
            Button(NSLocalizedString("CANCEL"), role: .cancel) {}
            Button(NSLocalizedString("DELETE"), role: .destructive) {
                Task { await deleteSelected() }
            }
        } message: {
            Text(NSLocalizedString("DELETE_DUPLICATES_TEXT"))
        }
        .onAppear {
            guard !didFirstLoad else { return }
            didFirstLoad = true
            Task { await loadDuplicates() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .updateLibrary)) { _ in
            // Reload duplicates when library is updated (manga added/removed)
            Task {
                isLoading = true
                await loadDuplicates()
            }
        }
    }

    @ViewBuilder
    private func row(for item: DuplicateItem) -> some View {
        Button {
            if selected.contains(item.id) {
                selected.remove(item.id)
            } else {
                selected.insert(item.id)
            }
        } label: {
            HStack(spacing: 12) {
                MangaCoverView(
                    source: SourceManager.shared.source(for: item.sourceId),
                    coverImage: item.cover ?? "",
                    width: 44,
                    height: 64
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                    Text(sourceNames[item.sourceId] ?? item.sourceId)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Text(String(format: NSLocalizedString("DUPLICATES_CHAPTER_COUNT_%i"), item.chapterCount))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text("•")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                        Text(item.sourceId)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Image(systemName: selected.contains(item.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected.contains(item.id) ? .red : .secondary)
                    .imageScale(.large)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

@available(iOS 16.0, *)
extension LibraryDuplicatesView {
    func loadDuplicates() async {
        let foundGroups = await CoreDataManager.shared.container.performBackgroundTask { context -> [DuplicateGroup] in
            let libraryObjects = CoreDataManager.shared.getLibraryManga(context: context)

            var buckets: [String: [DuplicateItem]] = [:]
            var displayTitles: [String: String] = [:]
            var seenIds: Set<String> = []

            for libraryObject in libraryObjects {
                guard let manga = libraryObject.manga else { continue }
                let key = Self.normalize(manga.title)
                guard !key.isEmpty else { continue }
                
                // Create unique ID for this manga
                let uniqueId = "\(manga.sourceId):\(manga.id)"
                
                // Skip if we've already seen this exact manga (prevents duplicates in the list)
                guard !seenIds.contains(uniqueId) else { continue }
                seenIds.insert(uniqueId)

                let chapterCount = CoreDataManager.shared.getChapters(
                    sourceId: manga.sourceId,
                    mangaId: manga.id,
                    context: context
                ).count

                let item = DuplicateItem(
                    sourceId: manga.sourceId,
                    mangaId: manga.id,
                    title: manga.title,
                    cover: manga.cover,
                    chapterCount: chapterCount,
                    lastOpened: libraryObject.lastOpened,
                    dateAdded: libraryObject.dateAdded
                )
                buckets[key, default: []].append(item)
                if displayTitles[key] == nil {
                    displayTitles[key] = manga.title
                }
            }

            return buckets
                .filter { $0.value.count > 1 }
                .map { entry in
                    DuplicateGroup(
                        normalizedTitle: entry.key,
                        displayTitle: displayTitles[entry.key] ?? entry.key,
                        items: entry.value.sorted { ($0.dateAdded ?? .distantPast) < ($1.dateAdded ?? .distantPast) }
                    )
                }
                .sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
        }

        await MainActor.run {
            groups = foundGroups
            isLoading = false
        }
    }

    func deleteSelected() async {
        let toDelete = groups
            .flatMap { $0.items }
            .filter { selected.contains($0.id) }

        for item in toDelete {
            await MangaManager.shared.removeFromLibrary(sourceId: item.sourceId, mangaId: item.mangaId)
        }

        selected.removeAll()
        // reload to reflect changes
        isLoading = true
        await loadDuplicates()
    }

    nonisolated static func normalize(_ title: String) -> String {
        // Remove common articles and normalize
        var normalized = title.lowercased()
        
        // Remove leading articles
        let articles = ["the ", "a ", "an "]
        for article in articles {
            if normalized.hasPrefix(article) {
                normalized = String(normalized.dropFirst(article.count))
                break
            }
        }
        
        // Remove diacritics and case
        normalized = normalized.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        
        // Remove all non-alphanumeric characters and spaces
        let filtered = normalized.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        return String(String.UnicodeScalarView(filtered))
    }
}
