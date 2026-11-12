import Foundation

public struct DiscoveredApplication: Identifiable, Hashable {
    public let url: URL
    public let name: String
    public let bundleIdentifier: String?
    public let hasDocumentDeclarations: Bool
    public var id: URL { url }
    public init(url: URL) {
        self.url = url.standardizedFileURL
        let bundle = Bundle(url: url)
        self.bundleIdentifier = bundle?.bundleIdentifier
        self.name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        self.hasDocumentDeclarations = !(bundle?.object(forInfoDictionaryKey: "CFBundleDocumentTypes") as? [[String: Any]] ?? []).isEmpty
    }
}
public enum ApplicationDiscovery {
    public static var standardRoots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications"), URL(fileURLWithPath: "/System/Applications"), URL(fileURLWithPath: "/System/Volumes/Preboot/Cryptexes/App/System/Applications")]
    }
    public static func scan(roots: [URL], extra: [URL] = []) -> [DiscoveredApplication] {
        let fm = FileManager.default
        var found: [String: URL] = [:]
        func add(_ url: URL) {
            let normalized = url.standardizedFileURL
            guard normalized.pathExtension.lowercased() == "app", fm.fileExists(atPath: normalized.path), Bundle(url: normalized) != nil else { return }
            found[normalized.path] = normalized
        }
        for root in roots {
            guard let iterator = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in iterator {
                if url.pathExtension.lowercased() == "app" { add(url); iterator.skipDescendants() }
            }
        }
        extra.forEach(add)
        return found.values.map(DiscoveredApplication.init).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
