import AppKit
import Foundation
import SkinCore
import SwiftUI

struct SkinSelection: Hashable, Sendable {
    let id: String
    let version: String

    init(_ skin: InstalledSkin) {
        id = skin.id
        version = skin.version
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var skins: [InstalledSkin] = []
    @Published var selection: SkinSelection?
    @Published var filter: SkinLibraryFilter = .all
    @Published private(set) var active: ActiveSkinRecord?
    @Published private(set) var state: SkinApplicationState = .idle
    @Published private(set) var inspection: CodexAppInspection?
    @Published var alertMessage: String?
    @Published private(set) var isBootstrapping = true
    @Published private(set) var watcherOwnedThisSession = false

    let repository: SkinRepository
    let resourcesRootURL: URL
    let stateRootURL: URL
    let officialAppURL: URL

    private let importer: SkinPackageImporter
    private let exporter = SkinPackageExporter()
    private let inspector: CodexAppInspector
    private let controller: SkinApplicationController
    private var didBootstrap = false

    init(
        repositoryRootURL: URL? = nil,
        resourcesRootURL: URL? = nil,
        officialAppURL: URL = URL(fileURLWithPath: "/Applications/ChatGPT.app")
    ) {
        let resolvedRepositoryRoot = repositoryRootURL
            ?? ProcessInfo.processInfo.environment["CODEX_SKIN_MANAGER_STATE_ROOT"].map {
                URL(fileURLWithPath: $0, isDirectory: true)
            }
            ?? SkinRepository.defaultRootURL
        let resolvedResources = resourcesRootURL
            ?? ProcessInfo.processInfo.environment["CODEX_SKIN_MANAGER_RESOURCES_ROOT"].map {
                URL(fileURLWithPath: $0, isDirectory: true)
            }
            ?? Bundle.main.resourceURL
            ?? URL(fileURLWithPath: "/", isDirectory: true)
        let stateRoot = resolvedRepositoryRoot.appending(path: "runtime", directoryHint: .isDirectory)
        let repository = SkinRepository(rootURL: resolvedRepositoryRoot)
        let inspector = CodexAppInspector()
        let runtime = SkinRuntimeResources(
            nodeURL: officialAppURL.appending(path: "Contents/Resources/cua_node/bin/node"),
            injectorURL: resolvedResources.appending(path: "Engine/injector.mjs"),
            templatesURL: resolvedResources.appending(path: "Templates", directoryHint: .isDirectory),
            stateRootURL: stateRoot,
            port: 9_340
        )
        self.repository = repository
        self.resourcesRootURL = resolvedResources
        self.stateRootURL = stateRoot
        self.officialAppURL = officialAppURL
        self.importer = SkinPackageImporter()
        self.inspector = inspector
        self.controller = SkinApplicationController(
            repository: repository,
            inspector: inspector,
            resources: runtime,
            appURL: officialAppURL
        )
    }

    var selectedSkin: InstalledSkin? {
        guard let selection else { return nil }
        return skins.first { $0.id == selection.id && $0.version == selection.version }
    }

    var filteredSkins: [InstalledSkin] {
        skins.filter { filter.includes($0, active: active) }
    }

    var actions: SkinActionAvailability {
        SkinActionAvailability(selected: selectedSkin, active: active, inspection: inspection, state: state)
    }

    var verifiedActive: ActiveSkinRecord? {
        if case let .active(record) = state { return record }
        return nil
    }

    var statePresentation: SkinStatePresentation {
        let record: ActiveSkinRecord?
        switch state {
        case let .applying(value), let .active(value): record = value
        default: record = active
        }
        let displayName = record.flatMap { activeRecord in
            skins.first { $0.id == activeRecord.id && $0.version == activeRecord.version }?.name
        }
        return SkinStatePresentation(state, activeDisplayName: displayName)
    }

    func activityLabel(for skin: InstalledSkin) -> String? {
        let record = ActiveSkinRecord(id: skin.id, version: skin.version)
        if verifiedActive == record { return "已验证生效" }
        if active == record { return "上次使用" }
        return nil
    }

    var inspectionPresentation: CodexInspectionPresentation { CodexInspectionPresentation(inspection) }
    var logURL: URL { stateRootURL.appending(path: "injector.log") }
    var repositoryRootDisplayPath: String { stateRootURL.deletingLastPathComponent().path }

    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        await controller.setStateHandler { [weak self] state in
            Task { @MainActor [weak self] in self?.state = state }
        }
        do {
            try await installBundledSkinsIfNeeded()
            try await refreshLibrary()
        } catch {
            alertMessage = "初始化皮肤库失败：\(error.localizedDescription)"
        }
        await inspectOfficialApp()
        if let active {
            if selection == nil { selection = SkinSelection(id: active.id, version: active.version) }
        }
        isBootstrapping = false
    }

    func inspectOfficialApp() async {
        inspection = await inspector.inspect(appURL: officialAppURL, port: 9_340)
    }

