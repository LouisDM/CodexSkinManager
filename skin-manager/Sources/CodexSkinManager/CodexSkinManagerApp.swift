import AppKit
import SwiftUI
import UniformTypeIdentifiers

@main
struct CodexSkinManagerApp: App {
    @NSApplicationDelegateAdaptor(TerminationCoordinator.self) private var terminationCoordinator
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Codex 皮肤管理器") {
            ContentView()
                .environmentObject(model)
                .task {
                    terminationCoordinator.model = model
                    await model.bootstrap()
                }
                .onOpenURL { url in
                    Task { await model.importSkin(from: url) }
                }
        }
        .defaultSize(width: 1_180, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("导入皮肤…") { presentImportPanel() }
                    .keyboardShortcut("o", modifiers: .command)
                Button(model.actions.applyTitle) { Task { await model.applySelected() } }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(!model.actions.canApply)
                Divider()
                Button("恢复默认界面") { Task { await model.restoreDefault() } }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(!model.actions.canRestore)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(model)
                .frame(width: 560, height: 390)
        }

        MenuBarExtra("Codex 皮肤", systemImage: "paintpalette.fill") {
            Text(model.statePresentation.title)
                .font(.headline)
            Text(model.statePresentation.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            Button("打开皮肤管理器") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
            }
            Button(model.actions.applyTitle) { Task { await model.applySelected() } }
                .disabled(!model.actions.canApply)
            Button("恢复默认界面") { Task { await model.restoreDefault() } }
                .disabled(!model.actions.canRestore)
            Divider()
            Button("退出皮肤管理器") { NSApp.terminate(nil) }
        }
    }

    private func presentImportPanel() {
        let panel = NSOpenPanel()
        panel.title = "导入 Codex 皮肤"
        panel.prompt = "导入"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "codexskin") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await model.importSkin(from: url) }
    }
}
