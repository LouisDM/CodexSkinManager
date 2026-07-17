import AppKit
import SkinCore
import SwiftUI

enum SkinLibraryLayoutMode: String {
    case navigator
    case gallery
}

struct SkinLibraryView: View {
    @EnvironmentObject private var model: AppModel

    let layout: SkinLibraryLayoutMode

    private let columns = [GridItem(.adaptive(minimum: 230, maximum: 330), spacing: 16)]

    private var summary: SkinLibrarySummaryPresentation {
        SkinLibrarySummaryPresentation(
            filter: model.filter,
            visibleCount: model.filteredSkins.count,
            totalCount: model.skins.count
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            libraryHeader
            Divider()
            libraryContent
            Divider()
            libraryFooter
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("skin-library-\(layout.rawValue)")
    }

    private var libraryHeader: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.title)
                    .font(layout == .navigator ? .headline : .title2.weight(.bold))
                    .lineLimit(1)
                Text(summary.countLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .layoutPriority(1)

            Spacer(minLength: 4)
            filterMenu
            refreshButton
        }
        .padding(.horizontal, layout == .navigator ? 14 : 18)
        .padding(.vertical, 12)
    }

    private var filterMenu: some View {
        Menu {
            Picker("筛选皮肤", selection: $model.filter) {
                ForEach(SkinLibraryFilter.allCases) { filter in
                    Label(filter.title, systemImage: filter.systemImage)
                        .tag(filter)
                }
            }
        } label: {
            filterMenuLabel
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("筛选皮肤，当前：\(model.filter.title)")
        .accessibilityLabel("筛选皮肤，当前\(model.filter.title)")
        .accessibilityIdentifier("skin-filter-menu")
    }

    @ViewBuilder
    private var filterMenuLabel: some View {
        if layout == .navigator {
            Image(systemName: model.filter == .all
                ? "line.3.horizontal.decrease.circle"
                : "line.3.horizontal.decrease.circle.fill")
                .font(.title3)
        } else {
            Label(model.filter.title, systemImage: "line.3.horizontal.decrease.circle")
        }
    }

    private var refreshButton: some View {
        Button {
            Task {
                do { try await model.refreshLibrary() }
                catch { model.alertMessage = "刷新失败：\(error.localizedDescription)" }
            }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.title3)
        }
        .buttonStyle(.borderless)
        .help("刷新资料库")
        .accessibilityLabel("刷新资料库")
        .accessibilityIdentifier("refresh-skin-library")
    }

    @ViewBuilder
    private var libraryContent: some View {
        if model.filteredSkins.isEmpty {
            EmptyLibraryState(
                title: "没有符合条件的皮肤",
                detail: "请调整上方筛选条件，或导入一个 .codexskin 文件。",
                image: "paintpalette"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if layout == .navigator {
            navigatorList
        } else {
            galleryGrid
        }
    }

    private var navigatorList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(model.filteredSkins, id: \.directoryURL) { skin in
                    SkinNavigatorRow(
                        skin: skin,
                        isSelected: model.selection == SkinSelection(skin),
                        activityLabel: model.activityLabel(for: skin)
                    ) {
                        model.selection = SkinSelection(skin)
                    }
                }
            }
            .padding(10)
        }
    }

    private var galleryGrid: some View {
        ScrollView {
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

    private var libraryFooter: some View {
        Label(
            model.inspectionPresentation.statusLabel,
            systemImage: model.inspection?.canApply == true
                ? "checkmark.shield.fill"
                : "exclamationmark.triangle.fill"
        )
        .font(.caption.weight(.semibold))
        .foregroundStyle(model.inspection?.canApply == true ? Color.green : Color.orange)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(layout == .navigator ? 12 : 14)
        .background(Color.primary.opacity(0.025))
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

private struct SkinNavigatorRow: View {
    @State private var isHovering = false

    let skin: InstalledSkin
    let isSelected: Bool
    let activityLabel: String?
    let action: () -> Void

    private var item: SkinNavigatorItemPresentation {
        SkinNavigatorItemPresentation(skin, activityLabel: activityLabel)
    }

    private var activityImage: String {
        activityLabel == "已验证生效" ? "checkmark.seal.fill" : "clock.arrow.circlepath"
    }

    private var activityColor: Color {
        activityLabel == "已验证生效" ? .green : .secondary
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                SkinPreviewImage(url: skin.previewURL)
                    .frame(width: 104, height: 66)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                    }

                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(item.metadata)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    HStack(spacing: 7) {
                        Label(item.rightsLabel, systemImage: item.rightsSystemImage)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if let activityLabel {
                            Label(activityLabel, systemImage: activityImage)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(activityColor)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isSelected {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(9)
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.13)
                    : Color.primary.opacity(isHovering ? 0.065 : 0.035)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isSelected ? Color.accentColor.opacity(0.80) : Color.primary.opacity(0.08),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
            .overlay(alignment: .leading) {
                if isSelected {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: 3, height: 36)
                        .padding(.leading, 3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .animation(.easeOut(duration: 0.12), value: isSelected)
        .accessibilityLabel(item.accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
                    .frame(height: 150)
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
                    .stroke(
                        isSelected ? Color.accentColor : Color.primary.opacity(0.10),
                        lineWidth: isSelected ? 2 : 1
                    )
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
