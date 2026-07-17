import Foundation
import XCTest
@testable import SkinCore

final class SkinRepositoryTests: XCTestCase {
    func testInstallsListsAndRecognizesAnIdenticalPackage() async throws {
        let root = temporaryRoot()
        let repository = SkinRepository(rootURL: root)
        let imported = try importFixture(id: "zeta-skin", name: "Zeta")

        let first = try await repository.install(imported)
        let second = try await repository.install(imported)
        let list = try await repository.listInstalled()

        guard case let .installed(installed) = first else { return XCTFail("expected new install") }
        guard case let .alreadyInstalled(existing) = second else { return XCTFail("expected identical install") }
        XCTAssertEqual(installed.id, "zeta-skin")
        XCTAssertEqual(existing.id, installed.id)
        XCTAssertEqual(list.map(\.id), ["zeta-skin"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: installed.directoryURL.path))
    }

    func testInventoryIsStableAndSortedByDisplayName() async throws {
        let repository = SkinRepository(rootURL: temporaryRoot())
        _ = try await repository.install(importFixture(id: "zeta-skin", name: "Zeta"))
        _ = try await repository.install(importFixture(id: "alpha-skin", name: "Alpha"))

        let installed = try await repository.listInstalled()

        XCTAssertEqual(installed.map(\.name), ["Alpha", "Zeta"])
    }

    func testRejectsSameIDAndVersionWithDifferentManifest() async throws {
        let repository = SkinRepository(rootURL: temporaryRoot())
        _ = try await repository.install(importFixture(id: "conflict-skin", name: "First"))
        let conflicting = try importFixture(id: "conflict-skin", name: "Changed")

        do {
            _ = try await repository.install(conflicting)
            XCTFail("expected version conflict")
        } catch {
            XCTAssertEqual(error as? SkinRepositoryError, .versionConflict(id: "conflict-skin", version: "1.0.0"))
        }
    }

    func testPersistsActiveSkinAndProtectsItFromDeletion() async throws {
        let root = temporaryRoot()
        let repository = SkinRepository(rootURL: root)
        let installed = installedValue(try await repository.install(importFixture(id: "active-skin", name: "Active")))

        try await repository.setActive(id: installed.id, version: installed.version)
        let reloaded = SkinRepository(rootURL: root)
        let active = try await reloaded.activeSkin()
        XCTAssertEqual(active, ActiveSkinRecord(id: installed.id, version: installed.version))

        do {
            try await reloaded.delete(id: installed.id, version: installed.version)
            XCTFail("expected active skin protection")
        } catch {
            XCTAssertEqual(error as? SkinRepositoryError, .cannotDeleteActiveSkin)
        }

        try await reloaded.clearActive()
        try await reloaded.delete(id: installed.id, version: installed.version)
        let remaining = try await reloaded.listInstalled()
        XCTAssertTrue(remaining.isEmpty)
    }

    func testInstallFailureLeavesNoStagingDirectoryOrPartialSkin() async throws {
        let root = temporaryRoot()
        try FileManager.default.createDirectory(at: root.appending(path: "skins"), withIntermediateDirectories: true)
        let blockingPath = root.appending(path: "skins/blocked-skin")
        try Data("not a directory".utf8).write(to: blockingPath)
        let repository = SkinRepository(rootURL: root)

        do {
            _ = try await repository.install(importFixture(id: "blocked-skin", name: "Blocked"))
            XCTFail("expected filesystem failure")
        } catch {
            let staging = root.appending(path: ".staging")
            let contents = (try? FileManager.default.contentsOfDirectory(atPath: staging.path)) ?? []
            XCTAssertTrue(contents.isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: "skins/blocked-skin/1.0.0").path))
        }
    }

    func testRepositoryCleansAbandonedStagingDirectories() async throws {
        let root = temporaryRoot()
        let abandoned = root.appending(path: ".staging/abandoned")
        try FileManager.default.createDirectory(at: abandoned, withIntermediateDirectories: true)
        try Data("partial".utf8).write(to: abandoned.appending(path: "file"))

        _ = try await SkinRepository(rootURL: root).listInstalled()

        XCTAssertFalse(FileManager.default.fileExists(atPath: abandoned.path))
    }

    func testInventoryDetectsTamperedInstalledFiles() async throws {
        let repository = SkinRepository(rootURL: temporaryRoot())
        let installed = installedValue(try await repository.install(importFixture(id: "tamper-skin", name: "Tamper")))
        try Data("tampered".utf8).write(to: installed.previewURL)

        do {
            _ = try await repository.listInstalled()
            XCTFail("expected tamper detection")
        } catch {
            XCTAssertEqual(error as? SkinRepositoryError, .corruptedInstallation("preview.png"))
        }
    }

    func testPublicRepositoryAPIsRejectTraversalReferences() async throws {
        let root = temporaryRoot()
        let repository = SkinRepository(rootURL: root)

        do {
            try await repository.delete(id: "../outside", version: "1.0.0")
            XCTFail("expected invalid reference")
        } catch {
            XCTAssertEqual(error as? SkinRepositoryError, .invalidReference)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.deletingLastPathComponent().appending(path: "outside").path))
    }

    private func importFixture(id: String, name: String) throws -> ImportedSkinPackage {
        let fixture = try SkinImportFixture.make(id: id, name: name)
        return try SkinPackageImporter().importPackage(data: fixture.archive)
    }

    private func installedValue(_ outcome: SkinInstallOutcome) -> InstalledSkin {
        switch outcome {
        case let .installed(skin), let .alreadyInstalled(skin): skin
        }
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "skin-repository-\(UUID().uuidString)", directoryHint: .isDirectory)
    }
}
