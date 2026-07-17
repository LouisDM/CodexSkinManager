import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import SkinCore

final class SkinPackageImporterTests: XCTestCase {
    func testImportsAValidUnsignedPackageAndSanitizesRasterMetadata() throws {
        let fixture = try SkinImportFixture.make()

        let imported = try SkinPackageImporter().importPackage(data: fixture.archive)

        XCTAssertEqual(imported.manifest.id, "meng-chuan-nightblade")
        XCTAssertEqual(imported.theme.assets["hero"], "assets/hero.png")
        XCTAssertFalse(imported.rights.canExportPublicly)
        XCTAssertEqual(imported.trust, .unsigned)
        XCTAssertNotNil(imported.files["preview.png"])
        XCTAssertFalse(String(decoding: imported.files["preview.png"]!, as: UTF8.self).contains("private-note"))
    }

    func testRejectsUndeclaredAndExecutableFiles() throws {
        let undeclared = try SkinImportFixture.make(extraEntries: [
            .init(name: "notes.txt", data: Data("surprise".utf8)),
        ])
        XCTAssertThrowsError(try SkinPackageImporter().importPackage(data: undeclared.archive)) { error in
            XCTAssertEqual(error as? SkinImportError, .undeclaredFile("notes.txt"))
        }

        let executable = try SkinImportFixture.make(additionalDeclaredFiles: [
            ("payload.js", "text/plain", Data("alert(1)".utf8)),
        ])
        XCTAssertThrowsError(try SkinPackageImporter().importPackage(data: executable.archive)) { error in
            XCTAssertEqual(error as? SkinImportError, .forbiddenFile("payload.js"))
        }
    }

    func testRejectsRemoteAssetsAndUnlistedAssetReferences() throws {
        let remoteTheme = SkinImportFixture.themeData(heroPath: "https://example.com/hero.png")
        let remote = try SkinImportFixture.make(themeData: remoteTheme)
        XCTAssertThrowsError(try SkinPackageImporter().importPackage(data: remote.archive))

        let missingTheme = SkinImportFixture.themeData(heroPath: "assets/missing.png")
        let missing = try SkinImportFixture.make(themeData: missingTheme)
        XCTAssertThrowsError(try SkinPackageImporter().importPackage(data: missing.archive)) { error in
            XCTAssertEqual(error as? SkinImportError, .missingAsset("assets/missing.png"))
        }
    }

    func testRejectsSizeHashMimeAndImageMismatches() throws {
        let badSize = try SkinImportFixture.make(descriptorMutation: { files in
            files[0] = SkinFile(path: files[0].path, byteCount: files[0].byteCount + 1, sha256: files[0].sha256, mime: files[0].mime)
        })
        XCTAssertThrowsError(try SkinPackageImporter().importPackage(data: badSize.archive)) { error in
            XCTAssertEqual(error as? SkinImportError, .fileSizeMismatch("theme.json"))
        }

        let badHash = try SkinImportFixture.make(descriptorMutation: { files in
            files[1] = SkinFile(path: files[1].path, byteCount: files[1].byteCount, sha256: String(repeating: "0", count: 64), mime: files[1].mime)
        })
        XCTAssertThrowsError(try SkinPackageImporter().importPackage(data: badHash.archive)) { error in
            XCTAssertEqual(error as? SkinImportError, .hashMismatch("rights.json"))
        }

        let badMIME = try SkinImportFixture.make(descriptorMutation: { files in
            files[2] = SkinFile(path: files[2].path, byteCount: files[2].byteCount, sha256: files[2].sha256, mime: "image/jpeg")
        })
        XCTAssertThrowsError(try SkinPackageImporter().importPackage(data: badMIME.archive)) { error in
            XCTAssertEqual(error as? SkinImportError, .mimeMismatch("preview.png"))
        }

        let invalidImage = try SkinImportFixture.make(previewData: Data("not an image".utf8))
        XCTAssertThrowsError(try SkinPackageImporter().importPackage(data: invalidImage.archive)) { error in
            XCTAssertEqual(error as? SkinImportError, .invalidImage("preview.png"))
        }
    }

