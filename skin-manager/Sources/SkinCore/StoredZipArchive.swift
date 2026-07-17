import Foundation

public enum StoredZipError: Error, Equatable, LocalizedError, Sendable {
    case archiveTooLarge
    case invalidArchive
    case entryCountExceeded
    case unsafePath(String)
    case duplicatePath(String)
    case linkOrSpecialFile(String)
    case encryptedEntry(String)
    case unsupportedCompression(String)
    case nestedArchive(String)
    case entryTooLarge(String)
    case expandedSizeExceeded
    case compressionRatioExceeded(String)
    case headerMismatch(String)
    case crcMismatch(String)
    case missingEntry(String)

    public var errorDescription: String? {
        switch self {
        case .archiveTooLarge: "皮肤包超过 64 MB 限制"
        case .invalidArchive: "皮肤包 ZIP 结构无效"
        case .entryCountExceeded: "皮肤包文件数量超过限制"
        case let .unsafePath(path): "皮肤包包含不安全路径：\(path)"
        case let .duplicatePath(path): "皮肤包包含冲突路径：\(path)"
        case let .linkOrSpecialFile(path): "皮肤包不得包含链接或特殊文件：\(path)"
        case let .encryptedEntry(path): "皮肤包不得包含加密文件：\(path)"
        case let .unsupportedCompression(path): "v1 皮肤包仅支持 store ZIP：\(path)"
        case let .nestedArchive(path): "皮肤包不得嵌套压缩包：\(path)"
        case let .entryTooLarge(path): "皮肤包内文件超过 32 MB：\(path)"
        case .expandedSizeExceeded: "皮肤包解压后超过 128 MB 限制"
        case let .compressionRatioExceeded(path): "皮肤包压缩比异常：\(path)"
        case let .headerMismatch(path): "ZIP 文件头不一致：\(path)"
        case let .crcMismatch(path): "文件 CRC 校验失败：\(path)"
        case let .missingEntry(path): "皮肤包缺少文件：\(path)"
        }
    }
}

public struct StoredZipArchive: Sendable {
    public struct Limits: Equatable, Sendable {
        public var maximumArchiveBytes: Int
        public var maximumExpandedBytes: UInt64
        public var maximumEntryBytes: UInt64
        public var maximumEntries: Int
        public var maximumCompressionRatio: UInt64

        public static let `default` = Limits(
            maximumArchiveBytes: 64 * 1_024 * 1_024,
            maximumExpandedBytes: 128 * 1_024 * 1_024,
            maximumEntryBytes: 32 * 1_024 * 1_024,
            maximumEntries: 128,
            maximumCompressionRatio: 100
        )

        public init(
            maximumArchiveBytes: Int,
            maximumExpandedBytes: UInt64,
            maximumEntryBytes: UInt64,
            maximumEntries: Int,
            maximumCompressionRatio: UInt64
        ) {
            self.maximumArchiveBytes = maximumArchiveBytes
            self.maximumExpandedBytes = maximumExpandedBytes
            self.maximumEntryBytes = maximumEntryBytes
            self.maximumEntries = maximumEntries
            self.maximumCompressionRatio = maximumCompressionRatio
        }
    }

    public struct Entry: Equatable, Sendable {
        public let path: String
        public let byteCount: Int
        public let crc32: UInt32
    }

    public let entries: [Entry]
    private let contents: [String: Data]

