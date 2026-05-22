//
//  MigrationBackupsView.swift
//  Aidoku
//
//  Created by Kiro on 5/22/26.
//

import SwiftUI

struct MigrationBackupsView: View {
    @State private var backups: [MigrationBackup] = []
    @State private var isLoading = true
    @State private var selectedBackup: MigrationBackup?
    @State private var showingRestoreAlert = false
    @State private var showingDeleteAlert = false
    @State private var isRestoring = false
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if backups.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text(NSLocalizedString("NO_MIGRATION_BACKUPS"))
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text(NSLocalizedString("NO_MIGRATION_BACKUPS_INFO"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(backups, id: \.id) { backup in
                        BackupRowView(backup: backup)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedBackup = backup
                                showingRestoreAlert = true
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    selectedBackup = backup
                                    showingDeleteAlert = true
                                } label: {
                                    Label(NSLocalizedString("DELETE"), systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(NSLocalizedString("MIGRATION_BACKUPS"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadBackups()
        }
        .refreshable {
            await loadBackups()
        }
        .alert(
            NSLocalizedString("RESTORE_MIGRATION_BACKUP"),
            isPresented: $showingRestoreAlert,
            presenting: selectedBackup
        ) { backup in
            Button(NSLocalizedString("CANCEL"), role: .cancel) {}
            Button(NSLocalizedString("RESTORE")) {
                Task {
                    await restoreBackup(backup)
                }
            }
        } message: { backup in
            Text(String(
                format: NSLocalizedString("RESTORE_MIGRATION_BACKUP_MESSAGE"),
                backup.migrations.count
            ))
        }
        .alert(
            NSLocalizedString("DELETE_BACKUP"),
            isPresented: $showingDeleteAlert,
            presenting: selectedBackup
        ) { backup in
            Button(NSLocalizedString("CANCEL"), role: .cancel) {}
            Button(NSLocalizedString("DELETE"), role: .destructive) {
                Task {
                    await deleteBackup(backup)
                }
            }
        } message: { _ in
            Text(NSLocalizedString("DELETE_BACKUP_MESSAGE"))
        }
        .overlay {
            if isRestoring {
                ZStack {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text(NSLocalizedString("RESTORING_BACKUP"))
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .padding(32)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(UIColor.systemBackground))
                    )
                }
            }
        }
    }
    
    private func loadBackups() async {
        isLoading = true
        backups = await MigrationBackupManager.shared.listBackups()
        isLoading = false
    }
    
    private func restoreBackup(_ backup: MigrationBackup) async {
        isRestoring = true
        let success = await MigrationBackupManager.shared.restoreBackup(backup)
        isRestoring = false
        
        if success {
            await loadBackups()
        }
    }
    
    private func deleteBackup(_ backup: MigrationBackup) async {
        await MigrationBackupManager.shared.deleteBackup(backup.id)
        await loadBackups()
    }
}

struct BackupRowView: View {
    let backup: MigrationBackup
    
    private var timeAgoString: String {
        let interval = Date().timeIntervalSince(backup.timestamp)
        let hours = Int(interval / 3600)
        
        if hours < 1 {
            let minutes = Int(interval / 60)
            return String(format: NSLocalizedString("MINUTES_AGO"), minutes)
        } else {
            return String(format: NSLocalizedString("HOURS_AGO"), hours)
        }
    }
    
    private var expiresInString: String {
        let interval = backup.expirationDate.timeIntervalSince(Date())
        let hours = Int(interval / 3600)
        
        if hours < 1 {
            let minutes = Int(interval / 60)
            return String(format: NSLocalizedString("EXPIRES_IN_MINUTES"), max(0, minutes))
        } else {
            return String(format: NSLocalizedString("EXPIRES_IN_HOURS"), hours)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(.accentColor)
                Text(timeAgoString)
                    .font(.headline)
                Spacer()
                if backup.isExpired {
                    Text(NSLocalizedString("EXPIRED"))
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.red.opacity(0.2))
                        )
                }
            }
            
            Text(String(
                format: NSLocalizedString("MIGRATION_BACKUP_COUNT"),
                backup.migrations.count
            ))
            .font(.subheadline)
            .foregroundColor(.secondary)
            
            if !backup.isExpired {
                Text(expiresInString)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Show first few manga titles
            if !backup.migrations.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(backup.migrations.prefix(3), id: \.mangaId) { migration in
                        HStack(spacing: 8) {
                            Image(systemName: "book.fill")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(migration.title)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    
                    if backup.migrations.count > 3 {
                        Text(String(
                            format: NSLocalizedString("AND_MORE_COUNT"),
                            backup.migrations.count - 3
                        ))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        MigrationBackupsView()
    }
}
