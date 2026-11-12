import Foundation
import OpenKindCore

func runDiscoveryChecks() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("openkind-discovery-\(UUID().uuidString)", isDirectory: true)
    defer { try? fm.removeItem(at: root) }
    func createApp(_ relative: String, docs: Bool) throws {
        let bundle = root.appendingPathComponent(relative, isDirectory: true)
        let contents = bundle.appendingPathComponent("Contents", isDirectory: true)
        try fm.createDirectory(at: contents, withIntermediateDirectories: true)
        var info: [String: Any] = ["CFBundleName": bundle.deletingPathExtension().lastPathComponent, "CFBundleIdentifier": "test.\(UUID().uuidString)", "CFBundlePackageType": "APPL"]
        if docs { info["CFBundleDocumentTypes"] = [["CFBundleTypeName": "Text", "CFBundleTypeExtensions": ["txt"]]] }
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
    }
    try createApp("WithoutDefaults.app", docs: false)
    try createApp("Nested/Editor.app", docs: true)
    try createApp(".hidden/Hidden.app", docs: true)
    try createApp("WithoutDefaults.app/Contents/Helpers/Child.app", docs: true)
    let apps = ApplicationDiscovery.scan(roots: [root])
    func ensure(_ condition: @autoclosure () -> Bool, _ text: String) { if !condition() { fputs("FAIL: \(text)\n", stderr); exit(1) } }
    ensure(apps.count == 2, "include regular apps; exclude hidden and nested app packages")
    ensure(apps.contains { $0.url.lastPathComponent == "WithoutDefaults.app" && !$0.hasDocumentDeclarations }, "include app without document declarations")
    ensure(apps.contains { $0.url.lastPathComponent == "Editor.app" && $0.hasDocumentDeclarations }, "include nested installed app with document declarations")
    let outside = root.appendingPathComponent("Nested/Editor.app")
    let extras = ApplicationDiscovery.scan(roots: [], extra: [outside, outside])
    ensure(extras.count == 1 && extras[0].url == outside.standardizedFileURL, "include and deduplicate an explicitly selected app")
    print("Application discovery checks passed")
}
