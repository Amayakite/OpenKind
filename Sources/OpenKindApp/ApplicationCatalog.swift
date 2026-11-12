import Foundation
import AppKit
import OpenKindCore
import UniformTypeIdentifiers

@MainActor final class ApplicationCatalog: ObservableObject {
    @Published private(set) var apps: [DiscoveredApplication] = []
    @Published private(set) var loading = false
    private let manualKey = "additionalApplicationPaths"
    private var manualURLs: [URL] { (UserDefaults.standard.stringArray(forKey: manualKey) ?? []).map { URL(fileURLWithPath: $0) } }
    func include(_ url: URL) {
        let item = DiscoveredApplication(url: url)
        var paths = UserDefaults.standard.stringArray(forKey: manualKey) ?? []
        if !paths.contains(item.url.path) { paths.append(item.url.path); UserDefaults.standard.set(paths, forKey: manualKey) }
        guard !apps.contains(where: { $0.id == item.id }) else { return }
        apps.append(item)
        apps.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    func reload(extra: [URL] = []) {
        guard !loading else { return }
        loading = true
        let initialExtra = extra + manualURLs
        Task {
            var discovered = await Task.detached(priority: .userInitiated) {
                ApplicationDiscovery.scan(roots: ApplicationDiscovery.standardRoots, extra: initialExtra)
            }.value
            // Keep apps manually added while the background scan was still running.
            for url in manualURLs where FileManager.default.fileExists(atPath: url.path) {
                let app = DiscoveredApplication(url: url)
                if !discovered.contains(where: { $0.id == app.id }) { discovered.append(app) }
            }
            apps = discovered.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }; loading = false
        }
    }
}

extension AssociationStore {
    // Declared extensions complement the built-in list; wildcard and multi-part names are excluded.
    func availableTypes(for app: URL) -> [FileAssociation] {
        let documents = Bundle(url: app)?.object(forInfoDictionaryKey: "CFBundleDocumentTypes") as? [[String: Any]] ?? []
        var extensions = Set(items.map(\.ext))
        for document in documents {
            for ext in document["CFBundleTypeExtensions"] as? [String] ?? [] {
                if let valid = FileCatalog.normalize(ext) { extensions.insert(valid) }
            }
            for identifier in document["LSItemContentTypes"] as? [String] ?? [] {
                guard let type = UTType(identifier) else { continue }
                for ext in type.tags[.filenameExtension] ?? [] {
                    if let valid = FileCatalog.normalize(ext) { extensions.insert(valid) }
                }
            }
        }
        let existing = Dictionary(uniqueKeysWithValues: items.map { ($0.ext, $0) })
        let builtInFirst = items.map(\.ext) + extensions.subtracting(Set(items.map(\.ext))).sorted()
        return builtInFirst.map { ext in
            if let item = existing[ext] { return item }
            let type = UTType(filenameExtension: ext)
            return FileAssociation(ext: ext, type: type, appURL: type.flatMap { NSWorkspace.shared.urlForApplication(toOpen: $0) })
        }
    }
}
