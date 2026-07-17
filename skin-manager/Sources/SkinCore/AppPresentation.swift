import Foundation

public enum SkinLibraryFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case active
    case privateOnly
    case unverified

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: "全部皮肤"
        case .active: "最近使用"
        case .privateOnly: "仅限本机"
        case .unverified: "未验证来源"
        }
    }

    public var systemImage: String {
        switch self {
        case .all: "square.grid.2x2"
        case .active: "clock.arrow.circlepath"
        case .privateOnly: "lock.shield"
        case .unverified: "exclamationmark.shield"
        }
    }

    public func includes(_ skin: InstalledSkin, active activeRecord: ActiveSkinRecord?) -> Bool {
        switch self {
        case .all: true
        case .active: activeRecord == ActiveSkinRecord(id: skin.id, version: skin.version)
        case .privateOnly: !skin.rights.canExportPublicly
        case .unverified:
            if case .verifiedPublisher = skin.trust { false } else { true }
        }
    }
}

public struct SkinTrustPresentation: Equatable, Sendable {
    public let label: String
    public let detail: String
    public let systemImage: String

    public init(_ trust: SkinTrustState) {
        switch trust {
        case let .verifiedPublisher(fingerprint):
            label = "发布者已验证"
            detail = "签名指纹：\(fingerprint)"
            systemImage = "checkmark.seal.fill"
        case let .signedUnknownPublisher(fingerprint):
            label = "签名未知"
            detail = "签名有效，但发布者尚未受信任。指纹：\(fingerprint)"
            systemImage = "questionmark.diamond"
        case .unsigned:
            label = "未签名"
            detail = "包内容已通过安全校验，但无法确认发布者身份。"
            systemImage = "exclamationmark.shield"
        }
    }
}

public struct SkinRightsPresentation: Equatable, Sendable {
    public let label: String
    public let detail: String
    public let systemImage: String

    public init(_ rights: SkinRights) {
        if rights.canExportPublicly {
            label = "允许导出"
            detail = "清单声明素材允许重新分发，可导出为 .codexskin。"
            systemImage = "square.and.arrow.up"
        } else {
            label = "仅限本机"
            detail = "当前素材授权不可导出共享，只能在本机预览和使用。"
            systemImage = "lock.shield"
        }
    }
}

public struct SkinCardPresentation: Equatable, Sendable, Identifiable {
    public let id: String
    public let version: String
    public let name: String
    public let author: String
    public let previewURL: URL
    public let trust: SkinTrustPresentation
    public let rights: SkinRightsPresentation
    public let privateExportMessage: String?

    public init(_ skin: InstalledSkin) {
        id = skin.id
        version = skin.version
        name = skin.name
        author = skin.author.name
        previewURL = skin.previewURL
        trust = SkinTrustPresentation(skin.trust)
        rights = SkinRightsPresentation(skin.rights)
        privateExportMessage = skin.rights.canExportPublicly ? nil : "仅供本机预览与使用，不可导出共享"
    }
}

public struct SkinActionAvailability: Equatable, Sendable {
    public let canApply: Bool
    public let canRestore: Bool
    public let canDelete: Bool
    public let canExport: Bool
    public let canImport: Bool
    public let canCancelWaiting: Bool
    public let applyTitle: String
    public let applyDisabledReason: String?
    public let exportDisabledReason: String?

