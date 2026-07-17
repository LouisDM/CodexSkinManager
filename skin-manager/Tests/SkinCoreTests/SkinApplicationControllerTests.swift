import Foundation
import XCTest
@testable import SkinCore

final class SkinApplicationControllerTests: XCTestCase {
    func testInitialApplyWaitsForNormalQuitThenLaunchesAndActivates() async throws {
        let fixture = try await ControllerFixture.make(runningResponses: [true, false])

        await fixture.controller.apply(id: fixture.first.id, version: fixture.first.version)

        let history = await fixture.controller.stateHistory()
        let launches = await fixture.lifecycle.launchArguments()
        let active = try await fixture.repository.activeSkin()
        let applied = await fixture.engine.appliedIDs()
        let terminated = await fixture.lifecycle.terminationRequested()
        XCTAssertEqual(history, [
            .idle,
            .checking,
            .waitingForQuit,
            .startingCodex,
            .applying(ActiveSkinRecord(id: fixture.first.id, version: fixture.first.version)),
            .active(ActiveSkinRecord(id: fixture.first.id, version: fixture.first.version)),
        ])
        XCTAssertEqual(launches, [[
            "--remote-debugging-address=127.0.0.1",
            "--remote-debugging-port=9340",
        ]])
        XCTAssertEqual(active, ActiveSkinRecord(id: fixture.first.id, version: fixture.first.version))
        XCTAssertEqual(applied, [fixture.first.id])
        XCTAssertFalse(terminated)
    }

    func testApplyUsesAnExistingVerifiedDebugSessionWithoutRelaunching() async throws {
        let fixture = try await ControllerFixture.make(
            runningResponses: [true],
            portStatus: .ownedByCodex(pid: 42)
        )

        await fixture.controller.apply(id: fixture.first.id, version: fixture.first.version)

        let launches = await fixture.lifecycle.launchArguments()
        let history = await fixture.controller.stateHistory()
        let state = await fixture.controller.currentState()
        XCTAssertEqual(launches, [])
        XCTAssertFalse(history.contains(.waitingForQuit))
        XCTAssertEqual(state, .active(ActiveSkinRecord(id: fixture.first.id, version: fixture.first.version)))
    }

    func testCancellationWhileWaitingNeverTerminatesCodexOrChangesActiveSkin() async throws {
        let fixture = try await ControllerFixture.make(runningResponses: Array(repeating: true, count: 50), slowClock: true)
        let task = Task { await fixture.controller.apply(id: fixture.first.id, version: fixture.first.version) }
        try await waitUntil { await fixture.controller.currentState() == .waitingForQuit }

        await fixture.controller.cancelWaiting()
        await task.value

        let state = await fixture.controller.currentState()
        let active = try await fixture.repository.activeSkin()
        let launches = await fixture.lifecycle.launchArguments()
        let terminated = await fixture.lifecycle.terminationRequested()
        XCTAssertEqual(state, .cancelled)
        XCTAssertNil(active)
        XCTAssertEqual(launches, [])
        XCTAssertFalse(terminated)
    }

    func testFailedSkinSwitchRollsBackToPreviousSkin() async throws {
        let fixture = try await ControllerFixture.make(runningResponses: [false], failingID: "second-skin")
        await fixture.controller.apply(id: fixture.first.id, version: fixture.first.version)
        await fixture.lifecycle.replaceRunningResponses([true])

        await fixture.controller.apply(id: fixture.second.id, version: fixture.second.version)

        let active = try await fixture.repository.activeSkin()
        let applied = await fixture.engine.appliedIDs()
        let state = await fixture.controller.currentState()
        let ownsWatcher = await fixture.controller.ownsWatcher()
        XCTAssertEqual(active, ActiveSkinRecord(id: fixture.first.id, version: fixture.first.version))
        XCTAssertEqual(applied, [fixture.first.id, fixture.second.id, fixture.first.id])
        XCTAssertTrue(ownsWatcher)
        guard case let .failed(message) = state else {
            return XCTFail("expected failed state after rollback")
        }
        XCTAssertTrue(message.contains("已恢复"))
    }

    func testRestoreClearsActiveStateAndStopsOnlyTheOwnedWatcher() async throws {
        let fixture = try await ControllerFixture.make(runningResponses: [false])
        await fixture.controller.apply(id: fixture.first.id, version: fixture.first.version)

        await fixture.controller.restore()

        let active = try await fixture.repository.activeSkin()
        let restored = await fixture.engine.restoredIDs()
        let state = await fixture.controller.currentState()
        let terminated = await fixture.lifecycle.terminationRequested()
        XCTAssertNil(active)
        XCTAssertEqual(restored, [fixture.first.id])
        XCTAssertEqual(state, .idle)
        XCTAssertFalse(terminated)
    }

    func testInspectorFailureStopsBeforeLaunchOrInjection() async throws {
        let fixture = try await ControllerFixture.make(runningResponses: [false], canApply: false)

        await fixture.controller.apply(id: fixture.first.id, version: fixture.first.version)

        let state = await fixture.controller.currentState()
        let launches = await fixture.lifecycle.launchArguments()
        let applied = await fixture.engine.appliedIDs()
        guard case .failed = state else { return XCTFail("expected failure") }
        XCTAssertEqual(launches, [])
        XCTAssertEqual(applied, [])
    }

