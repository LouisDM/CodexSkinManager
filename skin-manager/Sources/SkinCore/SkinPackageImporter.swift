import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum SkinTrustState: Equatable, Sendable {
    case verifiedPublisher(fingerprint: String)
    case signedUnknownPublisher(fingerprint: String)
    case unsigned
}

public struct ImportedSkinPackage: Sendable {
    public let manifest: SkinManifest
    public let theme: SkinTheme
    public let rights: SkinRights
    public let trust: SkinTrustState
    public let files: [String: Data]
    public let originalManifestData: Data
    public let signature: Data?

    public init(
        manifest: SkinManifest,
        theme: SkinTheme,
        rights: SkinRights,
        trust: SkinTrustState,
        files: [String: Data],
        originalManifestData: Data,
        signature: Data?
    ) {
        self.manifest = manifest
        self.theme = theme
        self.rights = rights
        self.trust = trust
        self.files = files
        self.originalManifestData = originalManifestData
        self.signature = signature
    }
}

public enum SkinImportError: Error, Equatable, LocalizedError, Sendable {
    case invalidManifest
    case invalidTheme
    case invalidRights
    case undeclaredFile(String)
    case missingDeclaredFile(String)
    case forbiddenFile(String)
    case fileSizeMismatch(String)
    case hashMismatch(String)
    case mimeMismatch(String)
    case missingLicense
    case missingAsset(String)
    case invalidImage(String)
    case imageDimensionsExceeded(String)
    case pixelBudgetExceeded
    case invalidSignature
    case unexpectedSignature

    public var errorDescription: String? {
        switch self {
        case .invalidManifest: "manifest.json 无效或包含未知字段"
        case .invalidTheme: "theme.json 无效或包含未知字段"
        case .invalidRights: "rights.json 无效或包含未知字段"
        case let .undeclaredFile(path): "皮肤包包含未声明文件：\(path)"
        case let .missingDeclaredFile(path): "皮肤包缺少已声明文件：\(path)"
        case let .forbiddenFile(path): "皮肤包包含禁止的文件类型：\(path)"
        case let .fileSizeMismatch(path): "文件大小与清单不符：\(path)"
        case let .hashMismatch(path): "文件哈希与清单不符：\(path)"
        case let .mimeMismatch(path): "文件类型与扩展名不符：\(path)"
        case .missingLicense: "皮肤包必须包含素材许可文件"
        case let .missingAsset(path): "主题引用了未声明素材：\(path)"
        case let .invalidImage(path): "无法安全解码图片：\(path)"
        case let .imageDimensionsExceeded(path): "图片尺寸超过限制：\(path)"
        case .pixelBudgetExceeded: "皮肤包图片总像素超过限制"
        case .invalidSignature: "发布者签名无效"
        case .unexpectedSignature: "未声明发布者公钥却携带签名"
        }
    }
}

public struct SkinPackageImporter: Sendable {
    public struct ImageLimits: Equatable, Sendable {
        public var maximumDimension: Int
        public var maximumTotalPixels: UInt64

        public static let `default` = ImageLimits(maximumDimension: 8_192, maximumTotalPixels: 80_000_000)

        public init(maximumDimension: Int, maximumTotalPixels: UInt64) {
            self.maximumDimension = maximumDimension
            self.maximumTotalPixels = maximumTotalPixels
        }
    }

    private let trustedPublisherKeys: Set<Data>
    private let archiveLimits: StoredZipArchive.Limits
    private let imageLimits: ImageLimits

    public init(
        trustedPublisherKeys: Set<Data> = [],
        archiveLimits: StoredZipArchive.Limits = .default,
        imageLimits: ImageLimits = .default
    ) {
        self.trustedPublisherKeys = trustedPublisherKeys
        self.archiveLimits = archiveLimits
        self.imageLimits = imageLimits
    }

