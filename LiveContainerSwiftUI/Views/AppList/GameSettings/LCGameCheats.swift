import SwiftUI
import UniformTypeIdentifiers

extension LCGameCheats {
    static func cheatsContext(for app: LCAppModel) -> (container: LCContainer, cheatsDir: URL)? {
        guard let container = LCGameLibraryInfo.defaultContainer(for: app) else {
            return nil
        }
        let cheatsDir = container.containerURL.appendingPathComponent("Documents/cheats", isDirectory: true)
        return (container, cheatsDir)
    }
}

extension LCGameCheatError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidFileName: return "lc.cheats.errorName".loc
        case .invalidContent: return "lc.cheats.errorContent".loc
        case .tooLarge: return "lc.cheats.errorSize".loc
        case .ambiguousBuild: return "lc.cheats.errorDuplicate".loc
        case .staleFile: return "lc.cheats.errorChanged".loc
        }
    }
}

// MARK: - 设置页「金手指」组（导入 + 条目开关 + 删除）

/// Imports are bounded and prepared off the UI thread. The launcher remains
/// the single writer of DM_CHEATS in env.txt.
struct LCGameCheatsSectionView: View {
    let app: LCAppModel
    /// 宿主页面的状态刷新计数：其他组动作后 bump，本组随之重算
    var refreshToken: Int = 0

    @State private var files: [LCGameCheats.CheatFile] = []
    @State private var hasContainer = false
    @State private var expandedBuildID: String?
    @State private var picking = false
    @State private var importing = false
    @State private var enabled = true
    @State private var buildIDs = Set<String>()
    @State private var lastRun: String?
    @State private var showingLog = false
    @State private var pendingPayloads: [PendingCheat] = []
    @State private var pendingProblems: [String] = []
    @State private var overwriteNames = ""
    @State private var confirmImportOverwrite = false
    @State private var pendingDelete: LCGameCheats.CheatFile?
    @State private var confirmDelete = false
    @State private var resultTitle: String?
    @State private var resultMessage: String?

    /// 已校验待落位的导入内容（数据在选择器回调的安全作用域内读好）
    private typealias PendingCheat = LCGameCheats.ImportPayload