    func testInitialInjectionFailureStopsWatcherAndReportsNoOwnership() async throws {
        let fixture = try await ControllerFixture.make(runningResponses: [false], failingID: "first-skin")

        await fixture.controller.apply(id: fixture.first.id, version: fixture.first.version)

        let ownsWatcher = await fixture.controller.ownsWatcher()
        let stopCount = await fixture.engine.stopCount()
        let active = try await fixture.repository.activeSkin()
        XCTAssertFalse(ownsWatcher)
        XCTAssertEqual(stopCount, 1)
        XCTAssertNil(active)
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        condition: @escaping @Sendable () async -> Bool
    ) async throws {
        let started = DispatchTime.now().uptimeNanoseconds
        while !(await condition()) {
            if DispatchTime.now().uptimeNanoseconds - started > timeoutNanoseconds {
                XCTFail("timed out waiting for controller state")
                return
            }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
    }
}

private struct ControllerFixture {
    let repository: SkinRepository
    let first: InstalledSkin
    let second: InstalledSkin
    let lifecycle: FakeCodexLifecycle
    let engine: FakeSkinEngine
    let controller: SkinApplicationController

    static func make(
        runningResponses: [Bool],
        portStatus: CodexDebugPortStatus = .available,
        failingID: String? = nil,
        canApply: Bool = true,
        slowClock: Bool = false
    ) async throws -> ControllerFixture {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "skin-controller-\(UUID().uuidString)", directoryHint: .isDirectory)
        let repository = SkinRepository(rootURL: root)
        let first = try await install(id: "first-skin", name: "First", repository: repository)
        let second = try await install(id: "second-skin", name: "Second", repository: repository)
        let appURL = URL(fileURLWithPath: "/Applications/ChatGPT.app")
        let inspection = CodexAppInspection(
            appURL: appURL,
            executableURL: appURL.appending(path: "Contents/MacOS/ChatGPT"),
            nodeURL: appURL.appending(path: "Contents/Resources/cua_node/bin/node"),
            signatureValid: canApply,
            portStatus: portStatus,
            issues: canApply ? [] : [CodexAppIssue(code: .invalidSignature, detail: "invalid fixture")]
        )
        let inspector = FakeCodexInspector(result: inspection)
        let lifecycle = FakeCodexLifecycle(runningResponses: runningResponses)
        let engine = FakeSkinEngine(failingID: failingID)
        let resources = SkinRuntimeResources(
            nodeURL: inspection.nodeURL,
            injectorURL: root.appending(path: "Engine/injector.mjs"),
            templatesURL: root.appending(path: "Templates"),
            stateRootURL: root.appending(path: "runtime"),
            port: 9_340
        )
        let clock: any SkinApplicationClock = slowClock ? SlowTestClock() : ImmediateTestClock()
        let controller = SkinApplicationController(
            repository: repository,
            inspector: inspector,
            lifecycle: lifecycle,
            engine: engine,
            resources: resources,
            appURL: appURL,
            clock: clock
        )
        return ControllerFixture(
            repository: repository,
            first: first,
            second: second,
            lifecycle: lifecycle,
            engine: engine,
            controller: controller
        )
    }

    private static func install(id: String, name: String, repository: SkinRepository) async throws -> InstalledSkin {
        let fixture = try SkinImportFixture.make(id: id, name: name)
        let imported = try SkinPackageImporter().importPackage(data: fixture.archive)
        switch try await repository.install(imported) {
        case let .installed(skin), let .alreadyInstalled(skin): return skin
        }
    }
}

private struct FakeCodexInspector: CodexAppInspecting {
    let result: CodexAppInspection
    func inspect(appURL: URL, port: Int) async -> CodexAppInspection { result }
}

private actor FakeCodexLifecycle: CodexApplicationLifecycle {
    private var runningResponses: [Bool]
    private var launches: [[String]] = []
    private(set) var receivedTerminationRequest = false

    init(runningResponses: [Bool]) {
        self.runningResponses = runningResponses
    }

    func isRunning(executableURL: URL) async -> Bool {
        guard !runningResponses.isEmpty else { return false }
        return runningResponses.removeFirst()
    }

    func launch(appURL: URL, arguments: [String]) async throws {
        launches.append(arguments)
    }

    func replaceRunningResponses(_ values: [Bool]) { runningResponses = values }
    func launchArguments() -> [[String]] { launches }
    func terminationRequested() -> Bool { receivedTerminationRequest }
}

private actor FakeSkinEngine: SkinEngineControlling {
    private let failingID: String?
    private var applied: [String] = []
    private var restored: [String] = []
    private var stops = 0

    init(failingID: String?) { self.failingID = failingID }

    func apply(_ package: StoredSkinPackage, resources: SkinRuntimeResources) async throws {
        applied.append(package.manifest.id)
        if package.manifest.id == failingID { throw FakeEngineError.injectionFailed }
    }

    func restore(_ package: StoredSkinPackage, resources: SkinRuntimeResources) async throws {
        restored.append(package.manifest.id)
    }

    func stopWatcher() async { stops += 1 }
    func appliedIDs() -> [String] { applied }
    func restoredIDs() -> [String] { restored }
    func stopCount() -> Int { stops }
}

private enum FakeEngineError: Error { case injectionFailed }

private struct ImmediateTestClock: SkinApplicationClock {
    func sleepForPoll() async throws { await Task.yield() }
}

private struct SlowTestClock: SkinApplicationClock {
    func sleepForPoll() async throws { try await Task.sleep(nanoseconds: 10_000_000) }
}
