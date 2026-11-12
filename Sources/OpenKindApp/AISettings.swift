import SwiftUI
import Security
import OpenKindCore

private enum KeychainVault {
    static let service = "local.default-app-manager.ai"
    static func query(_ profile: ProviderProfile) throws -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: try profile.credentialAccount()]
    }
    static func read(_ profile: ProviderProfile) throws -> String? {
        var query = try query(profile)
        query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else { throw SettingsError.keychain(status) }
        return value
    }
    static func exists(_ profile: ProviderProfile) throws -> Bool {
        var query = try query(profile)
        query[kSecReturnAttributes as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess else { throw SettingsError.keychain(status) }
        return true
    }
    static func save(_ key: String, profile: ProviderProfile) throws {
        let query = try query(profile); let data = Data(key.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var new = query; new[kSecValueData as String] = data
            let add = SecItemAdd(new as CFDictionary, nil)
            guard add == errSecSuccess else { throw SettingsError.keychain(add) }
        } else if status != errSecSuccess { throw SettingsError.keychain(status) }
    }
    static func remove(_ profile: ProviderProfile) throws {
        let status = SecItemDelete(try query(profile) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SettingsError.keychain(status) }
    }
    static func removeAll(for profile: ProviderProfile) throws {
        let lookup: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                     kSecReturnAttributes as String: true, kSecMatchLimit as String: kSecMatchLimitAll]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecItemNotFound { return }
        guard status == errSecSuccess, let items = result as? [[String: Any]] else { throw SettingsError.keychain(status) }
        let prefix = "profile:\(profile.id.uuidString)|"
        for item in items {
            guard let account = item[kSecAttrAccount as String] as? String,
                  account.hasPrefix(prefix) || account == profile.legacyCredentialAccount else { continue }
            let entry: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
            let deletion = SecItemDelete(entry as CFDictionary)
            guard deletion == errSecSuccess || deletion == errSecItemNotFound else { throw SettingsError.keychain(deletion) }
        }
    }
}
private enum SettingsError: LocalizedError {
    case keychain(OSStatus), invalidName, unsaved, noProfile
    var errorDescription: String? {
        switch self {
        case .keychain(let code): return L("无法访问钥匙串（错误代码 \(code)）。请检查钥匙串权限。", "Unable to access Keychain (error \(code)). Check Keychain permissions.")
        case .invalidName: return L("请为配置输入名称。", "Enter a name for this profile.")
        case .unsaved: return L("请先保存或放弃当前修改。", "Save or discard your changes first.")
        case .noProfile: return L("请先启用一个 AI 服务配置。", "Enable an AI provider profile first.")
        }
    }
}