    // 与 LCGameModsSectionView / LCGameSettingsView 的 LCNXColor 同值，深浅动态变体亦同
    private static let cream = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 1, green: 0.94, blue: 0.84, alpha: 1)
            : UIColor(red: 0.66, green: 0.47, blue: 0.16, alpha: 1)
    })
    private static let surface = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.10, green: 0.10, blue: 0.11, alpha: 1)
            : UIColor(red: 1, green: 1, blue: 1, alpha: 1)
    })
    private static let hairline = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.08)
            : UIColor.black.withAlphaComponent(0.08)
    })

    var body: some View {
        // Group 透明包裹：无容器时整组缺席，与 Mod 组自隐同效
        Group {
            if hasContainer {
                section
            }
        }
        .onAppear { reload() }
        .onChange(of: refreshToken) { _ in reload() }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.plainText, .folder], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                pickedCheatFiles(urls)
            } else if case .failure(let error) = result {
                resultTitle = "lc.cheats.import".loc
                resultMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $showingLog) { LCGameLogView(app: app) }
        .confirmationDialog("lc.cheats.importOverwriteTitle".loc, isPresented: $confirmImportOverwrite, titleVisibility: .visible) {
            Button("lc.cheats.replace".loc, role: .destructive) {
                writePending()
            }
            Button("lc.common.cancel".loc, role: .cancel) {
                pendingPayloads = []
                pendingProblems = []
            }
        } message: {
            Text("lc.cheats.importOverwriteMessage".loc.localizeWithFormat(overwriteNames))
        }
        .confirmationDialog("lc.cheats.deleteConfirmTitle".loc, isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("lc.cheats.delete".loc, role: .destructive) {
                if let file = pendingDelete {
                    runDelete(file)
                }
                pendingDelete = nil
            }
            Button("lc.common.cancel".loc, role: .cancel) {
                pendingDelete = nil
            }
        } message: {
            Text("lc.cheats.deleteConfirmMessage".loc.localizeWithFormat(pendingDelete?.buildID ?? ""))
        }
        .alert(resultTitle ?? "", isPresented: resultPresented) {
            Button("lc.common.ok".loc, role: .cancel) {}
        } message: {
            Text(resultMessage ?? "")
        }
    }

    private var resultPresented: Binding<Bool> {
        Binding(
            get: { resultMessage != nil },
            set: { if !$0 { resultMessage = nil; resultTitle = nil } }
        )
    }

    private var section: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("lc.cheats.section".loc.uppercased())
                .font(.system(size: 11.5, weight: .semibold))
                .tracking(1.6)
                .foregroundColor(Self.cream.opacity(0.72))
            VStack(alignment: .leading, spacing: 14) {
                Toggle("lc.cheats.enabled".loc, isOn: Binding(get: { enabled }, set: { value in
                    guard let context = LCGameCheats.cheatsContext(for: app) else { return }
                    do {
                        try LCGameCheats.setEnabled(value, in: context.cheatsDir.deletingLastPathComponent())
                        reload()
                    } catch {
                        resultTitle = "lc.cheats.section".loc
                        resultMessage = error.localizedDescription
                    }
                }))
                .tint(Self.cream)
                Text(enabled ? "lc.cheats.enabledNote".loc : "lc.cheats.disabledNote".loc)
                    .font(.footnote).foregroundColor(.secondary)
                Text(buildIDs.isEmpty ? "lc.cheats.buildUnknown".loc : "lc.cheats.currentBuild".loc.localizeWithFormat(buildIDs.sorted().joined(separator: ", ")))
                    .font(.footnote.monospaced()).textSelection(.enabled)
                    .foregroundColor(.secondary)
                if files.isEmpty {
                    Text("lc.cheats.none".loc)
                        .font(.system(size: 14))
                        .foregroundColor(.primary.opacity(0.72))
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                        if index > 0 {
                            Rectangle()
                                .fill(Color.primary.opacity(0.06))
                                .frame(height: 1)
                        }
                        fileBlock(file)
                    }
                }
                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 1)
                Button {
                    picking = true
                } label: {
                    HStack(spacing: 8) {
                        Text("lc.cheats.import".loc)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.primary)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.primary.opacity(0.4))
                    }
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(importing)
                if importing { ProgressView() }
                if let lastRun {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("lc.cheats.lastRun".loc).font(.footnote.bold())
                        Text(verbatim: lastRun).font(.caption.monospaced()).textSelection(.enabled)
                        Button("lc.cheats.viewLog".loc) { showingLog = true }
                    }
                }
                Text("lc.cheats.note".loc)
                    .font(.system(size: 12.5))
                    .foregroundColor(.primary.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(Self.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Self.hairline, lineWidth: 1)
            }
        }
    }

    /// 一个文件块：头行（build ID + 条目数 + 删除）点按展开 / 收起，
    /// 展开后逐条列条目开关。
    private func fileBlock(_ file: LCGameCheats.CheatFile) -> some View {
        let expanded = expandedBuildID == file.buildID
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    expandedBuildID = expanded ? nil : file.buildID
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(file.buildID)
                                .font(.system(size: 15, weight: .semibold).monospaced())
                                .foregroundColor(.primary)
                            Text("lc.cheats.entries".loc.localizeWithFormat(String(file.entries.count)))
                                .font(.system(size: 12.5))
                                .foregroundColor(.primary.opacity(0.45))
                            if !buildIDs.isEmpty {
                                Text(buildIDs.contains(file.buildID) ? "lc.cheats.buildMatch".loc : "lc.cheats.buildMismatch".loc)
                                    .font(.caption)
                    .foregroundColor(buildIDs.contains(file.buildID) ? Color.secondary : Color.orange)
                            }
                        }
                        Spacer(minLength: 8)
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.primary.opacity(0.4))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button {
                    pendingDelete = file
                    confirmDelete = true
                } label: {
                    Text("lc.cheats.delete".loc)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor(.red.opacity(0.85))
                }
                .buttonStyle(.plain)
            }
            if expanded {
                if file.headerCount > 256 || file.entries.contains(where: { $0.words.count > 8192 }) {
                    Text("lc.cheats.limitNote".loc).font(.footnote).foregroundColor(.orange)
                }
                if file.entries.isEmpty {
                    Text("lc.cheats.errorContent".loc).font(.footnote).foregroundColor(.orange)
                }
                if Set(file.entries.map(\.name)).count != file.entries.count {
                    Text("lc.cheats.duplicateNote".loc).font(.footnote).foregroundColor(.secondary)
                }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(file.entries.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 {
                            Rectangle()
                                .fill(Color.primary.opacity(0.05))
                                .frame(height: 1)
                        }
                        entryRow(file: file, entry: entry)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 一行条目：名字 + 开关；master 显示「恒开」不可关
    private func entryRow(file: LCGameCheats.CheatFile, entry: LCGameCheats.CheatEntry) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.key)
                    .font(.system(size: 14))
                    .foregroundColor(.primary.opacity(0.88))
                    .lineLimit(2)
                if !entry.invalidLines.isEmpty {
                    Text("lc.cheats.invalidLines".loc.localizeWithFormat(entry.invalidLines.map(String.init).joined(separator: ", ")))
                        .font(.caption).foregroundColor(.orange)
                }
            }
            Spacer(minLength: 8)
            if entry.isMaster {
                Text("lc.cheats.alwaysOn".loc)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.4))
            } else {
                Toggle("", isOn: entryBinding(file: file, entry: entry))
                    .labelsHidden()
                    .tint(Self.cream)
                    .disabled(!enabled)
            }
        }
        .frame(minHeight: 44)
    }

    private func entryBinding(file: LCGameCheats.CheatFile, entry: LCGameCheats.CheatEntry) -> Binding<Bool> {
        Binding(
            get: { file.isOn(entry) },
            set: { newValue in runToggle(file: file, entry: entry, on: newValue) }
        )
    }

    // MARK: 动作

    private func reload() {
        if let context = LCGameCheats.cheatsContext(for: app) {
            hasContainer = true
            files = LCGameCheats.installedFiles(in: context.cheatsDir)
            enabled = LCGameCheats.isEnabled(in: context.cheatsDir.deletingLastPathComponent())
            if let path = app.appInfo.bundlePath() { buildIDs = LCGameCheats.buildIDs(in: URL(fileURLWithPath: path)) }
            else { buildIDs = [] }
            let log = context.cheatsDir.deletingLastPathComponent().appendingPathComponent("log.txt")
            if let tail = LCGameLogReader.readTail(of: log) {
                let lines = tail.text.components(separatedBy: .newlines).filter {
                    $0.localizedCaseInsensitiveContains("cheats:") || $0.localizedCaseInsensitiveContains("cheat \"")
                }
                if !lines.isEmpty {
                    let date = (try? log.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                    let stamp = date.map { DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .short) } ?? ""
                    lastRun = stamp + "\n" + lines.suffix(6).map { String($0.prefix(300)) }.joined(separator: "\n")
                } else { lastRun = nil }
            } else { lastRun = nil }
        } else {
            hasContainer = false
            files = []
        }
        // 只有一个文件时默认展开（最常见情形，省一次点按）
        if files.count == 1 {
            expandedBuildID = files[0].buildID
        } else if let expandedBuildID, !files.contains(where: { $0.buildID == expandedBuildID }) {
            self.expandedBuildID = nil
        }
    }

    private func runToggle(file: LCGameCheats.CheatFile, entry: LCGameCheats.CheatEntry, on: Bool) {
        do {
            try LCGameCheats.setEntry(entry, on: on, file: file)
            reload()
        } catch {
            reload()
            resultTitle = "lc.cheats.section".loc
            resultMessage = "lc.cheats.failed".loc.localizeWithFormat(error.localizedDescription)
        }
    }

    private func runDelete(_ file: LCGameCheats.CheatFile) {
        do {
            try LCGameCheats.delete(file: file)
            reload()
        } catch {
            resultTitle = "lc.cheats.section".loc
            resultMessage = "lc.cheats.failed".loc.localizeWithFormat(error.localizedDescription)
        }
    }

    private func pickedCheatFiles(_ urls: [URL]) {
        importing = true
        let title = app.bundleIdentifier.split(separator: ".").last.map(String.init)
        Task { @MainActor in
            let prepared = await Task.detached(priority: .userInitiated) { () -> ([PendingCheat], [String]) in
                var payloads: [PendingCheat] = []
                var problems: [String] = []
                var total = 0
                for url in urls {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    do {
                        let isFolder = try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
                        let sources = isFolder ? try LCGameCheats.sourceFiles(in: url, titleID: title) : [url]
                        if sources.isEmpty { problems.append("lc.cheats.folderEmpty".loc.localizeWithFormat(url.lastPathComponent)) }
                        for source in sources {
                            let name = source.lastPathComponent
                            guard LCGameCheats.isCheatFileName(name) else {
                                problems.append("lc.cheats.importInvalidName".loc.localizeWithFormat(name)); continue
                            }
                            do {
                                let data = try LCGameCheats.readData(at: source)
                                total += data.count
                                guard total <= 32 * 1024 * 1024 else { throw LCGameCheatError.tooLarge }
                                let parsed = try LCGameCheats.validated(data)
                                payloads.append(PendingCheat(fileName: name, data: Data(parsed.text.utf8)))
                            } catch { problems.append(name + ": " + error.localizedDescription) }
                            if total > 32 * 1024 * 1024 { break }
                        }
                    } catch { problems.append(url.lastPathComponent + ": " + error.localizedDescription) }
                    if total > 32 * 1024 * 1024 { break }
                }
                let unique = LCGameCheats.uniqueImports(payloads)
                problems.append(contentsOf: unique.conflicts.map { "lc.cheats.batchConflict".loc.localizeWithFormat($0) })
                return (unique.files, problems)
            }.value
            importing = false
            prepareImport(prepared.0, problems: prepared.1)
        }
    }

    private func prepareImport(_ payloads: [PendingCheat], problems: [String]) {
        guard !payloads.isEmpty else {
            if !problems.isEmpty {
                resultTitle = "lc.cheats.import".loc
                resultMessage = problems.joined(separator: "\n")
            }
            return
        }
        let existing = Set(files.map { $0.fileURL.lastPathComponent.lowercased() })
        let conflicts = payloads
            .map { LCGameCheats.normalizedFileName($0.fileName) }
            .filter { existing.contains($0.lowercased()) }
        if conflicts.isEmpty {
            pendingPayloads = payloads
            pendingProblems = problems
            writePending()
        } else {
            pendingPayloads = payloads
            pendingProblems = problems
            overwriteNames = conflicts.joined(separator: ", ")
            confirmImportOverwrite = true
        }
    }

    /// 落位全部待导入文件并汇报（成功数 + 逐条跳过原因）
    private func writePending() {
        guard let context = LCGameCheats.cheatsContext(for: app) else { return }
        var imported = 0
        var problems = pendingProblems
        for payload in pendingPayloads {
            do {
                _ = try LCGameCheats.importCheatFile(fileName: payload.fileName, data: payload.data, into: context.cheatsDir)
                imported += 1
            } catch LCGameCheatError.invalidFileName {
                problems.append("lc.cheats.importInvalidName".loc.localizeWithFormat(payload.fileName))
            } catch LCGameCheatError.invalidContent {
                problems.append("lc.cheats.importInvalidContent".loc.localizeWithFormat(payload.fileName))
            } catch {
                problems.append("lc.cheats.failed".loc.localizeWithFormat(error.localizedDescription))
            }
        }
        pendingPayloads = []
        pendingProblems = []
        reload()
        var lines: [String] = []
        if imported > 0 {
            lines.append("lc.cheats.importDone".loc.localizeWithFormat(String(imported)))
        }
        lines.append(contentsOf: problems)
        if !lines.isEmpty {
            resultTitle = "lc.cheats.import".loc
            resultMessage = lines.joined(separator: "\n")
        }
    }
}
