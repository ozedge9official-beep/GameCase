import SwiftUI

extension LCStorageError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .insufficientSpace(required, available):
            return "lc.storage.insufficient".loc.localizeWithFormat(
                ByteCountFormatter.string(fromByteCount: required, countStyle: .file),
                ByteCountFormatter.string(fromByteCount: available, countStyle: .file))
        case .archiveSpace: return "lc.storage.archiveSpace".loc
        case .invalidSize: return "lc.storage.invalidSize".loc
        }
    }
}

struct LCBackupManagementView: View {
    // Capture the selected container when opening this sheet. A later model
    // refresh must not redirect a pending restore into another container.
    let documents: URL
    @Environment(\.dismiss) private var dismiss
    @State private var backups: [LCSaveBackupStore.Backup] = []
    @State private var busy = false
    @State private var pending: LCSaveBackupStore.Backup?
    @State private var deleting = false
    @State private var confirm = false
    @State private var message: String?
    @State private var share: SharedFile?
    private struct SharedFile: Identifiable {
        let id = UUID()
        let url: URL
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    Button("lc.backups.create".loc) { create() }.disabled(!FileManager.default.fileExists(atPath: documents.appendingPathComponent("save").path))
                    if backups.isEmpty { Text("lc.backups.none".loc).foregroundColor(.secondary) }
                    ForEach(backups) { backup in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(verbatim: backup.id).font(.subheadline)
                            if let date = backup.date {
                                Text(date, style: .date).font(.caption).foregroundColor(.secondary)
                            }
                            HStack(spacing: 20) {
                                Button("lc.backups.restore".loc) { pending = backup; deleting = false; confirm = true }
                                Button("lc.backups.export".loc) { export(backup) }
                                Button("lc.common.delete".loc, role: .destructive) { pending = backup; deleting = true; confirm = true }
                            }
                            .font(.subheadline)
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 4)
                    }
                } footer: { Text("lc.backups.note".loc) }
                if busy { ProgressView("lc.save.working".loc) }
            }
            .disabled(busy)
            .navigationTitle("lc.backups.title".loc)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("lc.common.done".loc) { dismiss() }.disabled(busy) }
            }
        }
        .interactiveDismissDisabled(busy)
        .onAppear { reload() }
        .confirmationDialog(deleting ? "lc.backups.deleteTitle".loc : "lc.backups.restoreTitle".loc, isPresented: $confirm, titleVisibility: .visible) {
            Button(deleting ? "lc.common.delete".loc : "lc.backups.restore".loc, role: .destructive) {
                if let pending { apply(pending, delete: deleting) }
                pending = nil
            }
            Button("lc.common.cancel".loc, role: .cancel) { pending = nil }
        } message: {
            Text(deleting ? "lc.backups.deleteMessage".loc : "lc.backups.restoreMessage".loc)
        }
        .sheet(item: $share) { item in ActivityViewController(activityItems: [item.url]) }
        .alert("lc.backups.title".loc, isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("lc.common.ok".loc, role: .cancel) {}
        } message: { Text(message ?? "") }
    }

    private func reload() {
        busy = true
        Task { @MainActor in
            do { backups = try await Task.detached { try LCSaveBackupStore.list(in: documents) }.value }
            catch { message = error.localizedDescription }
            busy = false
        }
    }

    private func create() {
        busy = true
        Task { @MainActor in
            do {
                let result = try await Task.detached {
                    try await LCSaveBackupStore.create(of: documents.appendingPathComponent("save"), in: documents)
                }.value
                message = result == nil ? "lc.backups.emptySave".loc : "lc.backups.created".loc
            } catch { message = error.localizedDescription }
            reload()
        }
    }

    private func apply(_ backup: LCSaveBackupStore.Backup, delete: Bool) {
        busy = true
        Task { @MainActor in
            do {
                try await Task.detached { () async throws -> Void in
                    if delete { try LCSaveBackupStore.delete(backup.url, in: documents) }
                    else { try await LCSaveBackupStore.restore(backup.url, in: documents) }
                }.value
                if !delete { message = "lc.backups.restored".loc }
            } catch { message = error.localizedDescription }
            reload()
        }
    }

    private func export(_ backup: LCSaveBackupStore.Backup) {
        busy = true
        Task { @MainActor in
            do {
                let url = try await Task.detached { () -> URL in
                    try LCSaveBackupStore.validate(backup.url, in: documents)
                    _ = try LCFileTree.scan(backup.url)
                    guard let data = LCUtils.zipData(forDirectory: backup.url), !data.isEmpty else { throw LCSaveDataError.archiveFailed }
                    let destination = FileManager.default.temporaryDirectory.appendingPathComponent("save-backup-\(UUID().uuidString).zip")
                    try LCStorageCapacity.check(sizes: [Int64(data.count)], at: destination)
                    try data.write(to: destination, options: .atomic)
                    return destination
                }.value
                share = SharedFile(url: url)
            } catch { message = error.localizedDescription }
            busy = false
        }
    }
}
