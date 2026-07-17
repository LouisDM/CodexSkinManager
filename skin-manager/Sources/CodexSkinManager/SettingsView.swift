import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("官方 Codex") {
                LabeledContent("应用", value: model.officialAppURL.path)
                LabeledContent("状态", value: model.inspectionPresentation.statusLabel)
                Button("重新检查签名与端口") { Task { await model.inspectOfficialApp() } }
            }

            Section("本机运行时") {
                LabeledContent("CDP 监听", value: "127.0.0.1:9340")
                LabeledContent("资料库", value: model.repositoryRootDisplayPath)
                LabeledContent("运行日志", value: model.logURL.path)
                Button("在 Finder 中显示日志") { model.revealLog() }
            }

            Section("安全边界") {
                Text("管理器不会修改官方应用包，不会强制结束 Codex，也不会执行皮肤包携带的脚本、CSS 或二进制文件。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(12)
    }
}
