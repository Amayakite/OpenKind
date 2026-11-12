import SwiftUI
import AppKit
import OpenKindCore

private enum Page { case types, apps, assistant, settings }
private enum Design {
    static let blue = Color(red: 0.22, green: 0.39, blue: 0.92)
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let line = Color.primary.opacity(0.07)
}

struct MainView: View {
    @StateObject private var store = AssociationStore()
    @StateObject private var appCatalog = ApplicationCatalog()
    @StateObject private var aiSettings = AISettingsStore()
    @AppStorage(AppLanguage.preferenceKey) private var language = AppLanguage.system.rawValue
    @State private var page: Page = .types
    @State private var category: FileCategory?
    @State private var query = ""
    @State private var selectedApp: URL?
    @State private var assistantApp: DiscoveredApplication?
    @State private var selectedType: FileAssociation?
    @State private var showAdd = false
    @State private var newExtension = ""
    @State private var addError: String?

    private var filtered: [FileAssociation] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return store.items.filter { item in
            (category == nil || item.category == category) &&
            (search.isEmpty || item.ext.contains(search.trimmingCharacters(in: CharacterSet(charactersIn: "."))) || item.appName.lowercased().contains(search) || item.detail.lowercased().contains(search))
        }
    }
    private var apps: [URL] {
        appCatalog.apps.map(\.url)
    }
    private var filteredApps: [URL] {
        query.isEmpty ? apps : apps.filter { appName($0).localizedCaseInsensitiveContains(query) }
    }
    private func appName(_ app: URL) -> String { FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "") }
    private func associated(_ app: URL) -> [FileAssociation] { store.items.filter { $0.appURL?.standardizedFileURL == app.standardizedFileURL } }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Design.line).frame(width: 1)
            VStack(alignment: .leading, spacing: 0) {
                if page == .settings {
                    GeneralSettingsView(settings: aiSettings)
                } else if page == .assistant {
                    AssistantView(store: store, settings: aiSettings, appCatalog: appCatalog, selectedApp: $assistantApp)
                } else {
                    header
                    if page == .types { typeContent } else { appContent }
                    footer
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Design.canvas)
        }
        .frame(minWidth: 940, minHeight: 620)
        .environment(\.locale, language == "system" ? .autoupdatingCurrent : Locale(identifier: language))
        .onAppear { store.reload(); appCatalog.reload(extra: store.items.compactMap(\.appURL)) }
        .sheet(item: $selectedType) { item in AppPicker(item: item, store: store) }
        .sheet(isPresented: $showAdd) { addSheet }
        .alert(L("无法完成操作", "Could not complete the action"), isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button(L("好", "OK")) { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                BrandMark(size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("OpenKind").font(.system(size: 16, weight: .bold, design: .rounded))
                    Text(L("默认应用管理", "Default app manager")).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 20).padding(.top, 35).padding(.bottom, 35)
            Text(L("管理方式", "Manage")).font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary).padding(.horizontal, 23).padding(.bottom, 9)
            sidebarButton(L("文件类型", "File types"), subtitle: L("按扩展名管理", "Manage by extension"), symbol: "doc.on.doc", selected: page == .types) { page = .types; query = "" }
            sidebarButton(L("应用", "Apps"), subtitle: L("查看应用关联", "View app associations"), symbol: "square.stack.3d.up", selected: page == .apps) { page = .apps; query = ""; category = nil }
            sidebarButton(L("AI 助理", "AI assistant"), subtitle: L("获取配置建议", "Get recommendations"), symbol: "sparkles", selected: page == .assistant) { page = .assistant; query = ""; category = nil }
            Spacer()
            sidebarButton(L("设置", "Settings"), subtitle: L("语言与服务", "Language and providers"), symbol: "gearshape", selected: page == .settings) { page = .settings }
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "person.crop.circle").font(.system(size: 16)).foregroundStyle(Design.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("当前用户", "Current user")).font(.system(size: 12, weight: .semibold))
                    Text(L("设置保存在这台 Mac 上", "Settings stay on this Mac")).font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                .padding(14).padding(.bottom, 8)
        }
        .frame(width: 210).frame(maxHeight: .infinity).background(Color(nsColor: .controlBackgroundColor))
    }
    private func sidebarButton(_ title: String, subtitle: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 15, weight: .medium)).frame(width: 20).foregroundStyle(selected ? Design.blue : .secondary)
                VStack(alignment: .leading, spacing: 3) { Text(title).font(.system(size: 13, weight: selected ? .semibold : .medium)); Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary) }
                Spacer()
            }.padding(.horizontal, 12).padding(.vertical, 10).contentShape(Rectangle())
                .background(selected ? Design.blue.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).padding(.horizontal, 12).padding(.bottom, 3)
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(page == .types ? L("文件类型", "File types") : L("应用关联", "App associations")).font(.system(size: 28, weight: .bold))
                    Text(page == .types ? L("为每种文件选择顺手的打开方式。", "Choose how each file type opens.") : L("查看常见位置中的已安装应用及其默认关联。", "Browse installed apps in common locations and their defaults."))
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { store.reload(); appCatalog.reload(extra: store.items.compactMap(\.appURL)); store.notice = L("已读取最新设置", "Settings refreshed") } label: { Image(systemName: "arrow.clockwise").frame(width: 30, height: 28) }
                    .help(L("刷新默认应用", "Refresh defaults"))
                if page == .types {
                    Button { newExtension = ""; addError = nil; showAdd = true } label: { Label(L("添加类型", "Add type"), systemImage: "plus").padding(.vertical, 2) }
                        .buttonStyle(.borderedProminent).tint(Design.blue)
                }
            }.padding(.top, 38).padding(.bottom, 23)
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(page == .types ? L("搜索文件扩展名或应用，如 .docx", "Search extensions or apps, e.g. .docx") : L("搜索应用名称", "Search apps"), text: $query).textFieldStyle(.plain)
                if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }.buttonStyle(.plain) }
                Text(L("搜索", "Search")).font(.system(size: 10)).foregroundStyle(.tertiary).padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 4))
            }.padding(.horizontal, 12).frame(height: 38)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Design.line))
        }.padding(.horizontal, 32)
    }
    private var typeContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    categoryChip(nil)
                    ForEach(FileCategory.allCases) { categoryChip($0) }
                }
            }.padding(.top, 17).padding(.bottom, 18)
            HStack {
                Text(category?.localizedName ?? L("所有文件类型", "All file types")).font(.system(size: 14, weight: .semibold))
                Text("\(filtered.count)").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 7).padding(.vertical, 3).background(Color.primary.opacity(0.05), in: Capsule())
                Spacer()
                Text(L("选择一项来更改", "Select an item to change")).font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(.bottom, 11)
            VStack(spacing: 0) {
                HStack {
                    Text(L("文件类型", "File types")).frame(maxWidth: .infinity, alignment: .leading)
                    Text(L("默认应用", "Default app")).frame(width: 230, alignment: .leading)
                    Text("").frame(width: 16)
                }.font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).padding(.horizontal, 18).frame(height: 35)
                    .background(Color.primary.opacity(0.025))
                Divider()
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered) { item in AssociationRow(item: item) { selectedType = item }.disabled(store.isApplying) }
                        if filtered.isEmpty { emptyState(L("没有找到文件类型", "No file types found"), detail: L("换个关键词，或添加自定义扩展名。", "Try another search or add a custom extension."), symbol: "doc.text.magnifyingglass") }
                    }
                }
            }.background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                .clipShape(RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Design.line))
        }.padding(.horizontal, 32).padding(.bottom, 14).frame(maxHeight: .infinity)
    }
    private func categoryChip(_ item: FileCategory?) -> some View {
        let active = category == item
        return Button { category = item } label: {
            Text(item?.localizedName ?? L("全部", "All")).font(.system(size: 11, weight: active ? .semibold : .medium))
                .foregroundStyle(active ? Design.blue : Color.secondary)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(active ? Design.blue.opacity(0.11) : Color.primary.opacity(0.04), in: Capsule())
        }.buttonStyle(.plain)
    }
    private var appContent: some View {
        HStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(filteredApps, id: \.self) { app in
                        Button { selectedApp = app } label: {
                            HStack(spacing: 10) {
                                ApplicationIcon(url: app, size: 34)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(appName(app)).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                    Text(associated(app).isEmpty ? L("暂无列表内默认关联", "No defaults in this list") : L("\(associated(app).count) 种默认类型", "\(associated(app).count) defaults")).font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                            }.padding(9).contentShape(Rectangle()).background(selectedApp == app ? Design.blue.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 9))
                        }.buttonStyle(.plain)
                    }
                    if filteredApps.isEmpty { Text(appCatalog.loading ? L("正在查找应用…", "Finding apps…") : L("没有找到应用", "No apps found")).font(.caption).foregroundStyle(.secondary).padding(22) }
                }.padding(9)
            }.frame(width: 250)
            Rectangle().fill(Design.line).frame(width: 1)
            if let app = selectedApp {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 12) {
                        ApplicationIcon(url: app, size: 43)
                        VStack(alignment: .leading, spacing: 4) { Text(appName(app)).font(.system(size: 16, weight: .semibold)); Text(L("当前是 \(associated(app).count) 种列表内格式的默认应用", "Default for \(associated(app).count) listed file types")).font(.system(size: 11)).foregroundStyle(.secondary)
                            Text(appCatalog.apps.first(where: { $0.id == app })?.hasDocumentDeclarations == true ? L("应用声明了文件类型", "The app declares document types") : L("未声明文件类型，仍可能支持打开文件", "No document types declared; it may still open files")).font(.system(size: 10)).foregroundStyle(.secondary) }
                        Spacer()
                        Button(L("AI 推荐", "AI suggestions")) {
                            assistantApp = appCatalog.apps.first(where: { $0.id == app }) ?? DiscoveredApplication(url: app)
                            page = .assistant
                        }
                    }.padding(18)
                    Divider()
                    ScrollView { LazyVStack(spacing: 0) {
                        if associated(app).isEmpty { Text(L("该应用当前不是列表中任何类型的默认应用；这不代表它不支持文件。", "This app is not the default for any listed types; it may still support files.")).font(.callout).foregroundStyle(.secondary).padding(24) }
                        ForEach(associated(app)) { item in AssociationRow(item: item, compact: true) { selectedType = item }.disabled(store.isApplying) }
                    } }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                emptyState(L("选择一个应用", "Choose an app"), detail: L("从左侧选择应用，查看它在当前列表中的关联。", "Select an app to view its associations in this list."), symbol: "square.stack.3d.up")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .clipShape(RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Design.line))
            .padding(.horizontal, 32).padding(.top, 20).padding(.bottom, 14).frame(maxHeight: .infinity)
    }
    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: store.notice == nil ? "info.circle" : "checkmark.circle.fill").foregroundStyle(store.notice == nil ? Color.secondary : Color.green)
            Text(store.notice ?? L("列表包含常见格式及你添加的类型，不代表全部系统格式。", "This list includes common and custom types, not every system type."))
            Spacer()
            if store.isApplying { ProgressView().controlSize(.small); Text(L("正在更新…", "Updating…")) }
        }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 33).padding(.bottom, 18)
    }
    private var addSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("添加文件类型", "Add file type")).font(.system(size: 20, weight: .bold))
            Text(L("输入扩展名，OpenKind 会在列表中显示它的默认应用。", "Enter an extension to see its default app in OpenKind.")) .font(.system(size: 13)).foregroundStyle(.secondary)
            TextField(L("例如 docx", "e.g. docx"), text: $newExtension).textFieldStyle(.roundedBorder)
            if let addError { Text(addError).font(.caption).foregroundStyle(.red) }
            HStack { Spacer(); Button(L("取消", "Cancel")) { showAdd = false }.keyboardShortcut(.cancelAction)
                Button(L("添加", "Add")) {
                    guard FileCatalog.normalize(newExtension) != nil else { addError = L("请输入有效扩展名，例如 docx 或 7z。", "Enter a valid extension, such as docx or 7z."); return }
                    if let value = store.add(newExtension) { page = .types; category = nil; query = value; showAdd = false }
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(25).frame(width: 410)
    }
}

