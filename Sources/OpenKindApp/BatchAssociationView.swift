import SwiftUI
import AppKit
import UniformTypeIdentifiers
import OpenKindCore

private struct BatchItem: Identifiable {
    let file: FileAssociation
    let recognized: Bool
    var id: String { file.ext }
}

struct BatchAssociationView: View {
    let app: URL
    @ObservedObject var store: AssociationStore
    @Environment(\.dismiss) private var dismiss
    @State private var items: [BatchItem] = []
    @State private var selected: Set<String> = []
    @State private var statuses: [String: String] = [:]
    @State private var search = ""
    @State private var category: FileCategory?
    @State private var showAll = false
    @State private var confirm = false
    @State private var working = false
    @State private var stopRequested = false
    @State private var message: String?

    private var appName: String { FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "") }
    private var visible: [BatchItem] {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return items.filter { (showAll || $0.recognized || $0.file.appURL?.standardizedFileURL == app.standardizedFileURL) && (category == nil || $0.file.category == category) && (term.isEmpty || $0.file.ext.localizedCaseInsensitiveContains(term) || $0.file.appName.localizedCaseInsensitiveContains(term)) }
    }
    private func canSelect(_ item: BatchItem) -> Bool {
        item.file.type != nil && item.file.appURL?.standardizedFileURL != app.standardizedFileURL && statuses[item.id] == nil
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 12) {
                ApplicationIcon(url: app, size: 42)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("关联文件类型", "Associate file types")).font(.title2.bold())
                    Text(L("选择由 \(appName) 默认打开的类型", "Choose types to open with \(appName) by default")).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }
            Text(L("默认显示 macOS 识别支持的类型。也可显示其他类型并手动选择；实际能否打开由应用和系统决定。", "Shows types recognized by macOS by default. You may also choose other types; actual support depends on the app and macOS.")).font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField(L("搜索扩展名或当前应用", "Search extensions or current apps"), text: $search).textFieldStyle(.roundedBorder)
                Picker(L("分类", "Category"), selection: $category) {
                    Text(L("全部分类", "All categories")).tag(Optional<FileCategory>.none)
                    ForEach(FileCategory.allCases) { Text($0.localizedName).tag(Optional($0)) }
                }.frame(width: 150)
            }
            VStack(alignment: .leading, spacing: 8) {
                Toggle(L("显示其他类型", "Show other types"), isOn: $showAll).toggleStyle(.checkbox)
                HStack {
                    Button(L("全选当前列表", "Select all shown")) {
                        for item in visible where canSelect(item) { selected.insert(item.id) }
                    }
                    Button(L("选中已识别", "Select recognized")) {
                        for item in visible where item.recognized && canSelect(item) { selected.insert(item.id) }
                    }
                    Spacer()
                    Button(L("清空", "Clear")) { selected.removeAll() }.disabled(selected.isEmpty)
                }
            }.disabled(working)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(visible) { item in
                        HStack(alignment: .center, spacing: 10) {
                            Toggle("", isOn: Binding(get: { selected.contains(item.id) }, set: { if $0 { selected.insert(item.id) } else { selected.remove(item.id) } }))
                                .labelsHidden().toggleStyle(.checkbox).disabled(working || !canSelect(item))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(".\(item.file.ext)").font(.system(size: 12, weight: .semibold))
                                Text(L("当前：\(item.file.appName)", "Current: \(item.file.appName)")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Text(statuses[item.id] ?? (item.file.appURL?.standardizedFileURL == app.standardizedFileURL ? L("已是默认", "Already default") : (item.file.type == nil ? L("系统未识别类型", "Type not recognized") : (item.recognized ? L("系统已识别支持", "Recognized by macOS") : L("系统未声明支持", "Not declared to macOS")))))
                                .font(.caption).foregroundStyle(item.recognized ? Color.secondary : Color.orange)
                        }.padding(.horizontal, 10).padding(.vertical, 7)
                        Divider()
                    }
                    if visible.isEmpty { Text(L("当前范围没有文件类型。", "No file types in this view.")).foregroundStyle(.secondary).padding(24) }
                }
            }.frame(maxHeight: .infinity).background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 9))
            Text(L("多个扩展名可能共享同一系统类型；修改一项可能影响其他扩展名。已完成的更改不会自动撤销。", "Extensions may share a system type, so other extensions can be affected. Completed changes are not automatically undone.")).font(.caption).foregroundStyle(.secondary)
            if let message { Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            HStack {
                Text(L("已选 \(selected.count) 种", "\(selected.count) selected")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if working { ProgressView().controlSize(.small); Button(L("停止后续操作", "Stop remaining changes")) { stopRequested = true }.disabled(stopRequested) }
                Button(L("关闭", "Close")) { dismiss() }.disabled(working)
                Button(L("应用关联…", "Apply associations…")) { confirm = true }.buttonStyle(.borderedProminent).disabled(working || selected.isEmpty)
            }
        }.padding(20).frame(minWidth: 520, minHeight: 440)
        .onAppear { load() }
        .alert(L("确认更改默认应用？", "Change default apps?"), isPresented: $confirm) {
            Button(L("取消", "Cancel"), role: .cancel) { }
            Button(L("应用", "Apply")) { apply() }
        } message: {
            let unknown = items.filter { selected.contains($0.id) && !$0.recognized }.count
            Text(L("将尝试把 \(selected.count) 种类型关联到 \(appName)，其中 \(unknown) 种未被系统声明支持。共享类型可能影响其他扩展名。", "Attempt to associate \(selected.count) types with \(appName), including \(unknown) not declared to macOS. Shared types may affect other extensions."))
        }
    }
    private func load() {
        store.reload()
        items = store.availableTypes(for: app).map { item in
            let supported = item.type.map { NSWorkspace.shared.urlsForApplications(toOpen: $0).contains { $0.standardizedFileURL == app.standardizedFileURL } } ?? false
            return BatchItem(file: item, recognized: supported)
        }.sorted { if $0.recognized != $1.recognized { return $0.recognized }; return $0.file.ext < $1.file.ext }
    }
    private func decision(_ item: BatchItem) -> ChangeDecision {
        let type = UTType(filenameExtension: item.file.ext)
        let current = type.flatMap { NSWorkspace.shared.urlForApplication(toOpen: $0) }
        let candidates = Set(type.map { NSWorkspace.shared.urlsForApplications(toOpen: $0).map { $0.standardizedFileURL.path } } ?? [])
        return ChangeGuard.evaluate(expectedType: item.file.type?.identifier ?? "", actualType: type?.identifier, expectedCurrent: item.file.appURL?.standardizedFileURL.path, actualCurrent: current?.standardizedFileURL.path, target: app.standardizedFileURL.path, candidates: candidates, targetExists: FileManager.default.fileExists(atPath: app.path), allowUnregistered: !item.recognized)
    }
    private func apply() {
        let chosen = items.filter { selected.contains($0.id) && canSelect($0) }
        guard !chosen.isEmpty else { return }
        guard chosen.allSatisfy({ decision($0) == .allowed }) else {
            message = L("应用或系统关联已变化，请关闭后重新打开此窗口。", "The app or system associations changed. Close and reopen this window."); return
        }
        let proposals = chosen.compactMap { item in item.file.type.map { ChangeProposal(fileExtension: item.id, typeID: $0.identifier, target: app.standardizedFileURL.path, current: item.file.appURL?.standardizedFileURL.path) } }
        let groups: [[String]]
        do { groups = try ChangeGrouping.group(proposals) }
        catch { message = L("共享文件类型的当前设置不一致，请刷新后重试。", "Current defaults for a shared type are inconsistent. Refresh and try again."); return }
        let byID = Dictionary(uniqueKeysWithValues: chosen.map { ($0.id, $0) })
        working = true; store.isApplying = true; stopRequested = false; message = nil
        Task { @MainActor in
            var completed: [String] = []
            defer { working = false; store.isApplying = false; store.remember(completed) }
            for group in groups {
                if stopRequested { message = L("已停止后续操作，已完成的更改保留。", "Remaining changes stopped; completed changes remain."); break }
                guard let id = group.first, let item = byID[id], let type = item.file.type, group.allSatisfy({ byID[$0].map { decision($0) == .allowed } ?? false }) else {
                    message = L("系统关联已变化，已停止后续操作。", "A system association changed; remaining changes were stopped."); break
                }
                let failure: Error? = await withCheckedContinuation { continuation in
                    NSWorkspace.shared.setDefaultApplication(at: app, toOpen: type) { continuation.resume(returning: $0) }
                }
                guard failure == nil, NSWorkspace.shared.urlForApplication(toOpen: type)?.standardizedFileURL == app.standardizedFileURL else {
                    for ext in group { statuses[ext] = L("设置失败", "Failed"); selected.remove(ext) }
                    message = L("系统拒绝或未保存更改，已停止后续操作；之前完成的更改保留。", "macOS rejected or did not save the change. Remaining changes stopped; earlier changes remain."); break
                }
                for ext in group { statuses[ext] = L("已应用", "Applied"); selected.remove(ext); completed.append(ext) }
            }
            if message == nil { message = L("已完成 \(completed.count) 种类型的关联。", "Associated \(completed.count) file types.") }
        }
    }
}
