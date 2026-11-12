import SwiftUI
import AppKit
import UniformTypeIdentifiers
import OpenKindCore

private struct LocalTypeSnapshot {
    let file: FileAssociation
    let currentURL: URL?
    let typeID: String
    let choices: [String: URL]
    let unregisteredChoices: Set<String>
}
private struct PreparedRequest: Identifiable {
    let id = UUID()
    let context: AIRequestContext
    let config: ProviderConfiguration
    let profileID: UUID
    let profileName: String
    let appName: String?
    let truncatedCount: Int
    let snapshots: [String: LocalTypeSnapshot]
}
private struct AppliedChange: Identifiable {
    let id: String
    let snapshot: LocalTypeSnapshot
    let old: URL?
    let new: URL
    let aliases: [String]
}

struct AssistantView: View {
    @ObservedObject var store: AssociationStore
    @ObservedObject var settings: AISettingsStore
    @ObservedObject var appCatalog: ApplicationCatalog
    @State private var mode = 0
    @Binding var selectedApp: DiscoveredApplication?
    @State private var category: FileCategory?
    @State private var showAppPicker = false
    @State private var batchProgress = ""
    @State private var diagnostic: String?
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
            Picker(L("推荐方式", "Recommendation mode"), selection: $mode) {
                Text(L("按应用推荐", "Recommend for an app")).tag(0)
                Text(L("按类型选择", "Choose file types")).tag(1)
            }.pickerStyle(.segmented).frame(maxWidth: 420).padding(.bottom, 12).disabled(working)
            ScrollViewReader { proxy in
              ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if mode == 0 {
                        section("1", title: L("选择想要使用的应用", "Choose the app to use"), subtitle: L("AI 会从常见格式和应用声明的格式中，挑选适合它的类型。", "AI will select suitable types from common formats and the app’s declarations.")) {
                            HStack(spacing: 10) {
                                ApplicationIcon(url: selectedApp?.url, size: 36)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(selectedApp?.name ?? L("尚未选择应用", "No app selected")).font(.system(size: 13, weight: .semibold))
                                    Text(selectedApp == nil ? L("可以选择尚未关联任何文件的应用", "Apps without defaults are available too") : (selectedApp?.hasDocumentDeclarations == false ? L("此应用未声明文件类型", "This app has no declared file types") : L("包含系统声明和 AI 推断", "Includes system declarations and AI inference"))).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(L("选择应用…", "Choose app…")) { showAppPicker = true }.disabled(working)
                            }
                            Picker(L("分析范围", "Scope"), selection: $category) {
                                Text(L("全部类型", "All file types")).tag(Optional<FileCategory>.none)
                                ForEach(FileCategory.allCases) { Text($0.localizedName).tag(Optional($0)) }
                            }.frame(maxWidth: 320).disabled(working)
                            Text(L("最多分析 240 种格式；可能需要多次模型请求。", "Up to 240 formats may be analyzed in multiple model requests.")).font(.caption).foregroundStyle(.secondary)
                        }
                        section("2", title: L("补充偏好（可选）", "Add preferences (optional)"), subtitle: L("例如：只推荐适合写代码的格式，不要修改办公文档。", "For example: recommend code formats, but leave office documents alone.")) {
                            TextEditor(text: $preference).font(.system(size: 13)).frame(height: 55).padding(5)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.12)))
                        }
                    } else {
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
                    }
                    HStack {
                        Button { prepare() } label: { Label(L("分析并推荐…", "Analyze and recommend…"), systemImage: "sparkles") }.buttonStyle(.borderedProminent).disabled(working)
                        if working { ProgressView().controlSize(.small); Text(batchProgress.isEmpty ? L("正在处理…", "Working…") : batchProgress).font(.caption).foregroundStyle(.secondary); Button(L("停止", "Stop")) { task?.cancel() } }
                        Spacer()
                    }
                    if let diagnostic { DiagnosticView(message: diagnostic) }
                    if let result, let request = lastRequest { resultsSection(result, request: request).id("suggestions") }
                    if result == nil && !applied.isEmpty { Button(L("尝试恢复之前的更改", "Try to restore previous changes")) { undo() }.disabled(working) }
                    if let info { Text(info).font(.caption).foregroundStyle(.secondary) }
                }.padding(.bottom, 25)
              }
              .onChange(of: result) { _, value in
                  if value != nil { withAnimation { proxy.scrollTo("suggestions", anchor: .top) } }
              }
            }
        }.padding(.horizontal, 32).frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear { task?.cancel() }
        .onChange(of: mode) { _, _ in clearResults() }
        .onChange(of: selectedApp?.id) { _, _ in clearResults() }
        .onChange(of: category) { _, _ in clearResults() }
        .sheet(isPresented: $showSettings) { AISettingsView(settings: settings) }
        .sheet(isPresented: $showAppPicker) { AppSelectionView(catalog: appCatalog, selection: $selectedApp) }
        .sheet(item: $prepared) { request in preview(request) }
        .alert(L("AI 助理", "AI assistant"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button(L("好", "OK")) { error = nil } } message: { Text(error ?? "") }
    }
    private func clearResults() {
        result = nil; lastRequest = nil; selectedResults.removeAll(); applyResults.removeAll(); info = nil
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
        let typed = preference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard typed.count <= 1500 else { error = L("偏好描述不能超过 1500 字。", "Preferences must be at most 1,500 characters."); return }
        store.reload()
        var local: [String: LocalTypeSnapshot] = [:]
        var types: [AIFileType] = []
        var truncatedCount = 0
        let prompt: String
        if mode == 0 {
            guard let app = selectedApp, FileManager.default.fileExists(atPath: app.url.path) else { error = L("请先选择一个已安装的应用。", "Choose an installed app first."); return }
            prompt = L("请为应用「\(app.name)」推荐适合默认打开的文件类型。只推荐真正适合的类型。\(typed)", "Recommend file types that are genuinely suitable to open by default with \(app.name). \(typed)")
            let eligible = store.availableTypes(for: app.url).filter { category == nil || $0.category == category }
            truncatedCount = max(0, eligible.count - 240)
            for item in eligible.prefix(240) {
                guard let type = item.type else { continue }
                let supported = NSWorkspace.shared.urlsForApplications(toOpen: type).contains { $0.standardizedFileURL == app.url.standardizedFileURL }
                let candidate = AICandidate(id: "selected_app", name: String(app.name.prefix(150)), registered: supported)
                types.append(AIFileType(fileExtension: item.ext, current: item.appURL == nil ? nil : String(item.appName.prefix(150)), candidates: [candidate]))
                local[item.ext] = LocalTypeSnapshot(file: item, currentURL: item.appURL, typeID: type.identifier, choices: [candidate.id: app.url], unregisteredChoices: supported ? [] : [candidate.id])
            }
        } else {
            guard !typed.isEmpty, !selectedTypes.isEmpty, selectedTypes.count <= 20 else { error = AIError.invalidContext.localizedDescription; return }
            prompt = typed
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
                let recognized = Set(NSWorkspace.shared.urlsForApplications(toOpen: type).map { $0.standardizedFileURL.path })
                let candidates = choices.sorted { $0.key < $1.key }.prefix(30).map { id, url in AICandidate(id: id, name: String(FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "").prefix(150)), registered: recognized.contains(url.standardizedFileURL.path)) }
                choices = choices.filter { entry in candidates.contains { $0.id == entry.key } }
                types.append(AIFileType(fileExtension: item.ext, current: item.appURL == nil ? nil : String(item.appName.prefix(150)), candidates: candidates))
                local[item.ext] = LocalTypeSnapshot(file: item, currentURL: item.appURL, typeID: type.identifier, choices: choices, unregisteredChoices: Set(candidates.filter { !$0.registered }.map(\.id)))
            }
            guard types.count == selectedTypes.count else { error = L("某些文件类型无法被系统识别，请取消选择后重试。", "Some file types are not recognized. Deselect them and try again."); return }
        }
        guard !types.isEmpty else { error = L("当前范围没有可分析的文件类型。", "There are no file types in this scope."); return }
        prepared = PreparedRequest(context: AIRequestContext(preference: prompt, types: types), config: settings.config, profileID: activeProfile.id, profileName: activeProfile.name, appName: mode == 0 ? selectedApp?.name : nil, truncatedCount: truncatedCount, snapshots: local)
    }
    private func preview(_ request: PreparedRequest) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(L("确认发送内容", "Confirm request")).font(.title2.bold())
            Text(L("以下信息将发送到你配置的服务；服务商可能记录请求并按其规则收费。", "This information will be sent to your provider, which may retain requests and charge for use.")) .font(.callout).foregroundStyle(.secondary)
            Text(L("配置：\(request.profileName)  ·  服务：\(request.config.baseURL)  ·  模型：\(request.config.model)", "Profile: \(request.profileName)  ·  Service: \(request.config.baseURL)  ·  Model: \(request.config.model)")).font(.caption).textSelection(.enabled)
            Text(L("将分析 \(request.context.types.count) 种类型，分 \((request.context.types.count + 19) / 20) 次请求。", "Analyzing \(request.context.types.count) types in \((request.context.types.count + 19) / 20) requests.")).font(.caption.weight(.semibold))
            if request.truncatedCount > 0 { Text(L("还有 \(request.truncatedCount) 种类型超出上限，本次不会发送。", "Another \(request.truncatedCount) types exceed the limit and will not be sent.")).font(.caption).foregroundStyle(.orange) }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L("你的描述", "Your description")).font(.caption.bold())
                    Text(request.context.preference).textSelection(.enabled)
                    Divider()
                    ForEach(request.context.types, id: \.fileExtension) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L(".\(item.fileExtension)   当前：\(item.current ?? L("未设置", "Not set"))", ".\(item.fileExtension)   Current: \(item.current ?? L("未设置", "Not set"))")).font(.system(size: 12, weight: .semibold))
                            if item.candidates.isEmpty { Text(L("无系统候选应用", "No system candidate apps")).font(.caption).foregroundStyle(.secondary) }
                            ForEach(item.candidates, id: \.id) { candidate in
                                Text("• \(candidate.name)\(candidate.id == "selected_app" ? "" : " (\(candidate.id))") — \(candidate.registered ? L("系统已识别", "System registered") : L("系统未声明支持", "Not declared to macOS"))").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            }
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
            working = true; result = nil; applyResults = [:]; info = nil; batchProgress = ""; diagnostic = nil
            let started = Date()
            task = Task { @MainActor in
                defer { working = false; task = nil; batchProgress = "" }
                var currentBatch = 0
                var totalBatches = 0
                do {
                    let response = try await client.recommendationsBatched(for: request.context, responseLanguage: AppLanguage.usesChinese ? "Chinese" : "English") { current, total in
                        currentBatch = current; totalBatches = total
                        Task { @MainActor in batchProgress = L("正在分析 \(current) / \(total)…", "Analyzing \(current) / \(total)…") }
                    }
                    try Task.checkCancellation()
                    result = response; lastRequest = request
                    selectedResults = Set(response.recommendations.filter { recommendation in
                        guard let snapshot = request.snapshots[recommendation.fileExtension], !snapshot.unregisteredChoices.contains(recommendation.candidateID) else { return false }
                        return snapshot.currentURL?.standardizedFileURL != snapshot.choices[recommendation.candidateID]?.standardizedFileURL
                    }.map(\.fileExtension))
                } catch {
                    let batch = currentBatch > 0 ? L("失败批次：\(currentBatch) / \(totalBatches)", "Failed batch: \(currentBatch) / \(totalBatches)") : nil
                    diagnostic = diagnosticMessage(operation: L("生成推荐", "Generate recommendations"), config: request.config, started: started, error: error, batch: batch)
                }
            }
        } catch { self.error = error.localizedDescription }
    }
    private func resultsSection(_ result: AIResult, request: PreparedRequest) -> some View {
        section("3", title: L("检查建议", "Review suggestions"), subtitle: L("建议不会自动执行。选中需要的项目后，再点击应用。", "Suggestions are not applied automatically. Select items and click Apply.")) {
            if !result.recommendations.isEmpty {
                Text(L("AI 建议 \(result.recommendations.count) 种类型，已选择 \(selectedResults.count) 种", "AI suggested \(result.recommendations.count) types; \(selectedResults.count) selected")).font(.caption).foregroundStyle(.secondary)
            }
            if result.recommendations.isEmpty { Text(L("助理没有提出变更建议。你可以调整描述或选择的类型后重试。", "No changes suggested. Try adjusting your description or selected file types.")) .font(.callout).foregroundStyle(.secondary) }
            ForEach(result.recommendations) { rec in
                let snapshot = request.snapshots[rec.fileExtension]
                let target = snapshot?.choices[rec.candidateID]
                HStack(alignment: .top, spacing: 10) {
                    Toggle("", isOn: Binding(get: { selectedResults.contains(rec.fileExtension) }, set: { if $0 { selectedResults.insert(rec.fileExtension) } else { selectedResults.remove(rec.fileExtension) } })).labelsHidden().toggleStyle(.checkbox).disabled(working || applyResults[rec.fileExtension] != nil)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(".\(rec.fileExtension)  \(snapshot?.file.appName ?? L("未设置", "Not set"))  →  \(target.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? L("未知应用", "Unknown app"))").font(.system(size: 12, weight: .semibold))
                        if snapshot?.unregisteredChoices.contains(rec.candidateID) == true {
                            Text(L("系统未声明支持 · 请确认应用确实能打开", "Not declared to macOS · confirm the app supports it")).font(.caption.weight(.medium)).foregroundStyle(.orange)
                        }
                        Text(rec.reason).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        if let status = applyResults[rec.fileExtension] { Text(status).font(.caption).foregroundStyle(.blue) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.padding(.vertical, 5)
                Divider()
            }
            ForEach(Array(result.notes.enumerated()), id: \.offset) { _, note in Text(note).font(.caption).foregroundStyle(.secondary) }
            Text(L("系统未声明支持的建议默认不勾选；多个扩展名可能共享系统文件类型。", "Undeclared suggestions are unchecked by default; extensions may share a system type.")) .font(.caption).foregroundStyle(.secondary)
            if result.recommendations.contains(where: { request.snapshots[$0.fileExtension]?.unregisteredChoices.contains($0.candidateID) == true && applyResults[$0.fileExtension] == nil }) {
                Button(L("选中所有未声明建议", "Select all undeclared suggestions")) {
                    for rec in result.recommendations where request.snapshots[rec.fileExtension]?.unregisteredChoices.contains(rec.candidateID) == true && applyResults[rec.fileExtension] == nil {
                        selectedResults.insert(rec.fileExtension)
                    }
                }.disabled(working)
            }
            HStack {
                Button(L("应用选中的建议", "Apply selected suggestions")) { applySelected(result, request: request) }.buttonStyle(.borderedProminent).disabled(working || selectedResults.isEmpty)
                if !applied.isEmpty { Button(L("尝试恢复本次更改", "Try to restore changes")) { undo() }.disabled(working) }
            }
        }
    }
    private func applySelected(_ result: AIResult, request: PreparedRequest) {
        let chosen = result.recommendations.filter { selectedResults.contains($0.fileExtension) && applyResults[$0.fileExtension] == nil }
        var proposals: [ChangeProposal] = []
        for rec in chosen {
            guard let snapshot = request.snapshots[rec.fileExtension], let target = snapshot.choices[rec.candidateID] else { error = L("无效建议", "Invalid suggestion"); return }
            proposals.append(ChangeProposal(fileExtension: rec.fileExtension, typeID: snapshot.typeID, target: target.standardizedFileURL.path, current: snapshot.currentURL?.standardizedFileURL.path))
        }
        let groups: [[AIRecommendation]]
        do {
            let byExtension = Dictionary(uniqueKeysWithValues: chosen.map { ($0.fileExtension, $0) })
            groups = try ChangeGrouping.group(proposals).map { $0.compactMap { byExtension[$0] } }
        } catch ChangeGroupingError.conflictingTargets {
            error = L("同一系统类型被选为不同应用，请调整选择。", "The same system type has conflicting app choices."); return
        } catch {
            self.error = L("系统设置在分析期间发生变化，请重新获取建议。", "A system setting changed during analysis. Get new suggestions."); return
        }
        working = true; info = nil
        task = Task { @MainActor in
            defer { working = false; task = nil }
            for group in groups {
                if Task.isCancelled { info = L("已停止；已完成的更改保留，可尝试恢复。", "Stopped. Completed changes remain and can be restored where possible."); break }
                guard let rec = group.first, let snapshot = request.snapshots[rec.fileExtension], let target = snapshot.choices[rec.candidateID] else { break }
                let unregistered = snapshot.unregisteredChoices.contains(rec.candidateID)
                let failure = await change(snapshot: snapshot, target: target, expected: snapshot.currentURL, allowUnregistered: unregistered)
                if let failure { for item in group { applyResults[item.fileExtension] = failure }; info = L("已停止后续操作，请检查结果。", "Remaining changes were stopped. Review the results."); break }
                let aliases = group.map(\.fileExtension)
                applied.append(AppliedChange(id: rec.fileExtension, snapshot: snapshot, old: snapshot.currentURL, new: target, aliases: aliases))
                for item in group { applyResults[item.fileExtension] = L("已应用", "Applied"); selectedResults.remove(item.fileExtension) }
            }
            store.reload()
        }
    }
    private func change(snapshot: LocalTypeSnapshot, target: URL, expected: URL?, allowUnregistered: Bool = false) async -> String? {
        let type = UTType(filenameExtension: snapshot.file.ext)
        let current = type.flatMap { NSWorkspace.shared.urlForApplication(toOpen: $0) }
        let candidates = Set(type.map { NSWorkspace.shared.urlsForApplications(toOpen: $0).map { $0.standardizedFileURL.path } } ?? [])
        let decision = ChangeGuard.evaluate(expectedType: snapshot.typeID, actualType: type?.identifier, expectedCurrent: expected?.standardizedFileURL.path, actualCurrent: current?.standardizedFileURL.path, target: target.standardizedFileURL.path, candidates: candidates, targetExists: FileManager.default.fileExists(atPath: target.path), allowUnregistered: allowUnregistered)
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
                guard let old = changeRecord.old else { for ext in changeRecord.aliases { applyResults[ext] = L("无法恢复到无默认应用", "Cannot restore an unset default") }; remaining.append(changeRecord); continue }
                if let failure = await change(snapshot: changeRecord.snapshot, target: old, expected: changeRecord.new) { for ext in changeRecord.aliases { applyResults[ext] = L("恢复失败：\(failure)", "Restore failed: \(failure)") }; remaining.append(changeRecord) }
                else { for ext in changeRecord.aliases { applyResults[ext] = L("已恢复", "Restored") } }
            }
            applied = remaining.reversed()
            info = remaining.isEmpty ? L("已恢复可恢复的更改。", "Restorable changes have been restored.") : L("部分项目无法恢复，请查看具体结果。", "Some changes could not be restored. Review the results.")
        }
    }
}
