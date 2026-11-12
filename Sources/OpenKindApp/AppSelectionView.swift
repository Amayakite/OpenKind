import SwiftUI
import UniformTypeIdentifiers
import OpenKindCore

struct AppSelectionView: View {
    @ObservedObject var catalog: ApplicationCatalog
    @Binding var selection: DiscoveredApplication?
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    var filtered: [DiscoveredApplication] {
        catalog.apps.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(L("选择应用", "Choose an app")).font(.title2.bold())
            Text(L("列出常见应用程序文件夹中的应用，包括尚未关联文件类型的应用。", "Apps from common Applications folders are shown, including apps without defaults.")).font(.callout).foregroundStyle(.secondary)
            TextField(L("搜索已安装应用", "Search installed apps"), text: $search).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filtered) { app in
                        Button {
                            selection = app; dismiss()
                        } label: {
                            HStack(spacing: 10) {
                                ApplicationIcon(url: app.url, size: 32)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(app.name).font(.system(size: 13, weight: .medium))
                                    if !app.hasDocumentDeclarations { Text(L("未声明文件类型", "No declared file types")).font(.caption).foregroundStyle(.secondary) }
                                    if catalog.apps.filter({ $0.name == app.name }).count > 1 { Text(app.url.deletingLastPathComponent().path).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                                }
                                Spacer()
                                if selection?.id == app.id { Image(systemName: "checkmark").foregroundStyle(.blue) }
                            }.padding(8).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Divider()
                    }
                    if filtered.isEmpty { Text(catalog.loading ? L("正在查找应用…", "Finding apps…") : L("没有找到应用。", "No apps found.")).foregroundStyle(.secondary).padding() }
                }
            }.frame(height: 300)
            HStack {
                Text(L("未包含所有磁盘或非常见安装位置。", "Apps in uncommon locations or on other disks may be missing.")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(L("选择其他应用…", "Choose another app…")) {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.application]
                    panel.directoryURL = URL(fileURLWithPath: "/Applications")
                    panel.canChooseDirectories = false
                    if panel.runModal() == .OK, let url = panel.url {
                        catalog.include(url); selection = DiscoveredApplication(url: url); dismiss()
                    }
                }
                Button(L("关闭", "Close")) { dismiss() }
            }
        }.padding(24).frame(width: 540)
    }
}
