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
        return ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let banner = model.inspectionPresentation.blockingBanner {
                    SafetyBanner(
                        title: "应用功能已安全阻止",
                        message: banner,
                        image: "exclamationmark.triangle.fill",
                        color: .orange
                    )
                }

                SkinPreviewImage(url: skin.previewURL)
                    .aspectRatio(16 / 10, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    }

                VStack(alignment: .leading, spacing: 7) {
                    Text(card.name)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .textSelection(.enabled)
                    Text("作者：\(card.author)  ·  版本 \(card.version)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                HStack(spacing: 10) {
                    DetailBadge(title: trust.label, detail: trust.detail, image: trust.systemImage)
                    DetailBadge(title: rights.label, detail: rights.detail, image: rights.systemImage)
                }

                if let message = card.privateExportMessage {
                    SafetyBanner(title: "素材权利限制", message: message, image: "lock.shield.fill", color: .yellow)
                }

                statusPanel
                actionBar

                Divider()
                LabeledContent("皮肤 ID", value: skin.id)
                    .textSelection(.enabled)
                LabeledContent("模板", value: skin.template)
                LabeledContent("安装位置", value: skin.directoryURL.path)
                    .textSelection(.enabled)
                    .lineLimit(3)
            }
            .padding(24)
        }
    }

    private var statusPanel: some View {
        HStack(alignment: .top, spacing: 12) {
            if model.statePresentation.showsProgress {
                ProgressView().controlSize(.small).padding(.top, 2)
            } else {
                Image(systemName: model.statePresentation.systemImage)
                    .foregroundStyle(model.statePresentation.isError ? Color.red : Color.secondary)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(model.statePresentation.title).font(.headline)
                Text(model.statePresentation.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
            if model.actions.canCancelWaiting {
                Button("取消") { Task { await model.cancelWaiting() } }
            } else if model.statePresentation.isError {
                Button("查看日志") { model.revealLog() }
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button {
                Task { await model.applySelected() }
            } label: {
                Label(model.actions.applyTitle, systemImage: "paintbrush.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!model.actions.canApply)
            .help(model.actions.applyDisabledReason ?? "安全应用所选皮肤")

            Button {
                Task { await model.restoreDefault() }
            } label: {
                Label("恢复默认", systemImage: "arrow.uturn.backward")
            }
            .controlSize(.large)
            .disabled(!model.actions.canRestore)

            Spacer()

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

private struct DetailBadge: View {
    let title: String
    let detail: String
    let image: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: image).font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct SafetyBanner: View {
    let title: String
    let message: String
    let image: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: image).foregroundStyle(color).font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.25), lineWidth: 1)
        }
    }
}
