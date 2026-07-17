import AppKit
import SkinCore
import SwiftUI
import UniformTypeIdentifiers

struct SkinDetailView: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirmsDelete = false

    var body: some View {
        Group {
            if let skin = model.selectedSkin {
                detail(for: skin)
            } else {
                EmptyLibraryState(
                    title: "选择一个皮肤",
                    detail: "这里会显示预览、来源、安全状态与可用操作。",
                    image: "sidebar.right"
                )
            }
        }
        .navigationTitle(model.selectedSkin?.name ?? "皮肤详情")
        .confirmationDialog("确定删除此皮肤？", isPresented: $confirmsDelete) {
            Button("删除", role: .destructive) { Task { await model.deleteSelected() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只会删除管理器资料库中的副本，不会修改官方 Codex。")
        }
    }

    private func detail(for skin: InstalledSkin) -> some View {
        let card = SkinCardPresentation(skin)
        let trust = SkinTrustPresentation(skin.trust)
        let rights = SkinRightsPresentation(skin.rights)
        return ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 22) {
                if let banner = model.inspectionPresentation.blockingBanner {
                    SafetyBanner(
                        title: "应用功能已安全阻止",
                        message: banner,
                        image: "exclamationmark.triangle.fill",
                        color: .orange
                    )
                }

                SkinDetailPreview(url: skin.previewURL)

                VStack(alignment: .leading, spacing: 7) {
                    Text(card.name)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .lineLimit(3)
                    Text("作者：\(card.author)  ·  版本 \(card.version)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                LazyVGrid(
                    columns: [
                        GridItem(
                            .adaptive(minimum: SkinDetailLayout.badgeMinimumWidth),
                            spacing: 10,
                            alignment: .top
                        ),
                    ],
                    alignment: .leading,
                    spacing: 10
                ) {
                    DetailBadge(title: trust.label, detail: trust.detail, image: trust.systemImage)
                    DetailBadge(title: rights.label, detail: rights.detail, image: rights.systemImage)
                }

                if let message = card.privateExportMessage {
                    SafetyBanner(title: "素材权利限制", message: message, image: "lock.shield.fill", color: .yellow)
                }

                statusPanel
                actionBar

                Divider()
                VStack(alignment: .leading, spacing: 14) {
                    DetailMetadataRow(title: "皮肤 ID", value: skin.id)
                    DetailMetadataRow(title: "模板", value: skin.template)
                    DetailMetadataRow(title: "安装位置", value: skin.directoryURL.path)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusSummary
            statusAction
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var statusSummary: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                if model.statePresentation.showsProgress {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: model.statePresentation.systemImage)
                        .foregroundStyle(model.statePresentation.isError ? Color.red : Color.secondary)
                }
                Text(model.statePresentation.title)
                    .font(.headline)
                Spacer(minLength: 0)
            }
            Text(model.statePresentation.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
    }

    @ViewBuilder
    private var statusAction: some View {
        if model.actions.canCancelWaiting {
            Button("取消") { Task { await model.cancelWaiting() } }
        } else if model.statePresentation.isError {
            Button("查看日志") { model.revealLog() }
        }
    }

    private var actionBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                applyButton(expands: false)
                restoreButton(expands: false)
                Spacer(minLength: 8)
                moreActionsMenu
            }
            .fixedSize(horizontal: true, vertical: false)

            VStack(alignment: .leading, spacing: 10) {
                applyButton(expands: true)
                restoreButton(expands: true)
                HStack {
                    Text("更多操作")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    moreActionsMenu
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func applyButton(expands: Bool) -> some View {
        Button {
            Task { await model.applySelected() }
        } label: {
            Label(model.actions.applyTitle, systemImage: "paintbrush.fill")
                .frame(maxWidth: expands ? .infinity : nil)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!model.actions.canApply)
        .help(model.actions.applyDisabledReason ?? "安全应用所选皮肤")
    }

    private func restoreButton(expands: Bool) -> some View {
        Button {
            Task { await model.restoreDefault() }
        } label: {
            Label("恢复默认", systemImage: "arrow.uturn.backward")
                .frame(maxWidth: expands ? .infinity : nil)
        }
        .controlSize(.large)
        .disabled(!model.actions.canRestore)
    }

    private var moreActionsMenu: some View {
        Menu {
            Button("导出 .codexskin…") { presentExportPanel() }
                .disabled(!model.actions.canExport)
            Button("在 Finder 中显示") {
                if let skin = model.selectedSkin {
                    NSWorkspace.shared.activateFileViewerSelecting([skin.directoryURL])
                }
            }
            Divider()
            Button("删除皮肤…", role: .destructive) { confirmsDelete = true }
                .disabled(!model.actions.canDelete)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("更多皮肤操作")
    }

    private func presentExportPanel() {
        guard let skin = model.selectedSkin, model.actions.canExport else { return }
        let panel = NSSavePanel()
        panel.title = "导出 Codex 皮肤"
        panel.prompt = "导出"
        panel.nameFieldStringValue = "\(skin.id)-\(skin.version).codexskin"
        panel.allowedContentTypes = [UTType(filenameExtension: "codexskin") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await model.exportSelected(to: url) }
    }
}

private struct SkinDetailPreview: View {
    let url: URL

    var body: some View {
        Color.clear
            .aspectRatio(SkinDetailLayout.previewAspectRatio, contentMode: .fit)
            .overlay {
                SkinPreviewImage(url: url)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            }
    }
}

private struct DetailBadge: View {
    let title: String
    let detail: String
    let image: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: image)
                    .font(.title3)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct DetailMetadataRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.callout, design: .monospaced))
                .lineLimit(4)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SafetyBanner: View {
    let title: String
    let message: String
    let image: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: image)
                    .foregroundStyle(color)
                    .font(.title3)
                Text(title)
                    .font(.headline)
                Spacer(minLength: 0)
            }
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.25), lineWidth: 1)
        }
    }
}
