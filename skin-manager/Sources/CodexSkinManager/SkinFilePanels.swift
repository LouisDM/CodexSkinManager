import AppKit
import SkinCore
import UniformTypeIdentifiers

@MainActor
enum SkinFilePanels {
    private static let codexSkinType = UTType(filenameExtension: "codexskin") ?? .data

    static func chooseImport() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "导入 Codex 皮肤"
        panel.prompt = "导入"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [codexSkinType]
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    static func chooseExport(for skin: InstalledSkin) -> URL? {
        let panel = NSSavePanel()
        panel.title = "导出 Codex 皮肤"
        panel.prompt = "导出"
        panel.nameFieldStringValue = "\(skin.id)-\(skin.version).codexskin"
        panel.allowedContentTypes = [codexSkinType]
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}
