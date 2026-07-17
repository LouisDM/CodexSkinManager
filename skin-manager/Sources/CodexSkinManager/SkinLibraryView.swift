import AppKit
import SkinCore
import SwiftUI

struct SkinLibraryView: View {
    @EnvironmentObject private var model: AppModel
    private let columns = [GridItem(.adaptive(minimum: 210, maximum: 310), spacing: 16)]

    var body: some View {
        ScrollView {
            if model.filteredSkins.isEmpty {
                EmptyLibraryState(
                    title: "此分类没有皮肤",
                    detail: "可从侧栏切换分类，或导入一个 .codexskin 文件。",
                    image: "paintpalette"
                )
                .frame(maxWidth: .infinity, minHeight: 420)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    ForEach(model.filteredSkins, id: \.directoryURL) { skin in
                        SkinCard(
                            skin: skin,
                            isSelected: model.selection == SkinSelection(skin),
                            activityLabel: model.activityLabel(for: skin)
                        ) {
                            model.selection = SkinSelection(skin)
                        }
                    }
                }
                .padding(18)
            }
        }
        .navigationTitle(model.filter.title)
        .toolbar {
            ToolbarItem {
                Button {
                    Task {
                        do { try await model.refreshLibrary() }
                        catch { model.alertMessage = "刷新失败：\(error.localizedDescription)" }
                    }
                } label: {
                    Label("刷新资料库", systemImage: "arrow.clockwise")
                }
            }
        }
    }
}

struct EmptyLibraryState: View {
    let title: String
    let detail: String
    let image: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: image)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text(title).font(.title3.weight(.semibold))
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
    }
}

private struct SkinCard: View {
    let skin: InstalledSkin
    let isSelected: Bool
    let activityLabel: String?
    let action: () -> Void

    private var card: SkinCardPresentation { SkinCardPresentation(skin) }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                SkinPreviewImage(url: skin.previewURL)
                    .frame(height: 132)
                    .overlay(alignment: .topLeading) {
                        if let activityLabel {
                            Label(
                                activityLabel,
                                systemImage: activityLabel == "已验证生效"
                                    ? "checkmark.seal.fill"
                                    : "clock.arrow.circlepath"
                            )
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .background(.ultraThickMaterial, in: Capsule())
                                .padding(10)
                        }
                    }
                    .clipped()

                VStack(alignment: .leading, spacing: 9) {
                    Text(card.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text("\(card.author) · v\(card.version)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        CompactBadge(label: card.trust.label, image: card.trust.systemImage)
                        CompactBadge(label: card.rights.label, image: card.rights.systemImage)
                    }
                }
                .padding(13)
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.10), lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(card.name)，作者 \(card.author)，\(card.rights.label)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct SkinPreviewImage: View {
    let url: URL

    var body: some View {
        Group {
            if let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    LinearGradient(
                        colors: [Color(nsColor: .darkGray), Color(nsColor: .black)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

struct CompactBadge: View {
    let label: String
    let image: String

    var body: some View {
        Label(label, systemImage: image)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.07), in: Capsule())
    }
}
