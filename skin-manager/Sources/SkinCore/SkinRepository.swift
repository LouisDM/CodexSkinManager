import CryptoKit
import Foundation

public struct InstalledSkin: Equatable, Sendable, Identifiable {
    public var id: String { manifest.id }
    public var name: String { manifest.name }
    public var version: String { manifest.version }
    public var template: String { manifest.template }
    public var author: SkinAuthor { manifest.author }
    public var previewURL: URL { directoryURL.appending(path: manifest.preview) }

    public let manifest: SkinManifest
    public let rights: SkinRights
    public let trust: SkinTrustState
    public let directoryURL: URL

    public init(
        manifest: SkinManifest,
        rights: SkinRights,
        trust: SkinTrustState,
        directoryURL: URL
    ) {
        self.manifest = manifest
        self.rights = rights
        self.trust = trust
        self.directoryURL = directoryURL
    }
}

public struct StoredSkinPackage: Sendable {
    public let installed: InstalledSkin
    public let manifest: SkinManifest
    public let theme: SkinTheme
    public let rights: SkinRights
    public let trust: SkinTrustState
    public let files: [String: Data]

    public init(
        installed: InstalledSkin,
        manifest: SkinManifest,
        theme: SkinTheme,
        rights: SkinRights,
        trust: SkinTrustState,
        files: [String: Data]
    ) {
        self.installed = installed
        self.manifest = manifest
        self.theme = theme
        self.rights = rights
        self.trust = trust
        self.files = files
    }
}

public enum SkinInstallOutcome: Equatable, Sendable {
    case installed(InstalledSkin)
    case alreadyInstalled(InstalledSkin)
}

public struct ActiveSkinRecord: Codable, Equatable, Sendable {
    public let id: String
    public let version: String

    public init(id: String, version: String) {
        self.id = id
        self.version = version
    }
}

public enum SkinRepositoryError: Error, Equatable, LocalizedError, Sendable {
    case versionConflict(id: String, version: String)
    case notInstalled(id: String, version: String)
    case cannotDeleteActiveSkin
    case invalidReference
    case corruptedInstallation(String)

    public var errorDescription: String? {
        switch self {
        case let .versionConflict(id, version): "已存在内容不同的同版本皮肤：\(id) \(version)"
        case let .notInstalled(id, version): "皮肤未安装：\(id) \(version)"
        case .cannotDeleteActiveSkin: "不能删除当前正在使用的皮肤"
        case .invalidReference: "皮肤 ID 或版本引用无效"
        case let .corruptedInstallation(path): "已安装皮肤文件损坏：\(path)"
        }
    }
}