private func emptyState(_ title: String, detail: String, symbol: String) -> some View {
    VStack(spacing: 9) { Image(systemName: symbol).font(.system(size: 26)).foregroundStyle(.tertiary); Text(title).font(.system(size: 14, weight: .semibold)); Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center) }.frame(maxWidth: .infinity).padding(38)
}

private struct AssociationRow: View {
    let item: FileAssociation
    var compact = false
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9).fill(Design.blue.opacity(0.08))
                    Image(systemName: item.category.symbol).font(.system(size: 15)).foregroundStyle(Design.blue)
                }.frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 4) {
                    Text(".\(item.ext)").font(.system(size: 13, weight: .semibold))
                    Text(item.detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
                if !compact {
                    HStack(spacing: 9) { ApplicationIcon(url: item.appURL, size: 28); Text(item.appName).font(.system(size: 12, weight: .medium)).lineLimit(1); Spacer(minLength: 0) }.frame(width: 230, alignment: .leading)
                }
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary).frame(width: 16)
            }.padding(.horizontal, 18).padding(.vertical, 10).contentShape(Rectangle())
                .background(hover ? Design.blue.opacity(0.035) : .clear)
        }.buttonStyle(.plain).onHover { hover = $0 }
        Divider().padding(.leading, 68)
    }
}
struct ApplicationIcon: View {
    let url: URL?
    var size: CGFloat = 32
    var body: some View {
        Group { if let url { Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().interpolation(.high) }
            else { Image(systemName: "app.dashed").resizable().scaledToFit().foregroundStyle(.secondary).padding(5) } }
            .frame(width: size, height: size)
    }
}
struct BrandMark: View {
    var size: CGFloat
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.25).fill(LinearGradient(colors: [Color(red: 0.35, green: 0.52, blue: 1), Color(red: 0.22, green: 0.30, blue: 0.77)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "square.stack.3d.up.fill").font(.system(size: size * 0.43, weight: .semibold)).foregroundStyle(.white)
        }.frame(width: size, height: size)
    }
}
