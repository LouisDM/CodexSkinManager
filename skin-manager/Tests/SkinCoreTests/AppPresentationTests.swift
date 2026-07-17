import Foundation
import XCTest
@testable import SkinCore

final class AppPresentationTests: XCTestCase {
    func testLibraryFiltersCoverInventoryAndSafetyStates() {
        XCTAssertEqual(SkinLibraryFilter.allCases, [.all, .active, .privateOnly, .unverified])
        XCTAssertEqual(SkinLibraryFilter.all.title, "全部皮肤")
        XCTAssertEqual(SkinLibraryFilter.active.title, "最近使用")
        XCTAssertEqual(SkinLibraryFilter.privateOnly.systemImage, "lock.shield")
    }

    func testLibraryShowsOnlyTheLatestInstalledVersionForEachSkinIdentity() {
        let distributable = rights(redistributionAllowed: true)
        let installedVersions = [
            installed(id: "meng-chuan-red-lotus", name: "孟川 · 红莲业火", version: "1.0.0", rights: distributable),
            installed(id: "meng-chuan-red-lotus", name: "孟川 · 红莲业火", version: "1.0.1", rights: distributable),
            installed(id: "meng-chuan-nightblade", name: "孟川 · 玄刃夜行", version: "1.9.0", rights: distributable),
            installed(id: "meng-chuan-nightblade", name: "孟川 · 玄刃夜行", version: "1.10.0", rights: distributable),
            installed(id: "liu-qiyue-undying-phoenix", name: "柳七月 · 不死凰焰", version: "1.0.0", rights: distributable),
        ]

        let visible = SkinLibraryInventory.visibleSkins(from: installedVersions)

        XCTAssertEqual(visible.count, 3)
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: visible.map { ($0.id, $0.version) }),
            [
                "liu-qiyue-undying-phoenix": "1.0.0",
                "meng-chuan-nightblade": "1.10.0",
                "meng-chuan-red-lotus": "1.0.1",
            ]
        )
    }

    func testRecentlyUsedFilterMatchesSkinIdentityAfterAStoredVersionUpgrade() {
        let latest = installed(
            id: "meng-chuan-red-lotus",
            version: "1.0.1",
            rights: rights(redistributionAllowed: true)
        )
        let previouslyUsed = ActiveSkinRecord(id: latest.id, version: "1.0.0")

        XCTAssertTrue(SkinLibraryFilter.active.includes(latest, active: previouslyUsed))
    }

    func testLibrarySummaryMakesFilteringAndTotalInventoryVisible() {
        let all = SkinLibrarySummaryPresentation(filter: .all, visibleCount: 3, totalCount: 3)
        let privateOnly = SkinLibrarySummaryPresentation(filter: .privateOnly, visibleCount: 1, totalCount: 3)

        XCTAssertEqual(all.title, "皮肤")
        XCTAssertEqual(all.countLabel, "3 套皮肤")
        XCTAssertEqual(privateOnly.title, "仅限本机")
        XCTAssertEqual(privateOnly.countLabel, "1 / 3 套皮肤")
    }

    func testNavigatorItemProvidesCompactDecisionInformation() {
        let skin = installed(
            id: "meng-chuan-red-lotus",
            name: "孟川 · 红莲业火",
            author: "OPCspace",
            version: "1.0.1",
            rights: rights(redistributionAllowed: true)
        )

        let item = SkinNavigatorItemPresentation(skin, activityLabel: "已验证生效")

        XCTAssertEqual(item.title, "孟川 · 红莲业火")
        XCTAssertEqual(item.metadata, "OPCspace · v1.0.1")
        XCTAssertEqual(item.rightsLabel, "允许导出")
        XCTAssertEqual(item.activityLabel, "已验证生效")
        XCTAssertTrue(item.accessibilityLabel.contains("孟川 · 红莲业火"))
        XCTAssertTrue(item.accessibilityLabel.contains("已验证生效"))
    }

    func testDetailLayoutDefinesFlexiblePreviewAndResizablePaneBounds() {
        XCTAssertEqual(SkinDetailLayout.previewAspectRatio, 1.6)
        XCTAssertEqual(SkinDetailLayout.badgeMinimumWidth, 210)
        XCTAssertLessThan(SkinDetailLayout.minimumPaneWidth, SkinDetailLayout.idealPaneWidth)
        XCTAssertLessThan(SkinDetailLayout.idealPaneWidth, SkinDetailLayout.maximumPaneWidth)
    }

    func testDetailVisibilityButtonExplainsCollapseAndExpandStates() {
        let shown = SkinDetailVisibilityPresentation(isPresented: true)
        let hidden = SkinDetailVisibilityPresentation(isPresented: false)

        XCTAssertEqual(shown.title, "收起详情")
        XCTAssertEqual(hidden.title, "显示详情")
        XCTAssertEqual(shown.systemImage, "sidebar.trailing")
        XCTAssertEqual(hidden.systemImage, "sidebar.trailing")
    }

    func testFileTransferPresentationKeepsImportAndExportAsPeerActions() {
        let selected = installed(id: "shareable", rights: rights(redistributionAllowed: true))
        let actions = SkinActionAvailability(
            selected: selected,
            active: nil,
            inspection: inspection(signatureValid: true),
            state: .idle
        )

        let transfer = SkinFileTransferPresentation(actions: actions)

        XCTAssertEqual(transfer.importTitle, "导入")
        XCTAssertEqual(transfer.exportTitle, "导出")
        XCTAssertEqual(transfer.importSystemImage, "square.and.arrow.down")
        XCTAssertEqual(transfer.exportSystemImage, "square.and.arrow.up")
        XCTAssertEqual(transfer.importHelp, "导入 .codexskin，也可以把文件拖进窗口")
        XCTAssertEqual(transfer.exportHelp, "导出所选皮肤为 .codexskin")
        XCTAssertTrue(transfer.canImport)
        XCTAssertTrue(transfer.canExport)
    }

    func testFileTransferPresentationExplainsPrivateExportRestriction() {
        let selected = installed(id: "private", rights: rights(redistributionAllowed: false))
        let actions = SkinActionAvailability(
            selected: selected,
            active: nil,
            inspection: inspection(signatureValid: true),
            state: .idle
        )

        let transfer = SkinFileTransferPresentation(actions: actions)

        XCTAssertFalse(transfer.canExport)
        XCTAssertEqual(transfer.exportSystemImage, "lock.fill")
        XCTAssertEqual(transfer.exportHelp, "当前素材授权不允许导出共享")
    }

    func testFileTransferPresentationDoesNotMistakeBusyStateForRightsLock() {
        let selected = installed(id: "shareable", rights: rights(redistributionAllowed: true))
        let record = ActiveSkinRecord(id: selected.id, version: selected.version)
        let actions = SkinActionAvailability(
            selected: selected,
            active: nil,
            inspection: inspection(signatureValid: true),
            state: .applying(record)
        )

        let transfer = SkinFileTransferPresentation(actions: actions)

        XCTAssertFalse(transfer.canExport)
        XCTAssertEqual(transfer.exportSystemImage, "square.and.arrow.up")
        XCTAssertEqual(transfer.exportHelp, "当前操作完成后可继续")
    }

    func testTrustAndRightsBadgesAreExplicit() {
        XCTAssertEqual(SkinTrustPresentation(.verifiedPublisher(fingerprint: "abc")).label, "发布者已验证")
        XCTAssertEqual(SkinTrustPresentation(.signedUnknownPublisher(fingerprint: "abc")).label, "签名未知")
        XCTAssertEqual(SkinTrustPresentation(.unsigned).label, "未签名")

        let privateRights = rights(redistributionAllowed: false)
        let publicRights = rights(redistributionAllowed: true)
        XCTAssertEqual(SkinRightsPresentation(privateRights).label, "仅限本机")
        XCTAssertTrue(SkinRightsPresentation(privateRights).detail.contains("不可导出共享"))
        XCTAssertEqual(SkinRightsPresentation(publicRights).label, "允许导出")
    }

    func testActionAvailabilityProtectsActiveAndPrivateSkins() {
        let selected = installed(id: "selected", rights: rights(redistributionAllowed: false))
        let other = ActiveSkinRecord(id: "other", version: "1.0.0")
        let ready = inspection(signatureValid: true)

        let actions = SkinActionAvailability(
            selected: selected,
            active: other,
            inspection: ready,
            state: .idle
        )

        XCTAssertTrue(actions.canApply)
        XCTAssertEqual(actions.applyTitle, "切换到此皮肤")
        XCTAssertTrue(actions.canRestore)
        XCTAssertTrue(actions.canDelete)
        XCTAssertFalse(actions.canExport)
        XCTAssertTrue(actions.canImport)
        XCTAssertEqual(actions.exportDisabledReason, "当前素材授权不允许导出共享")

        let activeActions = SkinActionAvailability(
            selected: selected,
            active: ActiveSkinRecord(id: selected.id, version: selected.version),
            inspection: ready,
            state: .active(ActiveSkinRecord(id: selected.id, version: selected.version))
        )
        XCTAssertTrue(activeActions.canApply)
        XCTAssertEqual(activeActions.applyTitle, "重新应用")
        XCTAssertNil(activeActions.applyDisabledReason)
        XCTAssertFalse(activeActions.canDelete)

        let retryActions = SkinActionAvailability(
            selected: selected,
            active: other,
            inspection: ready,
            state: .failed("注入失败")
        )
        XCTAssertTrue(retryActions.canApply)
        XCTAssertEqual(retryActions.applyTitle, "重试切换")
    }

    func testBusyAndSignatureFailureDisableApplyButNeverImport() {
        let selected = installed(id: "selected", rights: rights(redistributionAllowed: true))
        let blocked = inspection(signatureValid: false)
        let signatureActions = SkinActionAvailability(
            selected: selected,
            active: nil,
            inspection: blocked,
            state: .idle
        )
        XCTAssertFalse(signatureActions.canApply)
        XCTAssertTrue(signatureActions.canImport)
        XCTAssertNotNil(signatureActions.applyDisabledReason)

        let busy = SkinActionAvailability(
            selected: selected,
            active: nil,
            inspection: inspection(signatureValid: true),
            state: .applying(ActiveSkinRecord(id: selected.id, version: selected.version))
        )
        XCTAssertFalse(busy.canApply)
        XCTAssertFalse(busy.canDelete)
        XCTAssertFalse(busy.canExport)
    }

    func testEveryControllerStateHasUserFacingProgressCopy() {
        let active = ActiveSkinRecord(id: "skin", version: "1.0.0")
        let states: [SkinApplicationState] = [
            .idle, .checking, .waitingForQuit, .startingCodex, .applying(active),
            .active(active), .restoring, .cancelled, .failed("boom"),
        ]
        let presentations = states.map { SkinStatePresentation($0) }
        XCTAssertEqual(presentations.count, 9)
        XCTAssertTrue(presentations.allSatisfy { !$0.title.isEmpty && !$0.detail.isEmpty })
        XCTAssertTrue(SkinStatePresentation(.waitingForQuit).detail.contains("⌘Q"))
        XCTAssertTrue(SkinStatePresentation(.failed("boom")).detail.contains("boom"))
        XCTAssertTrue(presentations.allSatisfy { !$0.systemImage.isEmpty })
    }

    func testStatePresentationSeparatesLastUsedRecordFromVerifiedRuntimeState() {
        let record = ActiveSkinRecord(id: "meng-chuan-nightblade", version: "1.0.0")
        let displayName = "孟川 · 玄刃夜行"

        let recorded = SkinStatePresentation(.idle, activeDisplayName: displayName)
        XCTAssertEqual(recorded.title, "上次使用记录")
        XCTAssertTrue(recorded.detail.contains(displayName))
        XCTAssertTrue(recorded.detail.contains("\n"))
        XCTAssertFalse(recorded.title.contains("生效"))

        let verified = SkinStatePresentation(.active(record), activeDisplayName: displayName)
        XCTAssertEqual(verified.title, "皮肤已验证生效")
        XCTAssertTrue(verified.detail.contains(displayName))
        XCTAssertFalse(verified.detail.contains(record.id))
        XCTAssertEqual(verified.systemImage, "checkmark.seal.fill")
    }

    func testInspectionBannerSurfacesSignatureFailure() {
        let banner = CodexInspectionPresentation(inspection(signatureValid: false)).blockingBanner
        XCTAssertNotNil(banner)
        XCTAssertTrue(banner?.contains("签名") == true)
        XCTAssertNil(CodexInspectionPresentation(inspection(signatureValid: true)).blockingBanner)
    }

    func testCardPreservesLongNamesAndAuthorsForSwiftUITextLayout() {
        let longName = String(repeating: "孟川玄刃夜行", count: 30)
        let longAuthor = String(repeating: "作者", count: 80)
        let skin = installed(id: "long", name: longName, author: longAuthor, rights: rights(redistributionAllowed: false))

        let card = SkinCardPresentation(skin)

        XCTAssertEqual(card.name, longName)
        XCTAssertEqual(card.author, longAuthor)
        XCTAssertEqual(card.privateExportMessage, "仅供本机预览与使用，不可导出共享")
    }

    private func inspection(signatureValid: Bool) -> CodexAppInspection {
        let app = URL(fileURLWithPath: "/Applications/ChatGPT.app")
        return CodexAppInspection(
            appURL: app,
            executableURL: app.appending(path: "Contents/MacOS/ChatGPT"),
            nodeURL: app.appending(path: "Contents/Resources/cua_node/bin/node"),
            signatureValid: signatureValid,
            portStatus: .available,
            issues: signatureValid ? [] : [CodexAppIssue(code: .invalidSignature, detail: "代码签名校验失败")]
        )
    }

    private func installed(
        id: String,
        name: String = "Skin",
        author: String = "Author",
        version: String = "1.0.0",
        rights: SkinRights
    ) -> InstalledSkin {
        let manifest = SkinManifest(
            schemaVersion: 1,
            id: id,
            name: name,
            version: version,
            template: "nightblade-v1",
            minManagerVersion: "1.0.0",
            preview: "preview.png",
            files: [
                SkinFile(path: "preview.png", byteCount: 1, sha256: String(repeating: "a", count: 64), mime: "image/png"),
                SkinFile(path: "theme.json", byteCount: 1, sha256: String(repeating: "b", count: 64), mime: "application/json"),
                SkinFile(path: "rights.json", byteCount: 1, sha256: String(repeating: "c", count: 64), mime: "application/json"),
            ],
            author: SkinAuthor(name: author)
        )
        return InstalledSkin(
            manifest: manifest,
            rights: rights,
            trust: .unsigned,
            directoryURL: URL(fileURLWithPath: "/tmp/\(id)")
        )
    }

    private func rights(redistributionAllowed: Bool) -> SkinRights {
        SkinRights(
            redistributionAllowed: redistributionAllowed,
            commercialUse: false,
            fanMade: true,
            unofficial: true,
            noEndorsement: true,
            notice: "Fan-made"
        )
    }
}
