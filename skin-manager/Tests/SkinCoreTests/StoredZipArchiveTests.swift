import Foundation
import XCTest
@testable import SkinCore

final class StoredZipArchiveTests: XCTestCase {
    func testReadsAValidStoredArchive() throws {
        let data = ZipFixture.make([
            .init(name: "manifest.json", data: Data("{}".utf8)),
            .init(name: "assets/hero.png", data: Data([0x89, 0x50, 0x4E, 0x47])),
        ])

        let archive = try StoredZipArchive(data: data)

        XCTAssertEqual(archive.entries.map(\.path), ["manifest.json", "assets/hero.png"])
        XCTAssertEqual(try archive.data(for: "manifest.json"), Data("{}".utf8))
    }

    func testRejectsUnsafePaths() {
        let paths = [
            "/tmp/hero.png",
            "../hero.png",
            "assets/../hero.png",
            "assets\\hero.png",
            "assets//hero.png",
            "./hero.png",
            "a/b/c/d/e/f/g/h/i.png",
            "bad\0name.png",
        ]

        for path in paths {
            XCTAssertThrowsError(try StoredZipArchive(data: ZipFixture.make([.init(name: path)])), "accepted \(path)")
        }
    }

    func testRejectsDuplicateCaseAndUnicodeCollisions() {
        let duplicates = ZipFixture.make([
            .init(name: "Preview.png"),
            .init(name: "preview.png"),
        ])
        XCTAssertThrowsError(try StoredZipArchive(data: duplicates)) { error in
            XCTAssertEqual(error as? StoredZipError, .duplicatePath("preview.png"))
        }

        let unicodeCollision = ZipFixture.make([
            .init(name: "assets/caf\u{00E9}.png"),
            .init(name: "assets/cafe\u{0301}.png"),
        ])
        XCTAssertThrowsError(try StoredZipArchive(data: unicodeCollision))
    }

    func testRejectsSymlinksEncryptionCompressionAndNestedArchives() {
        let symlinkMode = UInt32(0o120777) << 16
        XCTAssertThrowsError(try StoredZipArchive(data: ZipFixture.make([
            .init(name: "assets/link.png", externalAttributes: symlinkMode),
        ]))) { error in
            XCTAssertEqual(error as? StoredZipError, .linkOrSpecialFile("assets/link.png"))
        }

        XCTAssertThrowsError(try StoredZipArchive(data: ZipFixture.make([
            .init(name: "assets/secret.png", flags: 0x0001),
        ]))) { error in
            XCTAssertEqual(error as? StoredZipError, .encryptedEntry("assets/secret.png"))
        }

        XCTAssertThrowsError(try StoredZipArchive(data: ZipFixture.make([
            .init(name: "assets/hero.png", method: 8),
        ]))) { error in
            XCTAssertEqual(error as? StoredZipError, .unsupportedCompression("assets/hero.png"))
        }

        for path in ["nested.zip", "assets/theme.codexskin", "assets/archive.tar"] {
            XCTAssertThrowsError(try StoredZipArchive(data: ZipFixture.make([.init(name: path)])))
        }
    }

    func testRejectsCountAndSizeLimitViolationsBeforeExtraction() {
        let tooMany = (0 ... 128).map { ZipFixture.Entry(name: "files/\($0).txt") }
        XCTAssertThrowsError(try StoredZipArchive(data: ZipFixture.make(tooMany))) { error in
            XCTAssertEqual(error as? StoredZipError, .entryCountExceeded)
        }

        let oversizedEntry = ZipFixture.make([
            .init(name: "huge.bin", declaredCompressedSize: 33 * 1_024 * 1_024, declaredUncompressedSize: 33 * 1_024 * 1_024),
        ])
        XCTAssertThrowsError(try StoredZipArchive(data: oversizedEntry)) { error in
            XCTAssertEqual(error as? StoredZipError, .entryTooLarge("huge.bin"))
        }

        let expanded = ZipFixture.make([
            .init(name: "one.bin", declaredCompressedSize: 32 * 1_024 * 1_024, declaredUncompressedSize: 32 * 1_024 * 1_024),
            .init(name: "two.bin", declaredCompressedSize: 32 * 1_024 * 1_024, declaredUncompressedSize: 32 * 1_024 * 1_024),
            .init(name: "three.bin", declaredCompressedSize: 32 * 1_024 * 1_024, declaredUncompressedSize: 32 * 1_024 * 1_024),
            .init(name: "four.bin", declaredCompressedSize: 32 * 1_024 * 1_024, declaredUncompressedSize: 32 * 1_024 * 1_024),
            .init(name: "five.bin", declaredCompressedSize: 1, declaredUncompressedSize: 1),
        ])
        XCTAssertThrowsError(try StoredZipArchive(data: expanded)) { error in
            XCTAssertEqual(error as? StoredZipError, .expandedSizeExceeded)
        }

        let suspiciousRatio = ZipFixture.make([
            .init(name: "ratio.bin", declaredCompressedSize: 1, declaredUncompressedSize: 101),
        ])
        XCTAssertThrowsError(try StoredZipArchive(data: suspiciousRatio)) { error in
            XCTAssertEqual(error as? StoredZipError, .compressionRatioExceeded("ratio.bin"))
        }
    }