@MainActor final class AISettingsStore: ObservableObject {
    @Published private(set) var registry: ProviderRegistry
    @Published var draft: ProviderProfile
    @Published var keyInput = ""
    @Published var models: [String] = []
    @Published var isLoading = false
    @Published var status: String?
    @Published var error: String?
    @Published var diagnostic: String?
    @Published var hasStoredKey = false
    private let defaults: UserDefaults
    private let registryKey = "ai.provider.registry.v1"
    var config: ProviderConfiguration { activeProfile?.config ?? .openAIDefault }
    var activeProfile: ProviderProfile? { registry.profiles.first { $0.id == registry.activeID } }
    var isDraftActive: Bool { draft.id == registry.activeID }
    var hasChanges: Bool { registry.profiles.first(where: { $0.id == draft.id }) != draft || !keyInput.isEmpty }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let initial: ProviderRegistry
        if let data = defaults.data(forKey: registryKey), let saved = try? JSONDecoder().decode(ProviderRegistry.self, from: data), !saved.profiles.isEmpty {
            initial = saved
        } else {
            let legacy = APIMode.allCases.compactMap { mode -> ProviderConfiguration? in
                guard let data = defaults.data(forKey: "ai.config.\(mode.rawValue)") else { return nil }
                return try? JSONDecoder().decode(ProviderConfiguration.self, from: data)
            }
            let mode = defaults.string(forKey: "ai.provider.mode").flatMap(APIMode.init(rawValue:))
            initial = ProviderRegistry.initial(legacy: legacy, activeMode: mode)
            if let data = try? JSONEncoder().encode(initial) { defaults.set(data, forKey: registryKey) }
        }
        registry = initial
        draft = initial.profiles.first(where: { $0.id == initial.activeID }) ?? initial.profiles[0]
        refreshKeyStatus()
    }
    private func persist() { if let data = try? JSONEncoder().encode(registry) { defaults.set(data, forKey: registryKey) } }
    func refreshKeyStatus() { hasStoredKey = (try? KeychainVault.exists(draft)) ?? false }
    func endpointChanged() {
        let cleared = !keyInput.isEmpty
        keyInput = ""; models = []; diagnostic = nil
        status = cleared ? L("地址或接口已更改，请重新输入尚未保存的密钥。", "The address or API type changed. Re-enter the unsaved key.") : nil
        refreshKeyStatus()
    }
    func select(_ profile: ProviderProfile) {
        guard profile.id != draft.id else { return }
        guard !hasChanges else { error = SettingsError.unsaved.localizedDescription; return }
        draft = profile; keyInput = ""; models = []; status = nil; diagnostic = nil; refreshKeyStatus()
    }
    func discard() { if let saved = registry.profiles.first(where: { $0.id == draft.id }) { draft = saved }; keyInput = ""; models = []; status = nil; refreshKeyStatus() }
    func add(_ profile: ProviderProfile) {
        guard !hasChanges else { error = SettingsError.unsaved.localizedDescription; return }
        registry.profiles.append(profile); persist(); draft = profile; keyInput = ""; models = []; status = nil; refreshKeyStatus()
    }
    @discardableResult func save() -> Bool {
        do {
            guard !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SettingsError.invalidName }
            _ = try draft.config.endpoint("models")
            if !keyInput.isEmpty { try KeychainVault.save(keyInput, profile: draft); keyInput = "" }
            guard let index = registry.profiles.firstIndex(where: { $0.id == draft.id }) else { throw SettingsError.noProfile }
            registry.profiles[index] = draft; persist(); refreshKeyStatus()
            status = L("配置已保存。", "Profile saved."); return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func activate() {
        guard save() else { return }
        registry.activeID = draft.id; persist(); status = L("已启用此配置。", "Profile enabled.")
    }
    func deleteKey() {
        do { try KeychainVault.remove(draft); keyInput = ""; refreshKeyStatus(); status = L("已删除此配置和地址的密钥。", "API key removed for this profile and address.") }
        catch { self.error = error.localizedDescription }
    }
    func removeProfile() {
        guard registry.profiles.count > 1 else { error = L("至少保留一个配置。", "Keep at least one profile."); return }
        do {
            // Remove only accounts belonging to this profile, including earlier endpoints.
            guard let saved = registry.profiles.first(where: { $0.id == draft.id }) else { throw SettingsError.noProfile }
            try KeychainVault.removeAll(for: saved)
            registry.profiles.removeAll { $0.id == saved.id }
            if registry.activeID == saved.id { registry.activeID = registry.profiles.first?.id }
            persist(); draft = registry.profiles.first!; keyInput = ""; models = []; status = nil; refreshKeyStatus()
        } catch { self.error = error.localizedDescription }
    }
    func client() throws -> AIClient {
        guard let active = activeProfile else { throw SettingsError.noProfile }
        _ = try active.config.endpoint("models")
        return AIClient(config: active.config, key: try KeychainVault.read(active) ?? "")
    }
    func fetchModels() async {
        guard !isLoading else { return }
        let started = Date()
        let submitted = draft
        let submittedKeyInput = keyInput
        do {
            _ = try submitted.config.endpoint("models")
            let key = submittedKeyInput.isEmpty ? try KeychainVault.read(submitted) ?? "" : submittedKeyInput
            let client = AIClient(config: submitted.config, key: key)
            isLoading = true; diagnostic = nil; defer { isLoading = false }
            let fetched = try await client.listModels()
            guard draft == submitted, keyInput == submittedKeyInput else { return }
            models = fetched
            status = fetched.isEmpty ? L("服务没有返回模型，可手动输入模型 ID。", "No models returned. You can enter a model ID manually.") : L("已获取 \(fetched.count) 个模型；是否支持文字生成取决于服务商。", "Loaded \(fetched.count) models. Text support depends on the provider.")
        } catch {
            guard draft == submitted, keyInput == submittedKeyInput else { return }
            diagnostic = diagnosticMessage(operation: L("获取模型", "List models"), config: submitted.config, started: started, error: error)
        }
    }
    func testConnection() async {
        guard !isLoading else { return }
        let started = Date()
        let submitted = draft
        let submittedKeyInput = keyInput
        do {
            _ = try submitted.config.endpoint("models")
            let key = submittedKeyInput.isEmpty ? try KeychainVault.read(submitted) ?? "" : submittedKeyInput
            let client = AIClient(config: submitted.config, key: key)
            let type = AIFileType(fileExtension: "txt", current: nil, candidates: [AICandidate(id: "test_app", name: "Example Editor")])
            let context = AIRequestContext(preference: "Recommend suitable text formats for Example Editor.", types: [type])
            isLoading = true; diagnostic = nil; defer { isLoading = false }
            _ = try await client.recommendations(for: context, responseLanguage: AppLanguage.usesChinese ? "Chinese" : "English")
            guard draft == submitted, keyInput == submittedKeyInput else { return }
            diagnostic = L("连接测试成功：模型返回了可解析的推荐结果。耗时 \(Int(Date().timeIntervalSince(started))) 秒。", "Connection test succeeded: the model returned a valid recommendation response. Elapsed: \(Int(Date().timeIntervalSince(started))) s.")
        } catch {
            guard draft == submitted, keyInput == submittedKeyInput else { return }
            diagnostic = diagnosticMessage(operation: L("测试模型", "Test model"), config: submitted.config, started: started, error: error)
        }
    }
}

