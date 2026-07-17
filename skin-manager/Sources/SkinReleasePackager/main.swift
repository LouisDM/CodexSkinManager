import Foundation
import SkinCore

private enum PackagerError: Error, LocalizedError {
    case invalidArguments

    var errorDescription: String? {
        switch self {
        case .invalidArguments:
            "用法：SkinReleasePackager --source <内置皮肤目录> --output <输出.codexskin>"
        }
    }
}

@main
private struct SkinReleasePackager {
    static func main() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 4,
              arguments[0] == "--source",
              arguments[2] == "--output"
        else {
            throw PackagerError.invalidArguments
        }

        let sourceURL = URL(fileURLWithPath: arguments[1], isDirectory: true).standardizedFileURL
        let outputURL = URL(fileURLWithPath: arguments[3]).standardizedFileURL
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: "codex-skin-release-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let imported = try SkinPackageImporter().importBundledPackage(at: sourceURL)
        let repository = SkinRepository(rootURL: temporaryRoot)
        _ = try await repository.install(imported)
        let stored = try await repository.load(id: imported.manifest.id, version: imported.manifest.version)
        try SkinPackageExporter().export(stored, to: outputURL)
        print(outputURL.path)
    }
}