    func testRejectsHeaderAndIntegrityMismatches() {
        let nameMismatch = ZipFixture.make([
            .init(name: "central.txt", localName: "local.txt"),
        ])
        XCTAssertThrowsError(try StoredZipArchive(data: nameMismatch)) { error in
            XCTAssertEqual(error as? StoredZipError, .headerMismatch("central.txt"))
        }

        let crcMismatch = ZipFixture.make([
            .init(name: "payload.txt", data: Data("hello".utf8), centralCRC32: 0x1234_5678, localCRC32: 0x1234_5678),
        ])
        XCTAssertThrowsError(try StoredZipArchive(data: crcMismatch)) { error in
            XCTAssertEqual(error as? StoredZipError, .crcMismatch("payload.txt"))
        }
    }

    func testRejectsAnArchiveLargerThanConfiguredMaximum() {
        var limits = StoredZipArchive.Limits.default
        limits.maximumArchiveBytes = 16

        XCTAssertThrowsError(try StoredZipArchive(data: ZipFixture.make([.init(name: "a.txt")]), limits: limits)) { error in
            XCTAssertEqual(error as? StoredZipError, .archiveTooLarge)
        }
    }
}

enum ZipFixture {
    struct Entry {
        let name: String
        var data = Data("x".utf8)
        var localName: String?
        var flags: UInt16 = 0
        var method: UInt16 = 0
        var externalAttributes: UInt32 = 0
        var declaredCompressedSize: UInt32?
        var declaredUncompressedSize: UInt32?
        var centralCRC32: UInt32?
        var localCRC32: UInt32?
    }

    static func make(_ entries: [Entry]) -> Data {
        var archive = Data()
        var central = Data()

        for entry in entries {
            let localOffset = UInt32(clamping: archive.count)
            let centralName = Data(entry.name.utf8)
            let localName = Data((entry.localName ?? entry.name).utf8)
            let crc = crc32(entry.data)
            let centralCRC = entry.centralCRC32 ?? crc
            let localCRC = entry.localCRC32 ?? centralCRC
            let compressedSize = entry.declaredCompressedSize ?? UInt32(clamping: entry.data.count)
            let uncompressedSize = entry.declaredUncompressedSize ?? UInt32(clamping: entry.data.count)

            archive.appendLE(UInt32(0x0403_4B50))
            archive.appendLE(UInt16(20))
            archive.appendLE(entry.flags)
            archive.appendLE(entry.method)
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0))
            archive.appendLE(localCRC)
            archive.appendLE(compressedSize)
            archive.appendLE(uncompressedSize)
            archive.appendLE(UInt16(clamping: localName.count))
            archive.appendLE(UInt16(0))
            archive.append(localName)
            archive.append(entry.data)

            central.appendLE(UInt32(0x0201_4B50))
            central.appendLE(UInt16((3 << 8) | 20))
            central.appendLE(UInt16(20))
            central.appendLE(entry.flags)
            central.appendLE(entry.method)
            central.appendLE(UInt16(0))
            central.appendLE(UInt16(0))
            central.appendLE(centralCRC)
            central.appendLE(compressedSize)
            central.appendLE(uncompressedSize)
            central.appendLE(UInt16(clamping: centralName.count))
            central.appendLE(UInt16(0))
            central.appendLE(UInt16(0))
            central.appendLE(UInt16(0))
            central.appendLE(UInt16(0))
            central.appendLE(entry.externalAttributes)
            central.appendLE(localOffset)
            central.append(centralName)
        }

        let centralOffset = UInt32(clamping: archive.count)
        archive.append(central)
        archive.appendLE(UInt32(0x0605_4B50))
        archive.appendLE(UInt16(0))
        archive.appendLE(UInt16(0))
        archive.appendLE(UInt16(clamping: entries.count))
        archive.appendLE(UInt16(clamping: entries.count))
        archive.appendLE(UInt32(clamping: central.count))
        archive.appendLE(centralOffset)
        archive.appendLE(UInt16(0))
        return archive
    }

    static func crc32(_ data: Data) -> UInt32 {
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

extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