    func refreshLibrary() async throws {
        skins = try await repository.listInstalled()
        active = try await repository.activeSkin()
        if let selection,
           !skins.contains(where: { $0.id == selection.id && $0.version == selection.version })
        {
            self.selection = nil
        }
        if selection == nil {
            if let active,
               let match = skins.first(where: { $0.id == active.id && $0.version == active.version })
            {
                selection = SkinSelection(match)
            } else if let first = skins.first {
                selection = SkinSelection(first)
            }
        }
    }

    func importSkin(from url: URL) async {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  url.pathExtension.lowercased() == "codexskin"
            else {
                throw AppModelError.invalidImportFile
            }
            guard (values.fileSize ?? Int.max) <= 64 * 1_024 * 1_024 else {
                throw AppModelError.packageTooLarge
            }
            let imported = try importer.importPackage(data: Data(contentsOf: url, options: .mappedIfSafe))
            let outcome = try await repository.install(imported)
            let installed: InstalledSkin
            switch outcome {
            case let .installed(value), let .alreadyInstalled(value): installed = value
            }
            try await refreshLibrary()
            selection = SkinSelection(installed)
        } catch {
            alertMessage = "导入失败：\(error.localizedDescription)"
        }
    }

    func applySelected() async {
        guard let selectedSkin, actions.canApply else { return }
        await controller.apply(id: selectedSkin.id, version: selectedSkin.version)
        state = await controller.currentState()
        watcherOwnedThisSession = await controller.ownsWatcher()
        do {
            try await refreshLibrary()
        } catch {
            alertMessage = "刷新皮肤状态失败：\(error.localizedDescription)"
        }
        await inspectOfficialApp()
    }

    func cancelWaiting() async {
        await controller.cancelWaiting()
    }

    func restoreDefault() async {
        await controller.restore()
        state = await controller.currentState()
        watcherOwnedThisSession = false
        do { try await refreshLibrary() }
        catch { alertMessage = "刷新皮肤状态失败：\(error.localizedDescription)" }
    }

    func stopOwnedWatcher() async {
        await controller.stopOwnedWatcher()
        watcherOwnedThisSession = false
    }

    func deleteSelected() async {
        guard let selectedSkin, actions.canDelete else { return }
        do {
            try await repository.delete(id: selectedSkin.id, version: selectedSkin.version)
            selection = nil
            try await refreshLibrary()
        } catch {
            alertMessage = "删除失败：\(error.localizedDescription)"
        }
    }

    func exportSelected(to destination: URL) async {
        guard let selectedSkin, actions.canExport else { return }
        do {
            let stored = try await repository.load(id: selectedSkin.id, version: selectedSkin.version)
            try exporter.export(stored, to: destination)
        } catch {
            alertMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    func revealLog() {
        try? FileManager.default.createDirectory(at: stateRootURL, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        NSWorkspace.shared.activateFileViewerSelecting([logURL])
    }

    func markWindowVisibleForTests() {
        guard ProcessInfo.processInfo.environment["CODEX_SKIN_MANAGER_UI_TEST"] == "1" else { return }
        do {
            try FileManager.default.createDirectory(at: stateRootURL, withIntermediateDirectories: true)
            let marker: [String: Any] = [
                "pid": ProcessInfo.processInfo.processIdentifier,
                "visible": true,
            ]
            let data = try JSONSerialization.data(withJSONObject: marker, options: [.sortedKeys])
            try data.write(to: stateRootURL.appending(path: "ui-ready.json"), options: .atomic)
        } catch {
            alertMessage = "UI 测试标记写入失败：\(error.localizedDescription)"
        }
    }

    private func installBundledSkinsIfNeeded() async throws {
        let builtinsURL = resourcesRootURL.appending(path: "BuiltinSkins", directoryHint: .isDirectory)
        let existing = try await repository.listInstalled()
        let installedKeys = Set(existing.map { "\($0.id)@\($0.version)" })
        let directories = try FileManager.default.contentsOfDirectory(
            at: builtinsURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ).sorted { $0.lastPathComponent < $1.lastPathComponent }
        for directory in directories {
            let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { continue }
            let manifestData = try Data(contentsOf: directory.appending(path: "manifest.json"))
            let manifest = try JSONDecoder().decode(SkinManifest.self, from: manifestData)
            if installedKeys.contains("\(manifest.id)@\(manifest.version)") { continue }
            let package = try importer.importBundledPackage(at: directory)
            _ = try await repository.install(package)
        }
    }
}

private enum AppModelError: Error, LocalizedError {
    case invalidImportFile
    case packageTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidImportFile: "请选择普通的 .codexskin 文件"
        case .packageTooLarge: "皮肤包超过 64 MiB 限制"
        }
    }
}

private extension SkinSelection {
    init(id: String, version: String) {
        self.id = id
        self.version = version
    }
}