    public init(data: Data, limits: Limits = .default) throws {
        guard data.count <= limits.maximumArchiveBytes else {
            throw StoredZipError.archiveTooLarge
        }
        let reader = ZipByteReader(data: data)
        let eocdOffset = try Self.findEndOfCentralDirectory(reader)
        let diskNumber = try reader.uint16(at: eocdOffset + 4)
        let centralDisk = try reader.uint16(at: eocdOffset + 6)
        let entriesOnDisk = Int(try reader.uint16(at: eocdOffset + 8))
        let entryCount = Int(try reader.uint16(at: eocdOffset + 10))
        let centralSize = Int(try reader.uint32(at: eocdOffset + 12))
        let centralOffset = Int(try reader.uint32(at: eocdOffset + 16))
        let commentLength = Int(try reader.uint16(at: eocdOffset + 20))

        guard diskNumber == 0,
              centralDisk == 0,
              entriesOnDisk == entryCount,
              entryCount > 0,
              eocdOffset + 22 + commentLength == data.count,
              centralOffset >= 0,
              centralSize >= 0,
              centralOffset + centralSize == eocdOffset
        else {
            throw StoredZipError.invalidArchive
        }
        guard entryCount <= limits.maximumEntries else {
            throw StoredZipError.entryCountExceeded
        }

        var centralEntries: [CentralEntry] = []
        centralEntries.reserveCapacity(entryCount)
        var cursor = centralOffset
        var normalizedPaths = Set<String>()
        var expandedBytes: UInt64 = 0

        for _ in 0 ..< entryCount {
            guard try reader.uint32(at: cursor) == 0x0201_4B50 else {
                throw StoredZipError.invalidArchive
            }
            let flags = try reader.uint16(at: cursor + 8)
            let method = try reader.uint16(at: cursor + 10)
            let crc = try reader.uint32(at: cursor + 16)
            let compressedSize = UInt64(try reader.uint32(at: cursor + 20))
            let uncompressedSize = UInt64(try reader.uint32(at: cursor + 24))
            let nameLength = Int(try reader.uint16(at: cursor + 28))
            let extraLength = Int(try reader.uint16(at: cursor + 30))
            let fileCommentLength = Int(try reader.uint16(at: cursor + 32))
            let diskStart = try reader.uint16(at: cursor + 34)
            let externalAttributes = try reader.uint32(at: cursor + 38)
            let localOffset = Int(try reader.uint32(at: cursor + 42))
            let recordLength = 46 + nameLength + extraLength + fileCommentLength
            guard recordLength >= 46, cursor + recordLength <= eocdOffset, diskStart == 0 else {
                throw StoredZipError.invalidArchive
            }
            let nameData = try reader.data(at: cursor + 46, count: nameLength)
            guard let path = String(data: nameData, encoding: .utf8) else {
                throw StoredZipError.invalidArchive
            }

            do {
                try SkinPackageContract.validateRelativePath(path)
            } catch {
                throw StoredZipError.unsafePath(path)
            }
            let normalizedPath = SkinPackageContract.normalizedPathKey(path)
            guard normalizedPaths.insert(normalizedPath).inserted else {
                throw StoredZipError.duplicatePath(path)
            }
            if Self.isNestedArchive(path) {
                throw StoredZipError.nestedArchive(path)
            }
            if flags & 0x0001 != 0 {
                throw StoredZipError.encryptedEntry(path)
            }
            if flags & 0x0008 != 0 || method != 0 {
                throw StoredZipError.unsupportedCompression(path)
            }
            if Self.isLinkOrSpecialFile(externalAttributes) {
                throw StoredZipError.linkOrSpecialFile(path)
            }
            guard uncompressedSize <= limits.maximumEntryBytes else {
                throw StoredZipError.entryTooLarge(path)
            }
            if compressedSize == 0 {
                if uncompressedSize > 0 {
                    throw StoredZipError.compressionRatioExceeded(path)
                }
            } else if uncompressedSize > compressedSize * limits.maximumCompressionRatio {
                throw StoredZipError.compressionRatioExceeded(path)
            }
            let (newTotal, overflow) = expandedBytes.addingReportingOverflow(uncompressedSize)
            guard !overflow, newTotal <= limits.maximumExpandedBytes else {
                throw StoredZipError.expandedSizeExceeded
            }
            expandedBytes = newTotal

            centralEntries.append(CentralEntry(
                path: path,
                flags: flags,
                method: method,
                crc32: crc,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                localOffset: localOffset
            ))
            cursor += recordLength
        }
        guard cursor == eocdOffset else {
            throw StoredZipError.invalidArchive
        }

        var publicEntries: [Entry] = []
        var extracted: [String: Data] = [:]
        publicEntries.reserveCapacity(entryCount)
        extracted.reserveCapacity(entryCount)

        for metadata in centralEntries {
            let offset = metadata.localOffset
            guard try reader.uint32(at: offset) == 0x0403_4B50 else {
                throw StoredZipError.headerMismatch(metadata.path)
            }
            let localFlags = try reader.uint16(at: offset + 6)
            let localMethod = try reader.uint16(at: offset + 8)
            let localCRC = try reader.uint32(at: offset + 14)
            let localCompressedSize = UInt64(try reader.uint32(at: offset + 18))
            let localUncompressedSize = UInt64(try reader.uint32(at: offset + 22))
            let localNameLength = Int(try reader.uint16(at: offset + 26))
            let localExtraLength = Int(try reader.uint16(at: offset + 28))
            let localNameData = try reader.data(at: offset + 30, count: localNameLength)
            let localName = String(data: localNameData, encoding: .utf8)

            guard localName == metadata.path,
                  localFlags == metadata.flags,
                  localMethod == metadata.method,
                  localCRC == metadata.crc32,
                  localCompressedSize == metadata.compressedSize,
                  localUncompressedSize == metadata.uncompressedSize,
                  metadata.compressedSize == metadata.uncompressedSize,
                  metadata.compressedSize <= UInt64(Int.max)
            else {
                throw StoredZipError.headerMismatch(metadata.path)
            }

            let dataOffset = offset + 30 + localNameLength + localExtraLength
            let payload = try reader.data(at: dataOffset, count: Int(metadata.compressedSize))
            guard Self.crc32(payload) == metadata.crc32 else {
                throw StoredZipError.crcMismatch(metadata.path)
            }
            publicEntries.append(Entry(path: metadata.path, byteCount: payload.count, crc32: metadata.crc32))
            extracted[SkinPackageContract.normalizedPathKey(metadata.path)] = payload
        }

        entries = publicEntries
        contents = extracted
    }

