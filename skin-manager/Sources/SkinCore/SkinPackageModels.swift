import Foundation

public struct SkinManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let id: String
    public let name: String
    public let version: String
    public let template: String
    public let minManagerVersion: String
    public let preview: String
    public let files: [SkinFile]
    public let author: SkinAuthor
    public let publisherPublicKey: String?

    public init(
        schemaVersion: Int,
        id: String,
        name: String,
        version: String,
        template: String,
        minManagerVersion: String,
        preview: String,
        files: [SkinFile],
        author: SkinAuthor,
        publisherPublicKey: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.version = version
        self.template = template
        self.minManagerVersion = minManagerVersion
        self.preview = preview
        self.files = files
        self.author = author
        self.publisherPublicKey = publisherPublicKey
    }
}

public struct SkinFile: Codable, Equatable, Sendable {
    public let path: String
    public let byteCount: Int64
    public let sha256: String
    public let mime: String

    public init(path: String, byteCount: Int64, sha256: String, mime: String) {
        self.path = path
        self.byteCount = byteCount
        self.sha256 = sha256
        self.mime = mime
    }
}

public struct SkinAuthor: Codable, Equatable, Sendable {
    public let name: String
    public let website: String?

    public init(name: String, website: String? = nil) {
        self.name = name
        self.website = website
    }
}

public struct SkinTheme: Codable, Equatable, Sendable {
    public let tokens: [String: String]
    public let assets: [String: String]
    public let focalPoints: [String: SkinFocalPoint]

    public init(
        tokens: [String: String],
        assets: [String: String],
        focalPoints: [String: SkinFocalPoint] = [:]
    ) {
        self.tokens = tokens
        self.assets = assets
        self.focalPoints = focalPoints
    }
}

public struct SkinFocalPoint: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct SkinRights: Codable, Equatable, Sendable {
    public let redistributionAllowed: Bool
    public let commercialUse: Bool
    public let fanMade: Bool
    public let unofficial: Bool
    public let noEndorsement: Bool
    public let notice: String

    public init(
        redistributionAllowed: Bool,
        commercialUse: Bool,
        fanMade: Bool,
        unofficial: Bool,
        noEndorsement: Bool,
        notice: String
    ) {
        self.redistributionAllowed = redistributionAllowed
        self.commercialUse = commercialUse
        self.fanMade = fanMade
        self.unofficial = unofficial
        self.noEndorsement = noEndorsement
        self.notice = notice
    }

    public var canExportPublicly: Bool { redistributionAllowed }
}

public enum SkinContractError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedSchema(Int)
    case invalidID(String)
    case invalidName
    case invalidVersion(String)
    case invalidManagerVersion(String)
    case unsupportedTemplate(String)
    case invalidPreview(String)
    case missingRequiredFile(String)
    case invalidFilePath(String)
    case duplicateFilePath(String)
    case invalidFileSize(String)
    case invalidHash(String)
    case unsupportedMIME(String)
    case invalidAuthor
    case invalidPublicKey
    case unsupportedToken(String)
    case invalidTokenValue(String)
    case unsupportedAssetSlot(String)
    case invalidFocalPoint(String)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedSchema(version): "不支持的皮肤包版本：\(version)"
        case let .invalidID(id): "非法皮肤 ID：\(id)"
        case .invalidName: "皮肤名称无效"
        case let .invalidVersion(version): "非法皮肤版本：\(version)"
        case let .invalidManagerVersion(version): "非法管理器版本：\(version)"
        case let .unsupportedTemplate(template): "不支持的皮肤模板：\(template)"
        case let .invalidPreview(path): "预览图路径无效：\(path)"
        case let .missingRequiredFile(path): "缺少必要文件：\(path)"
        case let .invalidFilePath(path): "非法包内路径：\(path)"
        case let .duplicateFilePath(path): "重复包内路径：\(path)"
        case let .invalidFileSize(path): "文件大小无效：\(path)"
        case let .invalidHash(path): "文件哈希无效：\(path)"
        case let .unsupportedMIME(mime): "不支持的文件类型：\(mime)"
        case .invalidAuthor: "作者信息无效"
        case .invalidPublicKey: "发布者公钥无效"
        case let .unsupportedToken(token): "不支持的主题令牌：\(token)"
        case let .invalidTokenValue(token): "主题令牌值无效：\(token)"
        case let .unsupportedAssetSlot(slot): "不支持的素材槽：\(slot)"
        case let .invalidFocalPoint(slot): "素材焦点无效：\(slot)"
        }
    }
}

public enum SkinPackageContract {
    public static let supportedTemplates: Set<String> = ["nightblade-v1", "red-lotus-v1"]