    func testRejectsPackagesWithoutAssetLicense() throws {
        let fixture = try SkinImportFixture.make(includeLicense: false)

        XCTAssertThrowsError(try SkinPackageImporter().importPackage(data: fixture.archive)) { error in
            XCTAssertEqual(error as? SkinImportError, .missingLicense)
        }
    }

    func testRejectsImageDimensionAndTotalPixelBudgetViolations() throws {
        let fixture = try SkinImportFixture.make()
        let dimensionLimited = SkinPackageImporter(
            imageLimits: .init(maximumDimension: 1, maximumTotalPixels: 80_000_000)
        )
        XCTAssertThrowsError(try dimensionLimited.importPackage(data: fixture.archive)) { error in
            XCTAssertEqual(error as? SkinImportError, .imageDimensionsExceeded("preview.png"))
        }

        let pixelLimited = SkinPackageImporter(
            imageLimits: .init(maximumDimension: 8_192, maximumTotalPixels: 4)
        )
        XCTAssertThrowsError(try pixelLimited.importPackage(data: fixture.archive)) { error in
            XCTAssertEqual(error as? SkinImportError, .pixelBudgetExceeded)
        }
    }

    func testVerifiesKnownPublishersAndLabelsUnknownSignedPublishers() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let publicKey = privateKey.publicKey.rawRepresentation
        let fixture = try SkinImportFixture.make(signingKey: privateKey)

        let trusted = try SkinPackageImporter(trustedPublisherKeys: [publicKey]).importPackage(data: fixture.archive)
        let unknown = try SkinPackageImporter().importPackage(data: fixture.archive)
        let fingerprint = SHA256.hash(data: publicKey).map { String(format: "%02x", $0) }.joined()

        XCTAssertEqual(trusted.trust, .verifiedPublisher(fingerprint: fingerprint))
        XCTAssertEqual(unknown.trust, .signedUnknownPublisher(fingerprint: fingerprint))
    }

    func testRejectsInvalidOrUnexpectedSignatures() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        var signed = try SkinImportFixture.make(signingKey: privateKey)
        signed.entries[signed.entries.firstIndex(where: { $0.name == "signature.ed25519" })!].data[0] ^= 0xFF
        signed.archive = ZipFixture.make(signed.entries)

        XCTAssertThrowsError(try SkinPackageImporter().importPackage(data: signed.archive)) { error in
            XCTAssertEqual(error as? SkinImportError, .invalidSignature)
        }

        let unexpected = try SkinImportFixture.make(extraEntries: [
            .init(name: "signature.ed25519", data: Data(repeating: 0, count: 64)),
        ])
        XCTAssertThrowsError(try SkinPackageImporter().importPackage(data: unexpected.archive)) { error in
            XCTAssertEqual(error as? SkinImportError, .unexpectedSignature)
        }
    }

    func testImportsAValidatedManagerBundledDirectory() throws {
        let fixture = try SkinImportFixture.make(id: "bundled-skin")
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "bundled-skin-\(UUID().uuidString)", directoryHint: .isDirectory)
        for entry in fixture.entries {
            let destination = directory.appending(path: entry.name)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try entry.data.write(to: destination)
        }

        let imported = try SkinPackageImporter().importBundledPackage(at: directory)

        XCTAssertEqual(imported.manifest.id, "bundled-skin")
        XCTAssertEqual(imported.trust, .unsigned)
    }

    func testBundledDirectoryImportRejectsSymlinksAndUndeclaredFiles() throws {
        let fixture = try SkinImportFixture.make(id: "bundled-skin")
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "bundled-attack-\(UUID().uuidString)", directoryHint: .isDirectory)
        for entry in fixture.entries {
            let destination = directory.appending(path: entry.name)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try entry.data.write(to: destination)
        }
        try Data("surprise".utf8).write(to: directory.appending(path: "extra.txt"))
        XCTAssertThrowsError(try SkinPackageImporter().importBundledPackage(at: directory))
        try FileManager.default.removeItem(at: directory.appending(path: "extra.txt"))
        try FileManager.default.removeItem(at: directory.appending(path: "preview.png"))
        try FileManager.default.createSymbolicLink(
            at: directory.appending(path: "preview.png"),
            withDestinationURL: directory.appending(path: "assets/hero.png")
        )
        XCTAssertThrowsError(try SkinPackageImporter().importBundledPackage(at: directory))
    }
}

