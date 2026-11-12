import Foundation
import AppKit
import UniformTypeIdentifiers
import OpenKindCore

struct FileAssociation: Identifiable {
    let ext: String
    let type: UTType?
    let appURL: URL?
    var id: String { ext }
    var category: FileCategory { FileCatalog.category(for: ext) }
    var appName: String { appURL.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? L("未设置", "Not set") }
    var detail: String { type == nil ? L("系统未识别此类型", "Type not recognized by macOS") : (type?.localizedDescription ?? L("\(ext.uppercased()) 文件", "\(ext.uppercased()) file")) }
}

@MainActor final class AssociationStore: ObservableObject {
    @Published private(set) var items: [FileAssociation] = []
    @Published var isApplying = false
    @Published var errorMessage: String?
    @Published var notice: String?
    private let customKey = "customExtensions"

    func reload() {
        let custom = UserDefaults.standard.stringArray(forKey: customKey) ?? []
        items = FileCatalog.all(custom: custom).map { ext in
            let type = UTType(filenameExtension: ext)
            return FileAssociation(ext: ext, type: type, appURL: type.flatMap { NSWorkspace.shared.urlForApplication(toOpen: $0) })
        }
    }
    @discardableResult func add(_ value: String) -> String? {
        guard let ext = FileCatalog.normalize(value) else { errorMessage = L("请输入有效的文件扩展名，例如 docx 或 7z。", "Enter a valid file extension, such as docx or 7z."); return nil }
        var custom = UserDefaults.standard.stringArray(forKey: customKey) ?? []
        if !FileCatalog.builtIn.contains(ext) && !custom.contains(ext) {
            custom.append(ext); UserDefaults.standard.set(custom, forKey: customKey)
        }
        reload()
        return ext
    }
    func candidates(for item: FileAssociation) -> [URL] {
        guard let type = item.type else { return [] }
        var urls = NSWorkspace.shared.urlsForApplications(toOpen: type)
        if let current = item.appURL, !urls.contains(current) { urls.insert(current, at: 0) }
        var seen = Set<String>()
        return urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }
    func apply(_ app: URL, to item: FileAssociation) {
        guard let type = item.type else { errorMessage = L("系统尚未识别此文件类型。请先安装支持此格式的应用。", "macOS does not recognize this type. Install a compatible app first."); return }
        isApplying = true
        NSWorkspace.shared.setDefaultApplication(at: app, toOpen: type) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                self.isApplying = false
                self.reload()
                if let error { self.errorMessage = L("设置失败：\(error.localizedDescription)", "Could not update the default: \(error.localizedDescription)"); return }
                let actual = self.items.first { $0.ext == item.ext }?.appURL
                if actual?.standardizedFileURL != app.standardizedFileURL {
                    self.errorMessage = L("系统没有保存此设置。请确认应用支持 .\(item.ext)，并留意系统确认提示。", "macOS did not save this setting. Check that the app supports .\(item.ext) and look for a system prompt.")
                } else {
                    self.notice = L(".\(item.ext) 的默认应用已更新", "Default app for .\(item.ext) updated")
                }
            }
        }
    }
}
