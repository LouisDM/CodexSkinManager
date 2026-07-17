import AppKit
import SkinCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var dropTargeted = false
    @State private var isDetailPresented = true

    var body: some View {
        workspace
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 980, minHeight: 640)
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ToolbarItem {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isDetailPresented.toggle()
                    }
                } label: {
                    Label(detailVisibility.title, systemImage: detailVisibility.systemImage)
                }
                .help(detailVisibility.title)
                .keyboardShortcut("i", modifiers: [.command, .option])
                .accessibilityIdentifier("toggle-skin-detail")
            }
        }
        .overlay {
            if model.isBootstrapping {
                ZStack {
                    Color.black.opacity(0.18).ignoresSafeArea()
                    VStack(spacing: 14) {
                        ProgressView()
                            .controlSize(.large)
                        Text("正在验证并载入皮肤库…")
                            .font(.headline)
                    }
                    .padding(26)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 7]))
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                    .padding(16)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: { $0.pathExtension.lowercased() == "codexskin" }) else { return false }
            Task { await model.importSkin(from: url) }
            return true
        } isTargeted: { dropTargeted = $0 }
        .onAppear { model.markWindowVisibleForTests() }
        .alert("Codex 皮肤管理器", isPresented: Binding(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil } }
        )) {
            Button("好", role: .cancel) { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "")
        }
    }

    private var workspace: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 260)
        } detail: {
            HSplitView {
                SkinLibraryView()
                    .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                if isDetailPresented {
                    SkinDetailView()
                        .frame(
                            minWidth: SkinDetailLayout.minimumPaneWidth,
                            idealWidth: SkinDetailLayout.idealPaneWidth,
                            maxWidth: SkinDetailLayout.maximumPaneWidth,
                            maxHeight: .infinity
                        )
                }
            }
        }
    }

    private var detailVisibility: SkinDetailVisibilityPresentation {
        SkinDetailVisibilityPresentation(isPresented: isDetailPresented)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(SkinLibraryFilter.allCases, selection: $model.filter) { filter in
                Label(filter.title, systemImage: filter.systemImage)
                    .tag(filter)
            }
            .listStyle(.sidebar)

            VStack(alignment: .leading, spacing: 12) {
                Divider()
                Label(model.inspectionPresentation.statusLabel, systemImage: model.inspection?.canApply == true ? "checkmark.shield" : "exclamationmark.triangle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(model.inspection?.canApply == true ? Color.green : Color.orange)
                    .lineLimit(2)
                Button {
                    presentImportPanel()
                } label: {
                    Label("导入 .codexskin", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.actions.canImport)
                .accessibilityHint("选择或拖入受限的 Codex 皮肤包")
            }
            .padding(14)
        }
        .navigationTitle("皮肤资料库")
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
