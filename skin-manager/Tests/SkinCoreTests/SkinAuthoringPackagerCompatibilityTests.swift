import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import SkinCore

final class SkinAuthoringPackagerCompatibilityTests: XCTestCase {
    func testGenericPythonPackagerProducesAnImportableSkin() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let builder = repositoryRoot.appending(path: "scripts/build_codexskin.py")
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: "codex-skin-authoring-\(UUID().uuidString)", directoryHint: .isDirectory)
        let source = temporaryRoot.appending(path: "sample", directoryHint: .isDirectory)
        let assets = source.appending(path: "assets", directoryHint: .isDirectory)
        let licenses = source.appending(path: "LICENSES", directoryHint: .isDirectory)
        let output = temporaryRoot.appending(path: "sample.codexskin")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: licenses, withIntermediateDirectories: true)
        let image = try makePNG()
        try image.write(to: assets.appending(path: "background.png"))
        try image.write(to: assets.appending(path: "hero.png"))
        try Data("Original test fixture. Redistribution allowed for tests.\n".utf8)
            .write(to: licenses.appending(path: "assets.txt"))
        try Data(
            """
            {
              "schemaVersion": 1,
              "id": "authoring-contract-test",
              "name": "Authoring Contract Test",
              "version": "1.0.0",
              "template": "nightblade-v1",
              "minManagerVersion": "1.1.0",
              "preview": "assets/background.png",
              "author": {"name": "Test Author", "website": null},
              "theme": {
                "tokens": {"accent": "#8FD8FF", "canvas": "#080D15", "panelRadius": "12"},
                "assets": {
                  "background": "assets/background.png",
                  "hero": "assets/hero.png"
                },
                "focalPoints": {
                  "background": {"x": 0.62, "y": 0.5},
                  "hero": {"x": 0.5, "y": 0.2}
                }
              },
              "rights": {
                "redistributionAllowed": true,
                "commercialUse": false,
                "fanMade": false,
                "unofficial": true,
                "noEndorsement": true,
                "notice": "Original automated test fixture."
              }
            }
            """.utf8
        ).write(to: source.appending(path: "skin.json"))

        let process = Process()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [
            builder.path,
            "--source", source.path,
            "--output", output.path,
        ]
        process.currentDirectoryURL = repositoryRoot
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        let errorText = String(
            decoding: errors.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        XCTAssertEqual(process.terminationStatus, 0, errorText)
        guard process.terminationStatus == 0 else { return }

        let imported = try SkinPackageImporter().importPackage(
            data: Data(contentsOf: output, options: .mappedIfSafe)
        )
        XCTAssertEqual(imported.manifest.id, "authoring-contract-test")
        XCTAssertEqual(imported.manifest.template, "nightblade-v1")
        XCTAssertEqual(imported.theme.assets["hero"], "assets/hero.png")
        XCTAssertEqual(imported.rights.redistributionAllowed, true)
        XCTAssertEqual(imported.trust, .unsigned)
    }

    private func makePNG() throws -> Data {
        let bytes: [UInt8] = [
            16, 24, 32, 255, 48, 56, 64, 255,
            80, 88, 96, 255, 112, 120, 128, 255,
        ]
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let image = CGImage(
            width: 2,
            height: 2,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: 8,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw ImageFixtureError.encodingFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ImageFixtureError.encodingFailed
        }
        return output as Data
    }

    private enum ImageFixtureError: Error {
        case encodingFailed
    }
}
