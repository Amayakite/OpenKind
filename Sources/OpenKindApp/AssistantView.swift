import SwiftUI
import AppKit
import UniformTypeIdentifiers
import OpenKindCore

private struct LocalTypeSnapshot {
    let file: FileAssociation
    let currentURL: URL?
    let typeID: String
    let choices: [String: URL]
}
private struct PreparedRequest: Identifiable {
    let id = UUID()
    let context: AIRequestContext
    let config: ProviderConfiguration
    let profileID: UUID
    let profileName: String
    let snapshots: [String: LocalTypeSnapshot]
}
private struct AppliedChange: Identifiable {
    let id: String
    let snapshot: LocalTypeSnapshot
    let old: URL?
    let new: URL
}

struct AssistantView: View {
    @ObservedObject var store: AssociationStore
    @ObservedObject var settings: AISettingsStore
    @State private var showSettings = false
    @State private var preference = ""
    @State private var selectedTypes: Set<String> = ["docx", "xlsx", "pptx"]
    @State private var search = ""
    @State private var prepared: PreparedRequest?
    @State private var lastRequest: PreparedRequest?
    @State private var result: AIResult?
    @State private var selectedResults: Set<String> = []
    @State private var applyResults: [String: String] = [:]
    @State private var applied: [AppliedChange] = []
    @State private var working = false
    @State private var task: Task<Void, Never>?
    @State private var error: String?
    @State private var info: String?
    private var visibleTypes: [FileAssociation] {
        store.items.filter { search.isEmpty || $0.ext.localizedCaseInsensitiveContains(search.trimmingCharacters(in: CharacterSet(charactersIn: "."))) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(L("AI 助理", "AI assistant")).font(.system(size: 28, weight: .bold))
                    Text(L("描述你的习惯，先预览建议，再决定是否应用。", "Describe your preferences, preview suggestions, then decide what to apply.")).font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { showSettings = true } label: { Label(L("服务设置", "Provider settings"), systemImage: "gearshape") }
            }.padding(.top, 38).padding(.bottom, 18)
            HStack(spacing: 7) {
                Image(systemName: "sparkles").foregroundStyle(.blue)
                Text("\(settings.activeProfile?.name ?? "—") · \(settings.config.model.isEmpty ? L("尚未选择模型", "No model selected") : settings.config.model)")
                    .font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer()
                Text(L("发送前可检查内容", "Review before sending")).font(.caption).foregroundStyle(.secondary)
            }.padding(11).background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 9)).padding(.bottom, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    section("1", title: L("告诉助理你的偏好", "Tell the assistant your preferences"), subtitle: L("例如：办公文件分别使用 WordCraft、GridCraft 和 DeckCraft。", "For example: use WordCraft, GridCraft and DeckCraft for office files.")) {
                        TextEditor(text: $preference).font(.system(size: 13)).frame(height: 70).padding(5)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.12)))
                        Text(L("你的描述会随请求发送，请避免输入不希望分享的信息。", "Your description is sent with the request. Avoid sharing sensitive information.")) .font(.caption).foregroundStyle(.secondary)
                    }
                    section("2", title: L("选择要分析的文件类型", "Choose file types to analyze"), subtitle: L("只发送选中类型的当前应用和候选应用，最多 20 种。", "Only selected types, current apps and candidate apps are sent; maximum 20.")) {
                        HStack { TextField(L("搜索扩展名", "Search extensions"), text: $search).textFieldStyle(.roundedBorder); Text(L("已选 \(selectedTypes.count) / 20", "\(selectedTypes.count) / 20 selected")).font(.caption).foregroundStyle(.secondary); Button(L("清空", "Clear")) { selectedTypes.removeAll() }.buttonStyle(.borderless) }
                        ScrollView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)], alignment: .leading, spacing: 7) {
                                ForEach(visibleTypes) { item in
                                    Toggle(".\(item.ext)", isOn: Binding(get: { selectedTypes.contains(item.ext) }, set: { value in
                                        if value && selectedTypes.count < 20 { selectedTypes.insert(item.ext) }
                                        else if !value { selectedTypes.remove(item.ext) }
                                    })).toggleStyle(.checkbox).font(.system(size: 12))
                                }
                            }.padding(9)
                        }.frame(height: 110).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08)))
                    }
                    HStack {
                        Button { prepare() } label: { Label(L("预览发送内容", "Review request"), systemImage: "eye") }.buttonStyle(.borderedProminent).disabled(working)
                        if working { ProgressView().controlSize(.small); Text(L("正在处理…", "Working…")).font(.caption).foregroundStyle(.secondary); Button(L("停止", "Stop")) { task?.cancel() } }
                        Spacer()
                    }
                    if let result, let request = lastRequest { resultsSection(result, request: request) }
                    if let info { Text(info).font(.caption).foregroundStyle(.secondary) }
                }.padding(.bottom, 25)
            }
        }.padding(.horizontal, 32).frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear { task?.cancel() }
        .sheet(isPresented: $showSettings) { AISettingsView(settings: settings) }
        .sheet(item: $prepared) { request in preview(request) }
        .alert(L("AI 助理", "AI assistant"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button(L("好", "OK")) { error = nil } } message: { Text(error ?? "") }
    }
    private func section<Content: View>(_ number: String, title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                Text(number).font(.system(size: 11, weight: .bold)).foregroundStyle(.blue).frame(width: 22, height: 22).background(Color.blue.opacity(0.1), in: Circle())
                Text(title).font(.system(size: 14, weight: .semibold))
            }
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
            content()
        }.padding(15).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.primary.opacity(0.07)))
    }
    private func prepare() {
        guard let activeProfile = settings.activeProfile else { error = L("请先启用 AI 配置。", "Enable an AI provider profile first."); return }
        guard !settings.config.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { error = L("请先在服务设置中选择或输入模型。", "Choose or enter a model in provider settings first."); return }
        do { _ = try settings.config.endpoint("models") } catch { self.error = error.localizedDescription; return }
        let prompt = preference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, prompt.count <= 2000, !selectedTypes.isEmpty, selectedTypes.count <= 20 else { error = AIError.invalidContext.localizedDescription; return }
        store.reload()
        var local: [String: LocalTypeSnapshot] = [:]
        var types: [AIFileType] = []
        for item in store.items where selectedTypes.contains(item.ext) {
            guard let type = item.type else { continue }
            var choices: [String: URL] = [:]
            var ambiguous = Set<String>()
            for url in store.candidates(for: item) {
                guard let id = Bundle(url: url)?.bundleIdentifier, !id.isEmpty, id.count <= 200 else { continue }
                if let previous = choices[id], previous.standardizedFileURL != url.standardizedFileURL { ambiguous.insert(id) }
                else { choices[id] = url }
            }
            for id in ambiguous { choices.removeValue(forKey: id) }
            let candidates = choices.sorted { $0.key < $1.key }.prefix(30).map { id, url in AICandidate(id: id, name: String(FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "").prefix(150))) }
            choices = choices.filter { entry in candidates.contains { $0.id == entry.key } }
            types.append(AIFileType(fileExtension: item.ext, current: item.appURL == nil ? nil : String(item.appName.prefix(150)), candidates: candidates))
            local[item.ext] = LocalTypeSnapshot(file: item, currentURL: item.appURL, typeID: type.identifier, choices: choices)
        }
        guard types.count == selectedTypes.count else { error = L("某些文件类型无法被系统识别，请取消选择后重试。", "Some file types are not recognized. Deselect them and try again."); return }
        prepared = PreparedRequest(context: AIRequestContext(preference: prompt, types: types), config: settings.config, profileID: activeProfile.id, profileName: activeProfile.name, snapshots: local)
    }
    private func preview(_ request: PreparedRequest) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(L("确认发送内容", "Confirm request")).font(.title2.bold())
            Text(L("以下信息将发送到你配置的服务；服务商可能记录请求并按其规则收费。", "This information will be sent to your provider, which may retain requests and charge for use.")) .font(.callout).foregroundStyle(.secondary)
            Text(L("配置：\(request.profileName)  ·  服务：\(request.config.baseURL)  ·  模型：\(request.config.model)", "Profile: \(request.profileName)  ·  Service: \(request.config.baseURL)  ·  Model: \(request.config.model)")).font(.caption).textSelection(.enabled)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L("你的描述", "Your description")).font(.caption.bold())
                    Text(request.context.preference).textSelection(.enabled)
                    Divider()
                    ForEach(request.context.types, id: \.fileExtension) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L(".\(item.fileExtension)   当前：\(item.current ?? L("未设置", "Not set"))", ".\(item.fileExtension)   Current: \(item.current ?? L("未设置", "Not set"))")).font(.system(size: 12, weight: .semibold))
                            if item.candidates.isEmpty { Text(L("无系统候选应用", "No system candidate apps")).font(.caption).foregroundStyle(.secondary) }
                            ForEach(item.candidates, id: \.id) { candidate in Text("• \(candidate.name)  (\(candidate.id))").font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }.frame(height: 260).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
            Text(L("不会自动发送文件内容、文件名或完整路径。你的描述请自行检查。", "File contents, names and full paths are not sent automatically. Review your description.")) .font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button(L("取消", "Cancel")) { prepared = nil }; Button(L("发送并获取建议", "Send and get suggestions")) { prepared = nil; send(request) }.buttonStyle(.borderedProminent) }
        }.padding(24).frame(width: 590)
    }
    private func send(_ request: PreparedRequest) {
        guard request.profileID == settings.activeProfile?.id, request.config == settings.config else { error = L("服务设置已更改，请重新预览。", "Provider settings changed. Review the request again."); return }
        do {
            let client = try settings.client()
            working = true; result = nil; applyResults = [:]; info = nil
            task = Task { @MainActor in
                defer { working = false; task = nil }
                do {
                    let response = try await client.recommendations(for: request.context, responseLanguage: AppLanguage.usesChinese ? "Chinese" : "English")
                    try Task.checkCancellation()
                    result = response; lastRequest = request
                    selectedResults = Set(response.recommendations.filter { request.snapshots[$0.fileExtension]?.currentURL?.standardizedFileURL != request.snapshots[$0.fileExtension]?.choices[$0.candidateID]?.standardizedFileURL }.map(\.fileExtension))
                } catch { self.error = error.localizedDescription }
            }
        } catch { self.error = error.localizedDescription }
    }
    private func resultsSection(_ result: AIResult, request: PreparedRequest) -> some View {
        section("3", title: L("检查建议", "Review suggestions"), subtitle: L("建议不会自动执行。选中需要的项目后，再点击应用。", "Suggestions are not applied automatically. Select items and click Apply.")) {
            if result.recommendations.isEmpty { Text(L("助理没有提出变更建议。你可以调整描述或选择的类型后重试。", "No changes suggested. Try adjusting your description or selected file types.")) .font(.callout).foregroundStyle(.secondary) }
            ForEach(result.recommendations) { rec in
                let snapshot = request.snapshots[rec.fileExtension]
                let target = snapshot?.choices[rec.candidateID]
                HStack(alignment: .top, spacing: 10) {
                    Toggle("", isOn: Binding(get: { selectedResults.contains(rec.fileExtension) }, set: { if $0 { selectedResults.insert(rec.fileExtension) } else { selectedResults.remove(rec.fileExtension) } })).labelsHidden().toggleStyle(.checkbox).disabled(working || applyResults[rec.fileExtension] != nil)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(".\(rec.fileExtension)  \(snapshot?.file.appName ?? L("未设置", "Not set"))  →  \(target.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? L("未知应用", "Unknown app"))").font(.system(size: 12, weight: .semibold))
                        Text(rec.reason).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        if let status = applyResults[rec.fileExtension] { Text(status).font(.caption).foregroundStyle(.blue) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.padding(.vertical, 5)
                Divider()
            }
            ForEach(Array(result.notes.enumerated()), id: \.offset) { _, note in Text(note).font(.caption).foregroundStyle(.secondary) }
            Text(L("多个扩展名可能共享系统文件类型，更改一项可能影响其他扩展名。", "Extensions can share a system type; a change may affect other extensions.")) .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(L("应用选中的建议", "Apply selected suggestions")) { applySelected(result, request: request) }.buttonStyle(.borderedProminent).disabled(working || selectedResults.isEmpty)
                if !applied.isEmpty { Button(L("尝试恢复本次更改", "Try to restore changes")) { undo() }.disabled(working) }
            }
        }
    }
    private func applySelected(_ result: AIResult, request: PreparedRequest) {
        let chosen = result.recommendations.filter { selectedResults.contains($0.fileExtension) && applyResults[$0.fileExtension] == nil }
        let typeIDs = chosen.compactMap { request.snapshots[$0.fileExtension]?.typeID }
        guard Set(typeIDs).count == typeIDs.count else { error = L("选中的扩展名中有共享同一系统类型的项目，请只选其中一项；它可能同时影响其他扩展名。", "Selected extensions share a system type. Select only one; other extensions may also be affected."); return }
        working = true; info = nil
        task = Task { @MainActor in
            defer { working = false; task = nil }
            for rec in chosen {
                if Task.isCancelled { info = L("已停止；已完成的更改保留，可尝试恢复。", "Stopped. Completed changes remain and can be restored where possible."); break }
                guard let snapshot = request.snapshots[rec.fileExtension], let target = snapshot.choices[rec.candidateID] else { applyResults[rec.fileExtension] = L("无效建议", "Invalid suggestion"); break }
                let failure = await change(snapshot: snapshot, target: target, expected: snapshot.currentURL)
                if let failure { applyResults[rec.fileExtension] = failure; info = L("已停止后续操作，请检查结果。", "Remaining changes were stopped. Review the results."); break }
                applied.append(AppliedChange(id: rec.fileExtension, snapshot: snapshot, old: snapshot.currentURL, new: target))
                applyResults[rec.fileExtension] = L("已应用", "Applied"); selectedResults.remove(rec.fileExtension)
            }
            store.reload()
        }
    }
    private func change(snapshot: LocalTypeSnapshot, target: URL, expected: URL?) async -> String? {
        let type = UTType(filenameExtension: snapshot.file.ext)
        let current = type.flatMap { NSWorkspace.shared.urlForApplication(toOpen: $0) }
        let candidates = Set(type.map { NSWorkspace.shared.urlsForApplications(toOpen: $0).map { $0.standardizedFileURL.path } } ?? [])
        let decision = ChangeGuard.evaluate(expectedType: snapshot.typeID, actualType: type?.identifier, expectedCurrent: expected?.standardizedFileURL.path, actualCurrent: current?.standardizedFileURL.path, target: target.standardizedFileURL.path, candidates: candidates, targetExists: FileManager.default.fileExists(atPath: target.path))
        switch decision {
        case .typeChanged: return L("文件类型已变化，请重新获取建议", "File type changed. Get new suggestions.")
        case .currentChanged: return L("当前设置已变化，请重新获取建议", "Current default changed. Get new suggestions.")
        case .missingApplication: return L("应用已不存在", "App no longer exists")
        case .unsupportedApplication: return L("应用不再是系统候选，请重新获取建议", "App is no longer a system candidate. Get new suggestions.")
        case .allowed: break
        }
        guard let type else { return L("文件类型已失效", "File type is no longer valid") }
        let operationError: Error? = await withCheckedContinuation { continuation in
            NSWorkspace.shared.setDefaultApplication(at: target, toOpen: type) { continuation.resume(returning: $0) }
        }
        if operationError != nil { return L("系统拒绝或取消了更改", "macOS rejected or cancelled the change") }
        guard NSWorkspace.shared.urlForApplication(toOpen: type)?.standardizedFileURL == target.standardizedFileURL else { return L("系统未保存此更改", "macOS did not save this change") }
        return nil
    }
    private func undo() {
        working = true
        task = Task { @MainActor in
            defer { working = false; task = nil; store.reload() }
            var remaining: [AppliedChange] = []
            for changeRecord in applied.reversed() {
                guard let old = changeRecord.old else { applyResults[changeRecord.id] = L("无法恢复到无默认应用", "Cannot restore an unset default"); remaining.append(changeRecord); continue }
                if let failure = await change(snapshot: changeRecord.snapshot, target: old, expected: changeRecord.new) { applyResults[changeRecord.id] = L("恢复失败：\(failure)", "Restore failed: \(failure)"); remaining.append(changeRecord) }
                else { applyResults[changeRecord.id] = L("已恢复", "Restored") }
            }
            applied = remaining.reversed()
            info = remaining.isEmpty ? L("已恢复可恢复的更改。", "Restorable changes have been restored.") : L("部分项目无法恢复，请查看具体结果。", "Some changes could not be restored. Review the results.")
        }
    }
}
