import Foundation

public enum SkinLibraryFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case active
    case privateOnly
    case unverified

    public static let allCases: [SkinLibraryFilter] = [.all, .active]

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: "全部皮肤"
        case .active: "最近使用"
        case .privateOnly: "受限皮肤"
        case .unverified: "来源提示"
        }
    }

    public var systemImage: String {
        switch self {
        case .all: "square.grid.2x2"
        case .active: "clock.arrow.circlepath"
        case .privateOnly: "tray.full"
        case .unverified: "checkmark.shield"
        }
    }

    public func includes(_ skin: InstalledSkin, active activeRecord: ActiveSkinRecord?) -> Bool {
        switch self {
        case .all: true
        case .active: activeRecord?.id == skin.id
        case .privateOnly, .unverified: true
        }
    }
}

public enum SkinLibraryInventory {
    public static func visibleSkins(from installedVersions: [InstalledSkin]) -> [InstalledSkin] {
        var latestByID: [String: InstalledSkin] = [:]
        for skin in installedVersions {
            guard let current = latestByID[skin.id] else {
                latestByID[skin.id] = skin
                continue
            }
            if isVersion(skin.version, newerThan: current.version) {
                latestByID[skin.id] = skin
            }
        }
        return latestByID.values.sorted {
            let nameComparison = $0.name.localizedStandardCompare($1.name)
            if nameComparison == .orderedSame { return $0.id < $1.id }
            return nameComparison == .orderedAscending
        }
    }

    private static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let candidateComponents = candidate.split(separator: ".").compactMap { Int($0) }
        let currentComponents = current.split(separator: ".").compactMap { Int($0) }
        return currentComponents.lexicographicallyPrecedes(candidateComponents)
    }
}

public struct SkinLibrarySummaryPresentation: Equatable, Sendable {
    public let title: String
    public let countLabel: String

    public init(filter: SkinLibraryFilter, visibleCount: Int, totalCount: Int) {
        title = filter == .all ? "皮肤" : filter.title
        countLabel = filter == .all
            ? "\(totalCount) 套皮肤"
            : "\(visibleCount) / \(totalCount) 套皮肤"
    }
}

public struct SkinNavigatorItemPresentation: Equatable, Sendable {
    public let title: String
    public let metadata: String
    public let rightsLabel: String
    public let rightsSystemImage: String
    public let activityLabel: String?
    public let accessibilityLabel: String

    public init(_ skin: InstalledSkin, activityLabel: String?) {
        let rights = SkinRightsPresentation(skin.rights)
        title = skin.name
        metadata = "\(skin.author.name) · v\(skin.version)"
        rightsLabel = rights.label
        rightsSystemImage = rights.systemImage
        self.activityLabel = activityLabel
        accessibilityLabel = [
            skin.name,
            "作者 \(skin.author.name)",
            "版本 \(skin.version)",
            rights.label,
            activityLabel,
        ]
        .compactMap { $0 }
        .joined(separator: "，")
    }
}

public enum SkinDetailLayout {
    public static let previewAspectRatio: CGFloat = 16 / 10
    public static let badgeMinimumWidth: CGFloat = 210
    public static let minimumPaneWidth: CGFloat = 360
    public static let idealPaneWidth: CGFloat = 500
    public static let maximumPaneWidth: CGFloat = 720
}

public struct SkinDetailVisibilityPresentation: Equatable, Sendable {
    public let title: String
    public let systemImage: String

    public init(isPresented: Bool) {
        title = isPresented ? "收起详情" : "显示详情"
        systemImage = "sidebar.trailing"
    }
}

public struct SkinFileTransferPresentation: Equatable, Sendable {
    public let importTitle = "导入"
    public let exportTitle = "导出"
    public let importSystemImage = "square.and.arrow.down"
    public let exportSystemImage: String
    public let importHelp = "导入 .codexskin，也可以把文件拖进窗口"
    public let exportHelp: String
    public let canImport: Bool
    public let canExport: Bool

    public init(actions: SkinActionAvailability) {
        canImport = actions.canImport
        canExport = actions.canExport
        exportSystemImage = "square.and.arrow.up"
        exportHelp = actions.exportDisabledReason ?? "导出所选皮肤为 .codexskin"
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
            label = "包已安全校验"
            detail = "签名有效；发布者指纹：\(fingerprint)。"
            systemImage = "checkmark.shield"
        case .unsigned:
            label = "包已安全校验"
            detail = "包结构、清单和文件内容已通过导入校验。"
            systemImage = "checkmark.shield"
        }
    }
}

public struct SkinRightsPresentation: Equatable, Sendable {
    public let label: String
    public let detail: String
    public let systemImage: String

    public init(_ rights: SkinRights) {
        label = "允许导入导出"
        detail = rights.canExportPublicly
            ? "清单声明素材允许重新分发，可导出为 .codexskin。"
            : "管理器允许导入和导出此皮肤；对外分享前请自行确认素材权利。"
        systemImage = "square.and.arrow.up"
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
        privateExportMessage = nil
    }
}

public struct SkinActionAvailability: Equatable, Sendable {
    public let canApply: Bool
    public let canRestore: Bool
    public let canDelete: Bool
    public let canExport: Bool
    public let canImport: Bool
    public let canCancelWaiting: Bool
    public let exportIsRightsRestricted: Bool
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
        canExport = selected != nil && !busy
        canImport = !busy
        canCancelWaiting = state == .waitingForQuit
        exportIsRightsRestricted = false

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
                detail = "上次使用：\(activeDisplayName)。\n重新应用后会验证当前 Codex 界面。"
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