    public func importPackage(data: Data) throws -> ImportedSkinPackage {
        let archive = try StoredZipArchive(data: data, limits: archiveLimits)
        let archivePaths = Set(archive.entries.map(\.path))
        let manifestData: Data
        do {
            manifestData = try archive.data(for: "manifest.json")
        } catch {
            throw SkinImportError.invalidManifest
        }
        guard Self.hasExactTopLevelKeys(
            manifestData,
            allowed: [
                "author", "files", "id", "minManagerVersion", "name", "preview", "publisherPublicKey",
                "schemaVersion", "template", "version",
            ]
        ) else {
            throw SkinImportError.invalidManifest
        }

        let manifest: SkinManifest
        do {
            manifest = try JSONDecoder().decode(SkinManifest.self, from: manifestData)
            try SkinPackageContract.validate(manifest: manifest)
        } catch let error as SkinContractError {
            throw error
        } catch {
            throw SkinImportError.invalidManifest
        }

        let hasSignature = archivePaths.contains("signature.ed25519")
        if manifest.publisherPublicKey == nil, hasSignature {
            throw SkinImportError.unexpectedSignature
        }
        if manifest.publisherPublicKey != nil, !hasSignature {
            throw SkinImportError.invalidSignature
        }

        var expectedPaths = Set(manifest.files.map(\.path))
        guard !expectedPaths.contains("manifest.json"), !expectedPaths.contains("signature.ed25519") else {
            throw SkinImportError.invalidManifest
        }
        expectedPaths.insert("manifest.json")
        if manifest.publisherPublicKey != nil {
            expectedPaths.insert("signature.ed25519")
        }
        for path in archivePaths where !expectedPaths.contains(path) {
            throw SkinImportError.undeclaredFile(path)
        }
        for path in expectedPaths where !archivePaths.contains(path) {
            throw SkinImportError.missingDeclaredFile(path)
        }

        var originalFiles: [String: Data] = [:]
        var descriptors: [String: SkinFile] = [:]
        for descriptor in manifest.files {
            guard Self.isAllowedDeclaredPath(descriptor.path) else {
                throw SkinImportError.forbiddenFile(descriptor.path)
            }
            guard Self.mimeMatchesPath(descriptor.mime, path: descriptor.path) else {
                throw SkinImportError.mimeMismatch(descriptor.path)
            }
            let fileData = try archive.data(for: descriptor.path)
            guard fileData.count == descriptor.byteCount else {
                throw SkinImportError.fileSizeMismatch(descriptor.path)
            }
            guard Self.sha256(fileData) == descriptor.sha256 else {
                throw SkinImportError.hashMismatch(descriptor.path)
            }
            originalFiles[descriptor.path] = fileData
            descriptors[descriptor.path] = descriptor
        }

        guard manifest.files.contains(where: {
            $0.path.hasPrefix("LICENSES/") && $0.path.lowercased().hasSuffix(".txt") && $0.mime == "text/plain"
        }) else {
            throw SkinImportError.missingLicense
        }

        guard let themeData = originalFiles["theme.json"],
              Self.hasExactTopLevelKeys(themeData, allowed: ["assets", "focalPoints", "tokens"])
        else {
            throw SkinImportError.invalidTheme
        }
        let theme: SkinTheme
        do {
            theme = try JSONDecoder().decode(SkinTheme.self, from: themeData)
            try SkinPackageContract.validate(theme: theme)
        } catch let error as SkinContractError {
            throw error
        } catch {
            throw SkinImportError.invalidTheme
        }

        guard let rightsData = originalFiles["rights.json"],
              Self.hasExactTopLevelKeys(
                  rightsData,
                  allowed: ["commercialUse", "fanMade", "noEndorsement", "notice", "redistributionAllowed", "unofficial"]
              ),
              let rights = try? JSONDecoder().decode(SkinRights.self, from: rightsData),
              !rights.notice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw SkinImportError.invalidRights
        }

        for path in theme.assets.values {
            guard let descriptor = descriptors[path], descriptor.mime == "image/png" || descriptor.mime == "image/jpeg" else {
                throw SkinImportError.missingAsset(path)
            }
        }
        guard let previewDescriptor = descriptors[manifest.preview],
              previewDescriptor.mime == "image/png" || previewDescriptor.mime == "image/jpeg"
        else {
            throw SkinImportError.mimeMismatch(manifest.preview)
        }

        var sanitizedFiles = originalFiles
        var totalPixels: UInt64 = 0
        for descriptor in manifest.files where descriptor.mime == "image/png" || descriptor.mime == "image/jpeg" {
            guard let original = originalFiles[descriptor.path] else {
                throw SkinImportError.missingDeclaredFile(descriptor.path)
            }
            let result = try sanitizeImage(original, mime: descriptor.mime, path: descriptor.path)
            let (newTotal, overflow) = totalPixels.addingReportingOverflow(result.pixels)
            guard !overflow, newTotal <= imageLimits.maximumTotalPixels else {
                throw SkinImportError.pixelBudgetExceeded
            }
            totalPixels = newTotal
            sanitizedFiles[descriptor.path] = result.data
        }

