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

    @ViewBuilder
    private var workspace: some View {
        if isDetailPresented {
            HSplitView {
                SkinLibraryView(layout: .navigator, onImport: presentImportPanel)
                    .frame(minWidth: 300, idealWidth: 340, maxWidth: 410, maxHeight: .infinity)
                SkinDetailView()
                    .frame(minWidth: 500, idealWidth: 760, maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            SkinLibraryView(layout: .gallery, onImport: presentImportPanel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var detailVisibility: SkinDetailVisibilityPresentation {
        SkinDetailVisibilityPresentation(isPresented: isDetailPresented)
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
