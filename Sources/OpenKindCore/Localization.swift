import Foundation

public enum AppLanguage: String, CaseIterable {
    case system, simplifiedChinese = "zh-Hans", english = "en"
    public static let preferenceKey = "openkind.language"
    public static var selected: AppLanguage { UserDefaults.standard.string(forKey: preferenceKey).flatMap(Self.init(rawValue:)) ?? .system }
    public static func usesChinese(_ selection: AppLanguage, preferredLanguages: [String]) -> Bool {
        switch selection {
        case .simplifiedChinese: return true
        case .english: return false
        case .system: return preferredLanguages.first?.lowercased().hasPrefix("zh") ?? false
        }
    }
    public static var usesChinese: Bool { usesChinese(selected, preferredLanguages: Locale.preferredLanguages) }
    public static var locale: Locale {
        switch selected {
        case .system: return .autoupdatingCurrent
        case .simplifiedChinese: return Locale(identifier: "zh-Hans")
        case .english: return Locale(identifier: "en")
        }
    }
}
public func L(_ chinese: String, _ english: String) -> String { AppLanguage.usesChinese ? chinese : english }