struct SkinImportFixture {
    var archive: Data
    var entries: [ZipFixture.Entry]

    static func make(
        id: String = "meng-chuan-nightblade",
        name: String = "孟川 · 玄刃夜行",
        version: String = "1.0.0",
        themeData: Data = themeData(),
        rightsData: Data? = nil,
        previewData: Data? = nil,
        includeLicense: Bool = true,
        additionalDeclaredFiles: [(String, String, Data)] = [],
        extraEntries: [ZipFixture.Entry] = [],
        signingKey: Curve25519.Signing.PrivateKey? = nil,
        descriptorMutation: ((inout [SkinFile]) -> Void)? = nil
    ) throws -> SkinImportFixture {
        let preview = try previewData ?? pngWithMetadata(note: "private-note")
        let hero = try pngWithMetadata(note: "source-metadata")
        let rights = rightsData ?? Data(#"{"redistributionAllowed":false,"commercialUse":false,"fanMade":true,"unofficial":true,"noEndorsement":true,"notice":"Private preview only"}"#.utf8)
        let license = Data("Private preview asset license".utf8)

        var declared: [(String, String, Data)] = [
            ("theme.json", "application/json", themeData),
            ("rights.json", "application/json", rights),
            ("preview.png", "image/png", preview),
            ("assets/hero.png", "image/png", hero),
        ]
        if includeLicense {
            declared.append(("LICENSES/assets.txt", "text/plain", license))
        }
        declared.append(contentsOf: additionalDeclaredFiles)

        var files = declared.map { value in
            SkinFile(path: value.0, byteCount: Int64(value.2.count), sha256: sha256(value.2), mime: value.1)
        }
        descriptorMutation?(&files)
        let publicKey = signingKey?.publicKey.rawRepresentation.base64EncodedString()
        let manifest = SkinManifest(
            schemaVersion: 1,
            id: id,
            name: name,
            version: version,
            template: "nightblade-v1",
            minManagerVersion: "1.0.0",
            preview: "preview.png",
            files: files,
            author: SkinAuthor(name: "OPCspace"),
            publisherPublicKey: publicKey
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let manifestData = try encoder.encode(manifest)

        var entries = [ZipFixture.Entry(name: "manifest.json", data: manifestData)]
        entries += declared.map { ZipFixture.Entry(name: $0.0, data: $0.2) }
        if let signingKey {
            entries.append(.init(name: "signature.ed25519", data: try signingKey.signature(for: manifestData)))
        }
        entries.append(contentsOf: extraEntries)
        return SkinImportFixture(archive: ZipFixture.make(entries), entries: entries)
    }

    static func themeData(heroPath: String = "assets/hero.png") -> Data {
        Data("""
        {
          "tokens": {"canvas":"#080D15","accent":"#9E2F28","panelRadius":"18"},
          "assets": {"hero":"\(heroPath)"},
          "focalPoints": {"hero":{"x":0.72,"y":0.36}}
        }
        """.utf8)
    }

    private static func pngWithMetadata(note: String) throws -> Data {
        let width = 2
        let height = 2
        let bytes: [UInt8] = [
            16, 24, 32, 255, 48, 56, 64, 255,
            80, 88, 96, 255, 112, 120, 128, 255,
        ]
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, [
            kCGImagePropertyPNGDictionary: [kCGImagePropertyPNGDescription: note],
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw FixtureError.imageEncoding }
        return output as Data
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private enum FixtureError: Error { case imageEncoding }
}
