import SwiftUI
import OpenKindCore

struct GeneralSettingsView: View {
    @ObservedObject var settings: AISettingsStore
    @AppStorage(AppLanguage.preferenceKey) private var language = AppLanguage.system.rawValue
    @State private var showProviders = false
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 7) {
                Text(L("设置", "Settings")).font(.system(size: 28, weight: .bold))
                Text(L("自定义 OpenKind 的使用方式。", "Customize how OpenKind works.")).font(.system(size: 13)).foregroundStyle(.secondary)
            }.padding(.top, 38)
            VStack(alignment: .leading, spacing: 14) {
                Label(L("语言", "Language"), systemImage: "globe").font(.system(size: 15, weight: .semibold))
                Text(L("默认跟随系统，也可以单独指定应用语言。", "Follow the system language or choose one for this app.")).font(.callout).foregroundStyle(.secondary)
                Picker(L("显示语言", "Display language"), selection: $language) {
                    Text(L("跟随系统", "Follow system")).tag(AppLanguage.system.rawValue)
                    Text("简体中文").tag(AppLanguage.simplifiedChinese.rawValue)
                    Text("English").tag(AppLanguage.english.rawValue)
                }.pickerStyle(.menu).frame(maxWidth: 360, alignment: .leading)
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 14) {
                Label(L("AI 服务", "AI providers"), systemImage: "sparkles").font(.system(size: 15, weight: .semibold))
                Text(L("添加、编辑服务配置并选择启用项。", "Add and edit provider profiles, and choose the active one.")).font(.callout).foregroundStyle(.secondary)
                Button(L("管理 AI 服务…", "Manage AI providers…")) { showProviders = true }
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 11))
            Spacer()
        }.padding(.horizontal, 32).frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showProviders) { AISettingsView(settings: settings) }
    }
}
