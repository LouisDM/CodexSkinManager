import XCTest
@testable import SkinCore

final class SkinPackageModelsTests: XCTestCase {
    private let decoder = JSONDecoder()

    func testSupportedManifestDecodesAndValidates() throws {
        let manifest = try decoder.decode(SkinManifest.self, from: Data(validManifest.utf8))

        XCTAssertNoThrow(try SkinPackageContract.validate(manifest: manifest))
        XCTAssertEqual(manifest.id, "meng-chuan-nightblade")
        XCTAssertEqual(manifest.version, "1.0.0")
        XCTAssertEqual(manifest.template, "nightblade-v1")
        XCTAssertEqual(manifest.files.count, 5)
        XCTAssertEqual(manifest.author.name, "OPCspace")
    }

    func testManifestRejectsUnsupportedSchema() throws {
        let manifest = try decodeManifest(replacing: "\"schemaVersion\": 1", with: "\"schemaVersion\": 2")

        XCTAssertThrowsError(try SkinPackageContract.validate(manifest: manifest)) { error in
            XCTAssertEqual(error as? SkinContractError, .unsupportedSchema(2))
        }
    }

    func testManifestRejectsUnsafeIdentifiers() throws {
        for identifier in ["../nightblade", "Night Blade", "-nightblade", "ab", "nightblade/"] {
            let manifest = try decodeManifest(replacing: "meng-chuan-nightblade", with: identifier)

            XCTAssertThrowsError(try SkinPackageContract.validate(manifest: manifest), "accepted \(identifier)")
        }
    }

    func testManifestRejectsInvalidSemanticVersion() throws {
        for version in ["1", "1.0", "01.0.0", "1.0.0-beta", "v1.0.0"] {
            let manifest = try decodeManifest(replacing: "1.0.0", with: version)

            XCTAssertThrowsError(try SkinPackageContract.validate(manifest: manifest), "accepted \(version)")
        }
    }

    func testManifestRejectsUnknownTemplate() throws {
        let manifest = try decodeManifest(replacing: "nightblade-v1", with: "package-script")

        XCTAssertThrowsError(try SkinPackageContract.validate(manifest: manifest)) { error in
            XCTAssertEqual(error as? SkinContractError, .unsupportedTemplate("package-script"))
        }
    }

    func testManifestRejectsUnsafeOrMalformedFiles() throws {
        let unsafePaths = ["/tmp/hero.png", "../hero.png", "assets\\hero.png", "assets//hero.png", "./hero.png"]
        for path in unsafePaths {
            let jsonPath = path.replacingOccurrences(of: "\\", with: "\\\\")
            let manifest = try decodeManifest(replacing: "assets/hero.png", with: jsonPath)
            XCTAssertThrowsError(try SkinPackageContract.validate(manifest: manifest), "accepted \(path)")
        }

        let badHash = try decodeManifest(replacing: String(repeating: "a", count: 64), with: "deadbeef")
        XCTAssertThrowsError(try SkinPackageContract.validate(manifest: badHash))
    }

    func testThemeAcceptsOnlyAllowlistedTokensAndMediaSlots() throws {
        let theme = try decoder.decode(SkinTheme.self, from: Data(validTheme.utf8))
        XCTAssertNoThrow(try SkinPackageContract.validate(theme: theme))

        let unknownToken = try decoder.decode(
            SkinTheme.self,
            from: Data(validTheme.replacingOccurrences(of: "\"canvas\"", with: "\"arbitraryCSS\"").utf8)
        )
        XCTAssertThrowsError(try SkinPackageContract.validate(theme: unknownToken))

        let unknownSlot = try decoder.decode(
            SkinTheme.self,
            from: Data(validTheme.replacingOccurrences(of: "\"hero\"", with: "\"script\"").utf8)
        )
        XCTAssertThrowsError(try SkinPackageContract.validate(theme: unknownSlot))
    }

    func testRightsControlPublicExport() throws {
        let privateRights = try decoder.decode(
            SkinRights.self,
            from: Data(#"{"redistributionAllowed":false,"commercialUse":false,"fanMade":true,"unofficial":true,"noEndorsement":true,"notice":"Private preview only"}"#.utf8)
        )
        let publicRights = try decoder.decode(
            SkinRights.self,
            from: Data(#"{"redistributionAllowed":true,"commercialUse":false,"fanMade":true,"unofficial":true,"noEndorsement":true,"notice":"Share with attribution"}"#.utf8)
        )

        XCTAssertFalse(privateRights.canExportPublicly)
        XCTAssertTrue(publicRights.canExportPublicly)
    }

    private func decodeManifest(replacing original: String, with replacement: String) throws -> SkinManifest {
        try decoder.decode(
            SkinManifest.self,
            from: Data(validManifest.replacingOccurrences(of: original, with: replacement).utf8)
        )
    }

    private var validManifest: String {
        let hash = String(repeating: "a", count: 64)
        return """
        {
          "schemaVersion": 1,
          "id": "meng-chuan-nightblade",
          "name": "孟川 · 玄刃夜行",
          "version": "1.0.0",
          "template": "nightblade-v1",
          "minManagerVersion": "1.0.0",
          "preview": "preview.png",
          "files": [
            {"path":"theme.json","byteCount":256,"sha256":"\(hash)","mime":"application/json"},
            {"path":"rights.json","byteCount":160,"sha256":"\(hash)","mime":"application/json"},
            {"path":"preview.png","byteCount":4096,"sha256":"\(hash)","mime":"image/png"},
            {"path":"assets/hero.png","byteCount":8192,"sha256":"\(hash)","mime":"image/png"},
            {"path":"LICENSES/assets.txt","byteCount":128,"sha256":"\(hash)","mime":"text/plain"}
          ],
          "author": {"name":"OPCspace","website":null},
          "publisherPublicKey": null
        }
        """
    }

    private var validTheme: String {
        """
        {
          "tokens": {
            "canvas": "#080D15",
            "accent": "#9E2F28",
            "panelRadius": "18"
          },
          "assets": {
            "hero": "assets/hero.png",
            "background": "assets/background.png"
          },
          "focalPoints": {
            "hero": {"x":0.72,"y":0.36}
          }
        }
        """
    }
}