public actor SkinRepository {
    public static var defaultRootURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/CodexSkinManager", directoryHint: .isDirectory)
    }

    private let rootURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    private var skinsURL: URL { rootURL.appending(path: "skins", directoryHint: .isDirectory) }
    private var stagingURL: URL { rootURL.appending(path: ".staging", directoryHint: .isDirectory) }
    private var activeURL: URL { rootURL.appending(path: "active.json") }

    public init(rootURL: URL = SkinRepository.defaultRootURL, fileManager: FileManager = .default) {
        self.rootURL = rootURL.standardizedFileURL
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    }

    public func install(_ package: ImportedSkinPackage) throws -> SkinInstallOutcome {
        try prepare(cleanStaging: true)
        let destination = skinDirectory(id: package.manifest.id, version: package.manifest.version)
        let originalHash = Self.sha256(package.originalManifestData)
        if fileManager.fileExists(atPath: destination.path) {
            let receipt = try readReceipt(at: destination)
            guard receipt.originalManifestSHA256 == originalHash else {
                throw SkinRepositoryError.versionConflict(id: package.manifest.id, version: package.manifest.version)
            }
            return .alreadyInstalled(try loadInstalled(at: destination))
        }

        let stage = stagingURL.appending(path: "import-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: stage, withIntermediateDirectories: false)
        defer { try? fileManager.removeItem(at: stage) }

        try package.originalManifestData.write(to: stage.appending(path: "manifest.json"), options: .atomic)
        var storedDescriptors: [SkinFile] = []
        let originalDescriptors = Dictionary(uniqueKeysWithValues: package.manifest.files.map { ($0.path, $0) })
        for path in package.files.keys.sorted() {
            guard let contents = package.files[path], let original = originalDescriptors[path] else {
                throw SkinRepositoryError.corruptedInstallation(path)
            }
            try SkinPackageContract.validateRelativePath(path)
            let destinationFile = stage.appending(path: path)
            try fileManager.createDirectory(at: destinationFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: destinationFile, options: .atomic)
            storedDescriptors.append(SkinFile(
                path: path,
                byteCount: Int64(contents.count),
                sha256: Self.sha256(contents),
                mime: original.mime
            ))
        }
        if let signature = package.signature {
            try signature.write(to: stage.appending(path: "signature.ed25519"), options: .atomic)
        }
        let trustRecord = TrustRecord(package.trust)
        let receipt = InstallationReceipt(
            schemaVersion: 1,
            originalManifestSHA256: originalHash,
            files: storedDescriptors,
            trust: trustRecord
        )
        try encoder.encode(receipt).write(to: stage.appending(path: "installation.json"), options: .atomic)

        let parent = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        do {
            try fileManager.moveItem(at: stage, to: destination)
        } catch {
            throw error
        }
        return .installed(try loadInstalled(at: destination))
    }

    public func listInstalled() throws -> [InstalledSkin] {
        try prepare(cleanStaging: true)
        let idDirectories = try childDirectories(at: skinsURL)
        var installed: [InstalledSkin] = []
        for idDirectory in idDirectories {
            for versionDirectory in try childDirectories(at: idDirectory) {
                installed.append(try loadInstalled(at: versionDirectory))
            }
        }
        return installed.sorted {
            let comparison = $0.name.localizedStandardCompare($1.name)
            if comparison == .orderedSame { return $0.version < $1.version }
            return comparison == .orderedAscending
        }
    }

    public func load(id: String, version: String) throws -> StoredSkinPackage {
        try validateReference(id: id, version: version)
        try prepare(cleanStaging: false)
        let directory = skinDirectory(id: id, version: version)
        guard fileManager.fileExists(atPath: directory.path) else {
            throw SkinRepositoryError.notInstalled(id: id, version: version)
        }
        let receipt = try readReceipt(at: directory)
        let manifestData = try verifiedData(at: directory.appending(path: "manifest.json"), descriptor: nil)
        let manifest: SkinManifest
        do {
            manifest = try decoder.decode(SkinManifest.self, from: manifestData)
            try SkinPackageContract.validate(manifest: manifest)
        } catch {
            throw SkinRepositoryError.corruptedInstallation("manifest.json")
        }
        var files: [String: Data] = [:]
        for descriptor in receipt.files {
            files[descriptor.path] = try verifiedData(at: directory.appending(path: descriptor.path), descriptor: descriptor)
        }
        guard let themeData = files["theme.json"], let rightsData = files["rights.json"],
              let theme = try? decoder.decode(SkinTheme.self, from: themeData),
              let rights = try? decoder.decode(SkinRights.self, from: rightsData)
        else {
            throw SkinRepositoryError.corruptedInstallation(directory.path)
        }
        let trust = receipt.trust.value
        let installed = InstalledSkin(manifest: manifest, rights: rights, trust: trust, directoryURL: directory)
        return StoredSkinPackage(
            installed: installed,
            manifest: manifest,
            theme: theme,
            rights: rights,
            trust: trust,
            files: files
        )
    }

    public func setActive(id: String, version: String) throws {
        _ = try load(id: id, version: version)
        try writeAtomically(encoder.encode(ActiveSkinRecord(id: id, version: version)), to: activeURL)
    }

    public func activeSkin() throws -> ActiveSkinRecord? {
        try prepare(cleanStaging: false)
        guard fileManager.fileExists(atPath: activeURL.path) else { return nil }
        do {
            return try decoder.decode(ActiveSkinRecord.self, from: Data(contentsOf: activeURL))
        } catch {
            throw SkinRepositoryError.corruptedInstallation("active.json")
        }
    }

    public func clearActive() throws {
        if fileManager.fileExists(atPath: activeURL.path) {
            try fileManager.removeItem(at: activeURL)
        }
    }

    public func delete(id: String, version: String) throws {
        try validateReference(id: id, version: version)
        if try activeSkin() == ActiveSkinRecord(id: id, version: version) {
            throw SkinRepositoryError.cannotDeleteActiveSkin
        }
        let directory = skinDirectory(id: id, version: version)
        guard fileManager.fileExists(atPath: directory.path) else {
            throw SkinRepositoryError.notInstalled(id: id, version: version)
        }
        try fileManager.removeItem(at: directory)
        let parent = directory.deletingLastPathComponent()
        if (try? fileManager.contentsOfDirectory(atPath: parent.path).isEmpty) == true {
            try? fileManager.removeItem(at: parent)
        }
    }

    private func prepare(cleanStaging: Bool) throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: skinsURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        if cleanStaging {
            for child in try fileManager.contentsOfDirectory(at: stagingURL, includingPropertiesForKeys: nil) {
                try fileManager.removeItem(at: child)
            }
        }
    }

    private func loadInstalled(at directory: URL) throws -> InstalledSkin {
        let receipt = try readReceipt(at: directory)
        let manifestData = try Data(contentsOf: directory.appending(path: "manifest.json"))
        guard Self.sha256(manifestData) == receipt.originalManifestSHA256 else {
            throw SkinRepositoryError.corruptedInstallation("manifest.json")
        }
        let manifest: SkinManifest
        do {
            manifest = try decoder.decode(SkinManifest.self, from: manifestData)
        } catch {
            throw SkinRepositoryError.corruptedInstallation("manifest.json")
        }
        var verifiedFiles: [String: Data] = [:]
        for descriptor in receipt.files {
            verifiedFiles[descriptor.path] = try verifiedData(
                at: directory.appending(path: descriptor.path),
                descriptor: descriptor
            )
        }
        guard let rightsData = verifiedFiles["rights.json"] else {
            throw SkinRepositoryError.corruptedInstallation("rights.json")
        }
        guard let rights = try? decoder.decode(SkinRights.self, from: rightsData) else {
            throw SkinRepositoryError.corruptedInstallation("rights.json")
        }
        return InstalledSkin(manifest: manifest, rights: rights, trust: receipt.trust.value, directoryURL: directory)
    }

    private func readReceipt(at directory: URL) throws -> InstallationReceipt {
        do {
            return try decoder.decode(InstallationReceipt.self, from: Data(contentsOf: directory.appending(path: "installation.json")))
        } catch {
            throw SkinRepositoryError.corruptedInstallation(directory.path)
        }
    }

    private func verifiedData(at url: URL, descriptor: SkinFile?) throws -> Data {
        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw SkinRepositoryError.corruptedInstallation(url.path)
        }
        if let descriptor,
           (data.count != descriptor.byteCount || Self.sha256(data) != descriptor.sha256)
        {
            throw SkinRepositoryError.corruptedInstallation(descriptor.path)
        }
        return data
    }

    private func childDirectories(at url: URL) throws -> [URL] {
        try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ).filter { child in
            guard let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return false }
            return values.isDirectory == true && values.isSymbolicLink != true
        }
    }

    private func skinDirectory(id: String, version: String) -> URL {
        skinsURL.appending(path: id, directoryHint: .isDirectory)
            .appending(path: version, directoryHint: .isDirectory)
    }

    private func validateReference(id: String, version: String) throws {
        do {
            try SkinPackageContract.validateReference(id: id, version: version)
        } catch {
            throw SkinRepositoryError.invalidReference
        }
    }

    private func writeAtomically(_ data: Data, to destination: URL) throws {
        let temporary = destination.deletingLastPathComponent()
            .appending(path: ".\(destination.lastPathComponent).tmp-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: temporary) }
        try data.write(to: temporary, options: .atomic)
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: destination)
        }
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private struct InstallationReceipt: Codable {
    let schemaVersion: Int
    let originalManifestSHA256: String
    let files: [SkinFile]
    let trust: TrustRecord
}

private struct TrustRecord: Codable {
    enum Kind: String, Codable { case verified, unknown, unsigned }

    let kind: Kind
    let fingerprint: String?

    init(_ trust: SkinTrustState) {
        switch trust {
        case let .verifiedPublisher(fingerprint):
            kind = .verified
            self.fingerprint = fingerprint
        case let .signedUnknownPublisher(fingerprint):
            kind = .unknown
            self.fingerprint = fingerprint
        case .unsigned:
            kind = .unsigned
            fingerprint = nil
        }
    }

    var value: SkinTrustState {
        switch kind {
        case .verified: .verifiedPublisher(fingerprint: fingerprint ?? "")
        case .unknown: .signedUnknownPublisher(fingerprint: fingerprint ?? "")
        case .unsigned: .unsigned
        }
    }
}
