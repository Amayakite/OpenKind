import SwiftUI
import Security
import OpenKindCore

private enum KeychainVault {
    static let service = "local.default-app-manager.ai"
    static func account(_ config: ProviderConfiguration) throws -> String { "\(config.mode.rawValue)|\(try config.endpoint("").absoluteString)" }
    static func read(_ config: ProviderConfiguration) throws -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: try account(config), kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else { throw SettingsError.keychain(status) }
        return value
    }
    static func save(_ key: String, config: ProviderConfiguration) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: try account(config)]
        let data = Data(key.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var new = query; new[kSecValueData as String] = data
            let addStatus = SecItemAdd(new as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw SettingsError.keychain(addStatus) }
        } else if status != errSecSuccess { throw SettingsError.keychain(status) }
    }
    static func remove(_ config: ProviderConfiguration) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: try account(config)]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SettingsError.keychain(status) }
    }
}
private enum SettingsError: LocalizedError {
    case keychain(OSStatus)
    var errorDescription: String? { switch self { case .keychain(let code): return "无法访问钥匙串（错误代码 \(code)）。请检查钥匙串权限。" } }
}

@MainActor final class AISettingsStore: ObservableObject {
    @Published var config: ProviderConfiguration
    @Published var keyInput = ""
    @Published var models: [String] = []
    @Published var isLoading = false
    @Published var status: String?
    @Published var error: String?
    private let defaults = UserDefaults.standard
    init() {
        let savedMode = UserDefaults.standard.string(forKey: "ai.provider.mode").flatMap(APIMode.init(rawValue:)) ?? .openAI
        config = Self.load(savedMode)
    }
    private static func load(_ mode: APIMode) -> ProviderConfiguration {
        let key = "ai.config.\(mode.rawValue)"
        if let data = UserDefaults.standard.data(forKey: key), let config = try? JSONDecoder().decode(ProviderConfiguration.self, from: data) { return config }
        return mode == .openAI ? .openAIDefault : .compatibleDefault
    }
    func switchMode(_ mode: APIMode) { config = Self.load(mode); keyInput = ""; models = []; status = nil; error = nil }
    func endpointChanged() { keyInput = ""; models = []; status = nil }
    func client() throws -> AIClient {
        _ = try config.endpoint("models")
        let key = keyInput.isEmpty ? try KeychainVault.read(config) ?? "" : keyInput
        return AIClient(config: config, key: key)
    }
    func save() {
        do {
            _ = try config.endpoint("models")
            if !keyInput.isEmpty { try KeychainVault.save(keyInput, config: config); keyInput = "" }
            defaults.set(try JSONEncoder().encode(config), forKey: "ai.config.\(config.mode.rawValue)")
            defaults.set(config.mode.rawValue, forKey: "ai.provider.mode")
            status = "设置已保存。密钥按服务地址保存在钥匙串。"
        } catch { self.error = error.localizedDescription }
    }
    func deleteKey() {
        do { try KeychainVault.remove(config); keyInput = ""; status = "已删除当前地址的密钥。" }
        catch { self.error = error.localizedDescription }
    }
    func fetchModels() async {
        guard !isLoading else { return }
        do {
            let client = try client(); let submittedConfig = config
            isLoading = true; defer { isLoading = false }
            let fetched = try await client.listModels()
            guard config == submittedConfig else { return }
            models = fetched
            status = fetched.isEmpty ? "服务没有返回模型，可手动输入模型 ID。" : "已获取 \(fetched.count) 个模型；是否可用于文字生成取决于服务商。"
        } catch { self.error = error.localizedDescription }
    }
}

struct AISettingsView: View {
    @ObservedObject var settings: AISettingsStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("AI 服务设置").font(.system(size: 22, weight: .bold))
            Text("选择 OpenAI 或兼容服务。密钥仅保存在此 Mac 的钥匙串中。") .font(.callout).foregroundStyle(.secondary)
            Form {
                Picker("接口类型", selection: Binding(get: { settings.config.mode }, set: { settings.switchMode($0) })) {
                    ForEach(APIMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                TextField("服务基础地址", text: $settings.config.baseURL)
                    .onChange(of: settings.config.baseURL) { _, _ in settings.endpointChanged() }
                Text("例如 https://api.openai.com/v1；本机 HTTP 地址也可使用。")
                    .font(.caption).foregroundStyle(.secondary)
                SecureField("API Key（留空使用已保存的密钥）", text: $settings.keyInput)
                HStack {
                    Button("删除此地址的密钥") { settings.deleteKey() }
                    Text("本地代理可不填密钥").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    TextField("模型 ID", text: $settings.config.model)
                    Button(settings.isLoading ? "获取中…" : "获取模型") { Task { await settings.fetchModels() } }.disabled(settings.isLoading)
                }
                if !settings.models.isEmpty {
                    Picker("从列表选择", selection: Binding(get: { settings.models.contains(settings.config.model) ? settings.config.model : "" }, set: { if !$0.isEmpty { settings.config.model = $0 } })) {
                        Text("选择模型…").tag("")
                        ForEach(settings.models, id: \.self) { Text($0).tag($0) }
                    }
                }
            }.formStyle(.grouped).frame(height: 340)
            Text("获取模型会连接上述服务，但不会发送文件关联信息。模型列表不代表每个模型都支持文字推荐。")
                .font(.caption).foregroundStyle(.secondary)
            if let status = settings.status { Text(status).font(.caption).foregroundStyle(.secondary) }
            HStack { Spacer(); Button("关闭") { dismiss() }; Button("保存") { settings.save() }.keyboardShortcut(.defaultAction) }
        }.padding(25).frame(width: 580)
        .alert("AI 设置", isPresented: Binding(get: { settings.error != nil }, set: { if !$0 { settings.error = nil } })) { Button("好") { settings.error = nil } } message: { Text(settings.error ?? "") }
    }
}