    private static let allowedMIMEs: Set<String> = [
        "application/json",
        "image/jpeg",
        "image/png",
        "text/plain",
    ]
    private static let colorTokens: Set<String> = [
        "accent", "accentStrong", "canvas", "focus", "ink", "line", "mutedInk", "surface", "surfaceRaised",
    ]
    private static let numericTokens: ClosedRange<Double> = 0 ... 1_000
    private static let allowedNumericTokenNames: Set<String> = ["controlRadius", "motionDuration", "panelRadius"]
    private static let allowedAssetSlots: Set<String> = ["avatar", "background", "hero"]

    public static func validate(manifest: SkinManifest) throws {
        guard manifest.schemaVersion == 1 else {
            throw SkinContractError.unsupportedSchema(manifest.schemaVersion)
        }
        guard matches(manifest.id, #"^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)*$"#),
              (3 ... 64).contains(manifest.id.utf8.count)
        else {
            throw SkinContractError.invalidID(manifest.id)
        }
        guard !manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              manifest.name.count <= 128
        else {
            throw SkinContractError.invalidName
        }
        guard isSemanticVersion(manifest.version) else {
            throw SkinContractError.invalidVersion(manifest.version)
        }
        guard isSemanticVersion(manifest.minManagerVersion) else {
            throw SkinContractError.invalidManagerVersion(manifest.minManagerVersion)
        }
        guard supportedTemplates.contains(manifest.template) else {
            throw SkinContractError.unsupportedTemplate(manifest.template)
        }
        guard !manifest.author.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              manifest.author.name.count <= 128
        else {
            throw SkinContractError.invalidAuthor
        }
        if let key = manifest.publisherPublicKey,
           Data(base64Encoded: key)?.count != 32
        {
            throw SkinContractError.invalidPublicKey
        }

        var normalizedPaths = Set<String>()
        for file in manifest.files {
            try validateRelativePath(file.path)
            let normalized = normalizedPathKey(file.path)
            guard normalizedPaths.insert(normalized).inserted else {
                throw SkinContractError.duplicateFilePath(file.path)
            }
            guard file.byteCount > 0, file.byteCount <= 32 * 1_024 * 1_024 else {
                throw SkinContractError.invalidFileSize(file.path)
            }
            guard matches(file.sha256, #"^[a-f0-9]{64}$"#) else {
                throw SkinContractError.invalidHash(file.path)
            }
            guard allowedMIMEs.contains(file.mime) else {
                throw SkinContractError.unsupportedMIME(file.mime)
            }
        }

        try validateRelativePath(manifest.preview)
        guard normalizedPaths.contains(normalizedPathKey(manifest.preview)) else {
            throw SkinContractError.invalidPreview(manifest.preview)
        }
        for required in ["theme.json", "rights.json"] where !normalizedPaths.contains(normalizedPathKey(required)) {
            throw SkinContractError.missingRequiredFile(required)
        }
    }

    public static func validateReference(id: String, version: String) throws {
        guard matches(id, #"^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)*$"#),
              (3 ... 64).contains(id.utf8.count),
              isSemanticVersion(version)
        else {
            throw SkinContractError.invalidID(id)
        }
    }

    public static func validate(theme: SkinTheme) throws {
        for (name, value) in theme.tokens {
            if colorTokens.contains(name) {
                guard matches(value, #"^#[0-9A-Fa-f]{6}(?:[0-9A-Fa-f]{2})?$"#) else {
                    throw SkinContractError.invalidTokenValue(name)
                }
            } else if allowedNumericTokenNames.contains(name) {
                guard let number = Double(value), numericTokens.contains(number) else {
                    throw SkinContractError.invalidTokenValue(name)
                }
            } else {
                throw SkinContractError.unsupportedToken(name)
            }
        }

        for (slot, path) in theme.assets {
            guard allowedAssetSlots.contains(slot) else {
                throw SkinContractError.unsupportedAssetSlot(slot)
            }
            try validateRelativePath(path)
        }
        for (slot, point) in theme.focalPoints {
            guard allowedAssetSlots.contains(slot),
                  (0 ... 1).contains(point.x),
                  (0 ... 1).contains(point.y)
            else {
                throw SkinContractError.invalidFocalPoint(slot)
            }
        }
    }

    public static func validateRelativePath(_ path: String) throws {
        guard !path.isEmpty,
              path.utf8.count <= 240,
              !path.hasPrefix("/"),
              !path.hasPrefix("~"),
              !path.contains("\\"),
              !path.contains("\0"),
              !path.contains("//")
        else {
            throw SkinContractError.invalidFilePath(path)
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count <= 8,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
        else {
            throw SkinContractError.invalidFilePath(path)
        }
    }

    public static func normalizedPathKey(_ path: String) -> String {
        path.precomposedStringWithCanonicalMapping.lowercased()
    }

    private static func isSemanticVersion(_ value: String) -> Bool {
        matches(value, #"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$"#)
    }

    private static func matches(_ value: String, _ pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }
}
