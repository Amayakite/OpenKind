import SwiftUI
import AppKit
import UniformTypeIdentifiers
import OpenKindCore

struct AppPicker: View {
    let item: FileAssociation
    @ObservedObject var store: AssociationStore
    @Environment(\.dismiss) private var dismiss
    private var candidates: [URL] { store.candidates(for: item) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 13) {
                ZStack { RoundedRectangle(cornerRadius: 11).fill(Color.accentColor.opacity(0.1)); Image(systemName: "doc.text").font(.system(size: 19)).foregroundStyle(.tint) }.frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 5) {
                    Text(L("选择默认应用", "Choose a default app")).font(.system(size: 20, weight: .bold))
                    Text(L("选择打开 .\(item.ext) 文件的应用", "Choose an app for .\(item.ext) files")).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }.padding(.bottom, 23)
            Text(L("推荐应用", "Suggested apps")).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.bottom, 9)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(candidates, id: \.self) { app in
                        Button { dismiss(); store.apply(app, to: item) } label: {
                            HStack(spacing: 12) {
                                ApplicationIcon(url: app, size: 36)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")).font(.system(size: 13, weight: .semibold))
                                    Text(app.path).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                }
                                Spacer()
                                if item.appURL?.standardizedFileURL == app.standardizedFileURL {
                                    Text(L("当前默认", "Current default")).font(.system(size: 10, weight: .medium)).foregroundStyle(.blue).padding(.horizontal, 8).padding(.vertical, 4).background(Color.blue.opacity(0.09), in: Capsule())
                                } else { Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.tertiary) }
                            }.padding(11).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Divider().padding(.leading, 59)
                    }
                    if candidates.isEmpty { Text(L("系统未找到声明支持此格式的应用。你可以手动选择。 ", "No apps registered for this format. You can choose one manually.")).font(.callout).foregroundStyle(.secondary).padding(20) }
                }
            }.frame(minHeight: 90, maxHeight: 270)
                .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.07)))
            HStack {
                Button(L("选择其他应用…", "Choose another app…")) { chooseOther() }
                Spacer()
                Button(L("取消", "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(.top, 19)
        }.padding(25).frame(width: 520)
    }
    private func chooseOther() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let app = panel.url { dismiss(); store.apply(app, to: item) }
    }
}