    public init(
        selected: InstalledSkin?,
        active: ActiveSkinRecord?,
        inspection: CodexAppInspection?,
        state: SkinApplicationState
    ) {
        let busy = Self.isBusy(state)
        let selectedRecord = selected.map { ActiveSkinRecord(id: $0.id, version: $0.version) }
        let isSelectedActive = selectedRecord != nil && selectedRecord == active
        let appReady = inspection?.canApply == true

        canApply = selected != nil && !busy && appReady
        canRestore = active != nil && !busy
        canDelete = selected != nil && !isSelectedActive && !busy
        canExport = selected?.rights.canExportPublicly == true && !busy
        canImport = !busy
        canCancelWaiting = state == .waitingForQuit

        if case .failed = state {
            applyTitle = "重试切换"
        } else if isSelectedActive {
            applyTitle = "重新应用"
        } else {
            applyTitle = "切换到此皮肤"
        }

        if selected == nil {
            applyDisabledReason = "请先选择一个皮肤"
        } else if busy {
            applyDisabledReason = "当前操作完成后可继续"
        } else if inspection == nil {
            applyDisabledReason = "正在检查官方 Codex"
        } else if !appReady {
            applyDisabledReason = inspection?.issues.first?.detail ?? "官方 Codex 未通过安全检查"
        } else {
            applyDisabledReason = nil
        }

        if selected == nil {
            exportDisabledReason = "请先选择一个皮肤"
        } else if selected?.rights.canExportPublicly != true {
            exportDisabledReason = "当前素材授权不允许导出共享"
        } else if busy {
            exportDisabledReason = "当前操作完成后可继续"
        } else {
            exportDisabledReason = nil
        }
    }

    private static func isBusy(_ state: SkinApplicationState) -> Bool {
        switch state {
        case .checking, .waitingForQuit, .startingCodex, .applying, .restoring: true
        case .idle, .active, .cancelled, .failed: false
        }
    }
}

public struct SkinStatePresentation: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let systemImage: String
    public let showsProgress: Bool
    public let isError: Bool

    public init(_ state: SkinApplicationState, activeDisplayName: String? = nil) {
        switch state {
        case .idle:
            if let activeDisplayName {
                title = "上次使用记录"
                detail = "上次使用：\(activeDisplayName)。重新应用后会验证并确认当前 Codex 界面。"
                systemImage = "clock.arrow.circlepath"
            } else {
                title = "就绪"
                detail = "选择皮肤后即可预览、导入或应用。"
                systemImage = "circle.dotted"
            }
            showsProgress = false
            isError = false
        case .checking:
            title = "正在安全检查"
            detail = "正在校验官方 Codex、代码签名和本机调试端口。"
            systemImage = "checkmark.shield"
            showsProgress = true
            isError = false
        case .waitingForQuit:
            title = "等待 Codex 正常退出"
            detail = "请在 Codex 中按 ⌘Q；管理器不会强制结束它。"
            systemImage = "clock"
            showsProgress = true
            isError = false
        case .startingCodex:
            title = "正在启动 Codex"
            detail = "正在通过 127.0.0.1 的本机调试端口启动官方应用。"
            systemImage = "app.badge"
            showsProgress = true
            isError = false
        case let .applying(record):
            title = "正在应用皮肤"
            detail = "正在应用 \(activeDisplayName ?? record.id) · v\(record.version)，并启动页面修复守护。"
            systemImage = "paintbrush.pointed"
            showsProgress = true
            isError = false
        case let .active(record):
            title = "皮肤已验证生效"
            detail = "当前：\(activeDisplayName ?? record.id) · v\(record.version)"
            systemImage = "checkmark.seal.fill"
            showsProgress = false
            isError = false
        case .restoring:
            title = "正在恢复默认界面"
            detail = "正在移除页面皮肤并停止管理器自己的守护进程。"
            systemImage = "arrow.uturn.backward.circle"
            showsProgress = true
            isError = false
        case .cancelled:
            title = "操作已取消"
            detail = "Codex 未被终止，当前皮肤状态保持不变。"
            systemImage = "xmark.circle"
            showsProgress = false
            isError = false
        case let .failed(message):
            title = "操作未完成"
            detail = message.isEmpty ? "发生未知错误，请查看日志。" : message
            systemImage = "xmark.octagon.fill"
            showsProgress = false
            isError = true
        }
    }
}

public struct CodexInspectionPresentation: Equatable, Sendable {
    public let blockingBanner: String?
    public let statusLabel: String

    public init(_ inspection: CodexAppInspection?) {
        guard let inspection else {
            blockingBanner = nil
            statusLabel = "等待检查"
            return
        }
        if inspection.canApply {
            blockingBanner = nil
            statusLabel = inspection.portStatus.isReady ? "官方 Codex 已连接" : "官方 Codex 可安全启动"
        } else {
            blockingBanner = inspection.issues.map(\.detail).joined(separator: "\n")
            statusLabel = "应用功能已阻止"
        }
    }
}
