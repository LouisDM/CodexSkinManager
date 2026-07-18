import CryptoKit
import Foundation

public enum SkinExportError: Error, Equatable, LocalizedError, Sendable {
    case invalidDestination
    case fileTooLarge(String)
    case missingFile(String)

    public var errorDescription: String? {
        switch self {
        case .invalidDestination: "导出文件必须使用 .codexskin 扩展名"
        case let .fileTooLarge(path): "导出文件超过 ZIP v1 限制：\(path)"
        case let .missingFile(path): "已安装皮肤缺少文件：\(path)"
        }
    }
}

public struct SkinPackageExporter: Sendable {
    public init() {}

    public func data(for package: StoredSkinPackage) throws -> Data {
        let originalDescriptors = Dictionary(uniqueKeysWithValues: package.manifest.files.map { ($0.path, $0) })
        var descriptors: [SkinFile] = []
        for path in package.files.keys.sorted() {
            guard let contents = package.files[path], let original = originalDescriptors[path] else {
                throw SkinExportError.missingFile(path)
            }
            descriptors.append(SkinFile(
                path: path,
                byteCount: Int64(contents.count),
                sha256: Self.sha256(contents),
                mime: original.mime
            ))
        }
        let manifest = SkinManifest(
            schemaVersion: 1,
            id: package.manifest.id,
            name: package.manifest.name,
            version: package.manifest.version,
            template: package.manifest.template,
            minManagerVersion: package.manifest.minManagerVersion,
            preview: package.manifest.preview,
            files: descriptors,
            author: package.manifest.author,
            publisherPublicKey: nil
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let manifestData = try encoder.encode(manifest)
        var entries = [("manifest.json", manifestData)]
        entries.append(contentsOf: package.files.keys.sorted().map { ($0, package.files[$0]!) })
        return try StoredZipWriter.write(entries)
    }

    public func export(_ package: StoredSkinPackage, to destination: URL) throws {
        guard destination.pathExtension.lowercased() == "codexskin" else {
            throw SkinExportError.invalidDestination
        }
        let bytes = try data(for: package)
        let fileManager = FileManager.default
        let parent = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let temporary = parent.appending(path: ".\(destination.lastPathComponent).tmp-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: temporary) }
        try bytes.write(to: temporary, options: .atomic)
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: destination)
        }
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

enum StoredZipWriter {
    static func write(_ entries: [(path: String, data: Data)]) throws -> Data {
        var archive = Data()
        var centralDirectory = Data()

        for entry in entries {
            guard entry.data.count <= Int(UInt32.max) else {
                throw SkinExportError.fileTooLarge(entry.path)
            }
            let nameData = Data(entry.path.utf8)
            guard nameData.count <= Int(UInt16.max) else {
                throw SkinExportError.fileTooLarge(entry.path)
            }
            let localOffset = UInt32(archive.count)
            let size = UInt32(entry.data.count)
            let crc = crc32(entry.data)

            archive.appendLittleEndian(UInt32(0x0403_4B50))
            archive.appendLittleEndian(UInt16(20))
            archive.appendLittleEndian(UInt16(0x0800))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(crc)
            archive.appendLittleEndian(size)
            archive.appendLittleEndian(size)
            archive.appendLittleEndian(UInt16(nameData.count))
            archive.appendLittleEndian(UInt16(0))
            archive.append(nameData)
            archive.append(entry.data)

            centralDirectory.appendLittleEndian(UInt32(0x0201_4B50))
            centralDirectory.appendLittleEndian(UInt16((3 << 8) | 20))
            centralDirectory.appendLittleEndian(UInt16(20))
            centralDirectory.appendLittleEndian(UInt16(0x0800))
            centralDirectory.appendLittleEndian(UInt16(0))
            centralDirectory.appendLittleEndian(UInt16(0))
            centralDirectory.appendLittleEndian(UInt16(0))
            centralDirectory.appendLittleEndian(crc)
            centralDirectory.appendLittleEndian(size)
            centralDirectory.appendLittleEndian(size)
            centralDirectory.appendLittleEndian(UInt16(nameData.count))
            centralDirectory.appendLittleEndian(UInt16(0))
            centralDirectory.appendLittleEndian(UInt16(0))
            centralDirectory.appendLittleEndian(UInt16(0))
            centralDirectory.appendLittleEndian(UInt16(0))
            centralDirectory.appendLittleEndian(UInt32(0o100644) << 16)
            centralDirectory.appendLittleEndian(localOffset)
            centralDirectory.append(nameData)
        }

        guard entries.count <= Int(UInt16.max),
              archive.count <= Int(UInt32.max),
              centralDirectory.count <= Int(UInt32.max)
        else {
            throw SkinExportError.fileTooLarge("archive")
        }
        let centralOffset = UInt32(archive.count)
        archive.append(centralDirectory)
        archive.appendLittleEndian(UInt32(0x0605_4B50))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt16(entries.count))
        archive.appendLittleEndian(UInt16(entries.count))
        archive.appendLittleEndian(UInt32(centralDirectory.count))
        archive.appendLittleEndian(centralOffset)
        archive.appendLittleEndian(UInt16(0))
        return archive
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc = UInt32.max
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0 ..< 8 {
                crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
            }
        }
        return crc ^ UInt32.max
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