    public func data(for path: String) throws -> Data {
        guard let data = contents[SkinPackageContract.normalizedPathKey(path)] else {
            throw StoredZipError.missingEntry(path)
        }
        return data
    }

    private static func findEndOfCentralDirectory(_ reader: ZipByteReader) throws -> Int {
        guard reader.count >= 22 else { throw StoredZipError.invalidArchive }
        let minimum = max(0, reader.count - 65_557)
        for offset in stride(from: reader.count - 22, through: minimum, by: -1) {
            if try reader.uint32(at: offset) == 0x0605_4B50 {
                return offset
            }
        }
        throw StoredZipError.invalidArchive
    }

    private static func isNestedArchive(_ path: String) -> Bool {
        let lowercased = path.lowercased()
        return [".7z", ".codexskin", ".gz", ".rar", ".tar", ".tgz", ".zip"].contains { lowercased.hasSuffix($0) }
    }

    private static func isLinkOrSpecialFile(_ attributes: UInt32) -> Bool {
        let fileType = (attributes >> 16) & 0xF000
        return fileType != 0 && fileType != 0x8000
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

private struct CentralEntry {
    let path: String
    let flags: UInt16
    let method: UInt16
    let crc32: UInt32
    let compressedSize: UInt64
    let uncompressedSize: UInt64
    let localOffset: Int
}

private struct ZipByteReader: Sendable {
    let data: Data
    var count: Int { data.count }

    func uint16(at offset: Int) throws -> UInt16 {
        let bytes = try data(at: offset, count: 2)
        return UInt16(bytes[bytes.startIndex]) | UInt16(bytes[bytes.startIndex + 1]) << 8
    }

    func uint32(at offset: Int) throws -> UInt32 {
        let bytes = try data(at: offset, count: 4)
        return UInt32(bytes[bytes.startIndex])
            | UInt32(bytes[bytes.startIndex + 1]) << 8
            | UInt32(bytes[bytes.startIndex + 2]) << 16
            | UInt32(bytes[bytes.startIndex + 3]) << 24
    }

    func data(at offset: Int, count: Int) throws -> Data {
        guard offset >= 0, count >= 0, offset <= data.count, count <= data.count - offset else {
            throw StoredZipError.invalidArchive
        }
        return Data(data[offset ..< offset + count])
    }
}