        let signature = hasSignature ? try archive.data(for: "signature.ed25519") : nil
        let trust = try verifyTrust(manifest: manifest, manifestData: manifestData, signature: signature)
        return ImportedSkinPackage(
            manifest: manifest,
            theme: theme,
            rights: rights,
            trust: trust,
            files: sanitizedFiles,
            originalManifestData: manifestData,
            signature: signature
        )
    }

    /// Imports a manager-owned package directory from the signed application bundle.
    /// The directory is converted to the same restricted store-only container used for external imports,
    /// so bundled skins do not bypass manifest, hash, MIME, image, or signature validation.
    public func importBundledPackage(at directoryURL: URL) throws -> ImportedSkinPackage {
        let requestedRoot = directoryURL.standardizedFileURL
        let fileManager = FileManager.default
        let rootValues = try requestedRoot.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true else {
            throw SkinImportError.forbiddenFile(requestedRoot.lastPathComponent)
        }
        let root = requestedRoot

        let manifestURL = root.appending(path: "manifest.json")
        let manifestValues = try manifestURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard manifestValues.isRegularFile == true, manifestValues.isSymbolicLink != true else {
            throw SkinImportError.invalidManifest
        }
        let manifestData = try Data(contentsOf: manifestURL, options: .mappedIfSafe)
        let manifest: SkinManifest
        do {
            manifest = try JSONDecoder().decode(SkinManifest.self, from: manifestData)
            try SkinPackageContract.validate(manifest: manifest)
        } catch let error as SkinContractError {
            throw error
        } catch {
            throw SkinImportError.invalidManifest
        }

        var expected = Set(manifest.files.map(\.path))
        expected.insert("manifest.json")
        if manifest.publisherPublicKey != nil { expected.insert("signature.ed25519") }
        var discovered = Set<String>()
        var bytesByPath: [String: Data] = [:]
        for relative in try fileManager.subpathsOfDirectory(atPath: root.path).sorted() {
            try SkinPackageContract.validateRelativePath(relative)
            let url = root.appending(path: relative)
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true {
                throw SkinImportError.forbiddenFile(relative)
            }
            if values.isDirectory == true { continue }
            guard values.isRegularFile == true else { throw SkinImportError.forbiddenFile(relative) }
            guard expected.contains(relative) else { throw SkinImportError.undeclaredFile(relative) }
            guard discovered.insert(relative).inserted else { throw SkinImportError.undeclaredFile(relative) }
            bytesByPath[relative] = try Data(contentsOf: url, options: .mappedIfSafe)
        }
        for path in expected where !discovered.contains(path) {
            throw SkinImportError.missingDeclaredFile(path)
        }
        var entries: [(path: String, data: Data)] = [("manifest.json", manifestData)]
        entries.append(contentsOf: expected.subtracting(["manifest.json"]).sorted().map { ($0, bytesByPath[$0]!) })
        return try importPackage(data: StoredZipWriter.write(entries))
    }

    private func verifyTrust(manifest: SkinManifest, manifestData: Data, signature: Data?) throws -> SkinTrustState {
        guard let encodedKey = manifest.publisherPublicKey else { return .unsigned }
        guard let keyData = Data(base64Encoded: encodedKey),
              let signature,
              signature.count == 64,
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
              key.isValidSignature(signature, for: manifestData)
        else {
            throw SkinImportError.invalidSignature
        }
        let fingerprint = Self.sha256(keyData)
        return trustedPublisherKeys.contains(keyData)
            ? .verifiedPublisher(fingerprint: fingerprint)
            : .signedUnknownPublisher(fingerprint: fingerprint)
    }

    private func sanitizeImage(_ data: Data, mime: String, path: String) throws -> (data: Data, pixels: UInt64) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              let sourceType = CGImageSourceGetType(source),
              let sourceUTType = UTType(sourceType as String)
        else {
            throw SkinImportError.invalidImage(path)
        }
        let expectedType: UTType = mime == "image/png" ? .png : .jpeg
        guard sourceUTType.conforms(to: expectedType),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0,
              height > 0
        else {
            throw SkinImportError.invalidImage(path)
        }
        guard width <= imageLimits.maximumDimension, height <= imageLimits.maximumDimension else {
            throw SkinImportError.imageDimensionsExceeded(path)
        }
        let pixels = UInt64(width) * UInt64(height)
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            throw SkinImportError.invalidImage(path)
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, expectedType.identifier as CFString, 1, nil) else {
            throw SkinImportError.invalidImage(path)
        }
        let propertiesForOutput: CFDictionary? = mime == "image/jpeg"
            ? [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary
            : nil
        CGImageDestinationAddImage(destination, image, propertiesForOutput)
        guard CGImageDestinationFinalize(destination) else {
            throw SkinImportError.invalidImage(path)
        }
        return (output as Data, pixels)
    }

    private static func isAllowedDeclaredPath(_ path: String) -> Bool {
        let lowercased = path.lowercased()
        return [".json", ".jpeg", ".jpg", ".png", ".txt"].contains { lowercased.hasSuffix($0) }
    }

    private static func mimeMatchesPath(_ mime: String, path: String) -> Bool {
        let lowercased = path.lowercased()
        return switch mime {
        case "application/json": lowercased.hasSuffix(".json")
        case "image/jpeg": lowercased.hasSuffix(".jpg") || lowercased.hasSuffix(".jpeg")
        case "image/png": lowercased.hasSuffix(".png")
        case "text/plain": lowercased.hasSuffix(".txt")
        default: false
        }
    }

    private static func hasExactTopLevelKeys(_ data: Data, allowed: Set<String>) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else {
            return false
        }
        return Set(dictionary.keys).isSubset(of: allowed)
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
