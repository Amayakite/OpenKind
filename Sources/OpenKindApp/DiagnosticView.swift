import SwiftUI
import AppKit
import OpenKindCore

// Diagnostics deliberately exclude credentials, raw response bodies, URLs and file associations.
func diagnosticMessage(operation: String, config: ProviderConfiguration, started: Date, error: Error, batch: String? = nil) -> String {
    let detail = (error as? AIError)?.localizedDescription ?? L("请求未能完成。请检查配置和系统钥匙串权限。", "The request could not be completed. Check the configuration and Keychain access.")
    let elapsed = max(0, Int(Date().timeIntervalSince(started)))
    let label = L("操作", "Operation") + ": " + operation
    let mode = L("接口", "API") + ": " + config.mode.label
    let time = L("耗时", "Elapsed") + ": " + String(elapsed) + "s"
    return ([label, mode, time] + (batch.map { [$0] } ?? []) + [detail]).joined(separator: "\n")
}

struct DiagnosticView: View {
    let message: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(message).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Text(L("不包含密钥、响应原文或文件关联。", "Excludes keys, raw responses and file associations.")).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button(L("复制诊断", "Copy diagnostics")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(message, forType: .string)
                }.controlSize(.small)
            }
        }.padding(10).background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}
