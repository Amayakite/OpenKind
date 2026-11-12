import Foundation

public struct ProviderProfile: Codable, Identifiable, Equatable {
    public let id: UUID
    public var name: String
    public var config: ProviderConfiguration
    // Previous releases keyed secrets by mode and endpoint. Keep that mapping for migrated profiles.
    public var legacyCredentialAccount: String?
    public init(id: UUID = UUID(), name: String, config: ProviderConfiguration, legacyCredentialAccount: String? = nil) {
        self.id = id; self.name = name; self.config = config; self.legacyCredentialAccount = legacyCredentialAccount
    }
    public func credentialAccount() throws -> String {
        let endpoint = try config.endpoint("").absoluteString
        let legacy = "\(config.mode.rawValue)|\(endpoint)"
        return legacyCredentialAccount == legacy ? legacy : "profile:\(id.uuidString)|\(config.mode.rawValue)|\(endpoint)"
    }
    public static func openAI() -> Self { .init(name: "OpenAI", config: .openAIDefault) }
    public static func deepSeek() -> Self { .init(name: "DeepSeek", config: .init(mode: .compatible, baseURL: "https://api.deepseek.com", model: "")) }
    public static func custom() -> Self { .init(name: L("自定义", "Custom"), config: .compatibleDefault) }
}

public struct ProviderRegistry: Codable, Equatable {
    public var profiles: [ProviderProfile]
    public var activeID: UUID?
    public init(profiles: [ProviderProfile], activeID: UUID?) { self.profiles = profiles; self.activeID = activeID }
    public static func initial(legacy: [ProviderConfiguration], activeMode: APIMode?) -> Self {
        var profiles = legacy.map { config -> ProviderProfile in
            let name = config.mode == .openAI ? "OpenAI" : "Custom (migrated)"
            let account = (try? config.endpoint("").absoluteString).map { "\(config.mode.rawValue)|\($0)" }
            return ProviderProfile(name: name, config: config, legacyCredentialAccount: account)
        }
        if !profiles.contains(where: { $0.config.mode == .openAI && $0.config.baseURL == ProviderConfiguration.openAIDefault.baseURL }) { profiles.insert(.openAI(), at: 0) }
        if !profiles.contains(where: { $0.config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == "https://api.deepseek.com" }) { profiles.append(.deepSeek()) }
        let active = activeMode.flatMap { mode in profiles.first { $0.legacyCredentialAccount != nil && $0.config.mode == mode }?.id } ?? profiles.first?.id
        return Self(profiles: profiles, activeID: active)
    }
}
