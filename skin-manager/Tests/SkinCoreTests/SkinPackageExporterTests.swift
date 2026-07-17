import Foundation
import XCTest
@testable import SkinCore

final class SkinPackageExporterTests: XCTestCase {
    func testRefusesToExportAPrivateOnlySkin() async throws {
        let repository = SkinRepository(rootURL: temporaryRoot())
        let imported = try SkinPackageImporter().importPackage(data: SkinImportFixture.make().archive)
        let installed = installedValue(try await repository.install(imported))
        let stored = try await repository.load(id: installed.id, version: installed.version)

        XCTAssertThrowsError(try SkinPackageExporter().data(for: stored)) { error in
            XCTAssertEqual(error as? SkinExportError, .redistributionNotAllowed)
        }
    }

    func testExportIsDeterministicContainsOnlyDataAndRoundTrips() async throws {
        let rights = Data(#"{"redistributionAllowed":true,"commercialUse":false,"fanMade":true,"unofficial":true,"noEndorsement":true,"notice":"Share with attribution"}"#.utf8)
        let fixture = try SkinImportFixture.make(id: "shareable-skin", name: "Shareable", rightsData: rights)
        let imported = try SkinPackageImporter().importPackage(data: fixture.archive)
        let repository = SkinRepository(rootURL: temporaryRoot())
        let installed = installedValue(try await repository.install(imported))
        let stored = try await repository.load(id: installed.id, version: installed.version)
        let exporter = SkinPackageExporter()

        let first = try exporter.data(for: stored)
        let second = try exporter.data(for: stored)
        let roundTrip = try SkinPackageImporter().importPackage(data: first)
        let entries = try StoredZipArchive(data: first).entries.map(\.path)

        XCTAssertEqual(first, second)
        XCTAssertEqual(roundTrip.manifest.id, "shareable-skin")
        XCTAssertEqual(roundTrip.trust, .unsigned)
        XCTAssertFalse(entries.contains(where: { ["js", "mjs", "sh", "command"].contains(URL(fileURLWithPath: $0).pathExtension) }))
        XCTAssertEqual(entries.first, "manifest.json")
    }

    func testExportsAtomicallyToChosenCodexskinURL() async throws {
        let rights = Data(#"{"redistributionAllowed":true,"commercialUse":true,"fanMade":false,"unofficial":false,"noEndorsement":true,"notice":"Original redistributable skin"}"#.utf8)
        let fixture = try SkinImportFixture.make(id: "original-skin", name: "Original", rightsData: rights)
        let repository = SkinRepository(rootURL: temporaryRoot())
        let installed = installedValue(try await repository.install(SkinPackageImporter().importPackage(data: fixture.archive)))
        let stored = try await repository.load(id: installed.id, version: installed.version)
        let destination = temporaryRoot().appending(path: "Original.codexskin")

        try SkinPackageExporter().export(stored, to: destination)

        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertNoThrow(try SkinPackageImporter().importPackage(data: Data(contentsOf: destination)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathExtension("tmp").path))
    }

    private func installedValue(_ outcome: SkinInstallOutcome) -> InstalledSkin {
        switch outcome {
        case let .installed(skin), let .alreadyInstalled(skin): skin
        }
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "skin-export-\(UUID().uuidString)", directoryHint: .isDirectory)
    }
}