struct AISettingsView: View {
    @ObservedObject var settings: AISettingsStore
    @AppStorage(AppLanguage.preferenceKey) private var language = AppLanguage.system.rawValue
    @Environment(\.dismiss) private var dismiss
    @State private var showKey = false
    @State private var confirmDelete = false
    @State private var confirmDeleteKey = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("AI 服务配置", "AI providers")).font(.system(size: 22, weight: .bold))
                    Text(L("保存多个服务，并选择一个用于 AI 助理。", "Save multiple providers and enable one for the assistant.")).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button(L("完成", "Done")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(L("配置列表", "Profiles")).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Menu { Button("OpenAI") { settings.add(.openAI()) }; Button("DeepSeek") { settings.add(.deepSeek()) }; Button(L("自定义", "Custom")) { settings.add(.custom()) } } label: { Image(systemName: "plus") }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel(Text(L("添加配置", "Add profile"))).help(L("添加配置", "Add profile"))
                    }.padding(.horizontal, 10).padding(.top, 12)
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(settings.registry.profiles) { profile in
                                Button { settings.select(profile) } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(profile.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                            Text(profile.id == settings.registry.activeID ? L("已启用", "Enabled") : profile.config.mode.label).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                        Spacer()
                                        if profile.id == settings.registry.activeID { Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue) }
                                    }.padding(9).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                        .background(profile.id == settings.draft.id ? Color.accentColor.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 8))
                                }.buttonStyle(.plain)
                            }
                        }.padding(.horizontal, 6)
                    }
                    Spacer()
                    Button(role: .destructive) { confirmDelete = true } label: { Label(L("删除配置", "Delete profile"), systemImage: "trash") }
                        .disabled(settings.registry.profiles.count <= 1).padding(10)
                }.frame(width: 195).frame(maxHeight: .infinity).background(Color.primary.opacity(0.025))
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        field(L("配置名称", "Profile name")) { TextField(L("例如 DeepSeek", "e.g. DeepSeek"), text: $settings.draft.name).textFieldStyle(.roundedBorder) }
                        field(L("接口类型", "API type")) {
                            Picker("", selection: $settings.draft.config.mode) {
                                ForEach(APIMode.allCases, id: \.self) { Text($0.label).tag($0) }
                            }.labelsHidden().onChange(of: settings.draft.config.mode) { _, _ in settings.endpointChanged() }
                        }
                        field(L("服务基础地址", "Base URL")) {
                            TextField("https://api.example.com/v1", text: $settings.draft.config.baseURL).textFieldStyle(.roundedBorder)
                                .onChange(of: settings.draft.config.baseURL) { _, _ in settings.endpointChanged() }
                            Text(L("远程服务使用 HTTPS；HTTP 仅用于本机。", "Use HTTPS for remote services; HTTP is limited to localhost.")).font(.caption).foregroundStyle(.secondary)
                        }
                        field("API Key") {
                            HStack {
                                Group {
                                    if showKey { TextField(L("输入 API Key", "Enter API key"), text: $settings.keyInput) }
                                    else { SecureField(L("输入 API Key", "Enter API key"), text: $settings.keyInput) }
                                }.textFieldStyle(.roundedBorder).onChange(of: settings.keyInput) { _, _ in settings.diagnostic = nil }
                                Button { showKey.toggle() } label: { Image(systemName: showKey ? "eye.slash" : "eye") }.accessibilityLabel(Text(L("显示或隐藏密钥", "Show or hide API key"))).help(L("显示或隐藏密钥", "Show or hide API key"))
                                Button(L("删除密钥", "Delete key")) { if settings.hasStoredKey { confirmDeleteKey = true } else { settings.keyInput = "" } }.disabled(!settings.hasStoredKey && settings.keyInput.isEmpty)
                            }
                            Text(settings.hasStoredKey ? L("此地址已有密钥；留空保留原密钥。", "A key is saved for this address. Leave blank to keep it.") : L("此地址尚未保存密钥；本地代理可留空。", "No key saved for this address. Local proxies may not need one."))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        field(L("模型", "Model")) {
                            HStack {
                                TextField(L("输入模型 ID", "Enter model ID"), text: $settings.draft.config.model).textFieldStyle(.roundedBorder).onChange(of: settings.draft.config.model) { _, _ in settings.diagnostic = nil }
                                Button(settings.isLoading ? L("获取中…", "Loading…") : L("获取模型", "Get models")) { Task { await settings.fetchModels() } }.disabled(settings.isLoading)
                            }
                            if !settings.models.isEmpty {
                                Picker(L("选择模型", "Choose model"), selection: Binding(get: { settings.models.contains(settings.draft.config.model) ? settings.draft.config.model : "" }, set: { if !$0.isEmpty { settings.draft.config.model = $0 } })) {
                                    Text(L("选择模型…", "Select a model…")).tag("")
                                    ForEach(settings.models, id: \.self) { Text($0).tag($0) }
                                }
                            }
                            Text(L("获取模型会连接此服务，不会发送文件关联信息。", "Fetching models connects to this service without sending file associations.")).font(.caption).foregroundStyle(.secondary)
                        }
                        field(L("连接诊断", "Connection diagnostics")) {
                            Button(settings.isLoading ? L("请求中…", "Working…") : L("测试当前模型", "Test current model")) { Task { await settings.testConnection() } }.disabled(settings.isLoading)
                            Text(L("发送一条固定测试请求，不包含你的文件关联；可能产生费用。", "Sends a fixed test request without your file associations; charges may apply.")).font(.caption).foregroundStyle(.secondary)
                            if let diagnostic = settings.diagnostic { DiagnosticView(message: diagnostic) }
                        }
                    }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }.frame(height: 455).overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08))).clipShape(RoundedRectangle(cornerRadius: 10))
            HStack {
                Text(settings.status ?? " ").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                if settings.hasChanges { Button(L("放弃更改", "Discard")) { settings.discard() } }
                Button(L("保存", "Save")) { settings.save() }
                Button(settings.isDraftActive ? (settings.hasChanges ? L("保存更改", "Save changes") : L("已启用", "Enabled")) : L("保存并启用", "Save & enable")) { settings.activate() }.buttonStyle(.borderedProminent).disabled(settings.isDraftActive && !settings.hasChanges)
            }
        }.padding(22).frame(width: 840)
        .alert(L("AI 设置", "AI settings"), isPresented: Binding(get: { settings.error != nil }, set: { if !$0 { settings.error = nil } })) { Button(L("好", "OK")) { settings.error = nil } } message: { Text(settings.error ?? "") }
        .onChange(of: settings.draft.id) { _, _ in showKey = false }
        .confirmationDialog(L("删除此地址的密钥？", "Delete the API key for this address?"), isPresented: $confirmDeleteKey) {
            Button(L("删除密钥", "Delete key"), role: .destructive) { settings.deleteKey() }
            Button(L("取消", "Cancel"), role: .cancel) {}
        }
        .confirmationDialog(L("删除此配置及其所有地址对应的密钥？", "Delete this profile and its keys for all addresses?"), isPresented: $confirmDelete) {
            Button(L("删除配置", "Delete profile"), role: .destructive) { settings.removeProfile() }
            Button(L("取消", "Cancel"), role: .cancel) {}
        }
    }
    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) { Text(label).font(.system(size: 12, weight: .semibold)); content() }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
