import Foundation
import XCTest
@testable import SkinCore

final class CodexAppInspectorTests: XCTestCase {
    func testUsesFixedCodesignArgumentsAndAcceptsAFreeDebugPort() async throws {
        let appURL = try makeAppFixture()
        let runner = RecordingProcessRunner(responses: [
            ProcessExecutionResult(exitCode: 0, standardOutput: "", standardError: ""),
            ProcessExecutionResult(exitCode: 1, standardOutput: "", standardError: ""),
        ])
        let before = try recursivePaths(at: appURL)

        let result = await CodexAppInspector(processRunner: runner).inspect(appURL: appURL, port: 9_340)

        XCTAssertTrue(result.canApply)
        XCTAssertTrue(result.canImport)
        XCTAssertEqual(result.portStatus, .available)
        let invocations = await runner.invocations()
        XCTAssertEqual(invocations, [
            ProcessInvocation(
                executableURL: URL(fileURLWithPath: "/usr/bin/codesign"),
                arguments: ["--verify", "--deep", "--strict", appURL.path]
            ),
            ProcessInvocation(
                executableURL: URL(fileURLWithPath: "/usr/sbin/lsof"),
                arguments: ["-nP", "-iTCP:9340", "-sTCP:LISTEN", "-Fpcdn"]
            ),
        ])
        XCTAssertEqual(try recursivePaths(at: appURL), before, "inspection must never write inside the official app")
    }

    func testInvalidOfficialSignatureBlocksApplyButNotImport() async throws {
        let appURL = try makeAppFixture()
        let runner = RecordingProcessRunner(responses: [
            ProcessExecutionResult(exitCode: 1, standardOutput: "", standardError: "a sealed resource is missing or invalid"),
            ProcessExecutionResult(exitCode: 1, standardOutput: "", standardError: ""),
        ])

        let result = await CodexAppInspector(processRunner: runner).inspect(appURL: appURL, port: 9_340)

        XCTAssertFalse(result.canApply)
        XCTAssertTrue(result.canImport)
        XCTAssertEqual(result.issues.map(\.code), [.invalidSignature])
        XCTAssertTrue(result.issues[0].detail.contains("sealed resource"))
    }

    func testRejectsMissingExecutablesAndDoesNotRunCodesign() async throws {
        let appURL = FileManager.default.temporaryDirectory
            .appending(path: "missing-codex-\(UUID().uuidString).app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        let runner = RecordingProcessRunner(responses: [
            ProcessExecutionResult(exitCode: 1, standardOutput: "", standardError: ""),
        ])

        let result = await CodexAppInspector(processRunner: runner).inspect(appURL: appURL, port: 9_340)

        XCTAssertFalse(result.canApply)
        XCTAssertEqual(Set(result.issues.map(\.code)), [.missingExecutable, .missingNode])
        let invocations = await runner.invocations()
        XCTAssertEqual(invocations.map(\.executableURL.path), ["/usr/sbin/lsof"])
    }

    func testAcceptsOnlyAnOfficialListenerBoundToIPv4Loopback() async throws {
        let appURL = try makeAppFixture()
        let executable = appURL.appending(path: "Contents/MacOS/ChatGPT").path
        let runner = RecordingProcessRunner(responses: [
            ProcessExecutionResult(exitCode: 0, standardOutput: "", standardError: ""),
            ProcessExecutionResult(exitCode: 0, standardOutput: "p481\ncChatGPT\nn127.0.0.1:9340\n", standardError: ""),
            ProcessExecutionResult(exitCode: 0, standardOutput: "n\(executable)\n", standardError: ""),
        ])

        let result = await CodexAppInspector(processRunner: runner).inspect(appURL: appURL, port: 9_340)

        XCTAssertTrue(result.canApply)
        XCTAssertEqual(result.portStatus, .ownedByCodex(pid: 481))
        let invocations = await runner.invocations()
        XCTAssertEqual(invocations.last, ProcessInvocation(
            executableURL: URL(fileURLWithPath: "/usr/sbin/lsof"),
            arguments: ["-a", "-p", "481", "-d", "txt", "-Fn"]
        ))
    }

    func testAcceptsAnOfficialListenerWhenAChildInheritedTheSameSocket() async throws {
        let appURL = try makeAppFixture()
        let executable = appURL.appending(path: "Contents/MacOS/ChatGPT").path
        let inheritedExecutable = "/tmp/Codex Computer Use.app/Contents/MacOS/SkyComputerUseService"
        let runner = RecordingProcessRunner(responses: [
            ProcessExecutionResult(exitCode: 0, standardOutput: "", standardError: ""),
            ProcessExecutionResult(
                exitCode: 0,
                standardOutput: "p481\ncChatGPT\nf60\nd0xabc\nn127.0.0.1:9340\np482\ncSkyComputerUseService\nf60\nd0xabc\nn127.0.0.1:9340\n",
                standardError: ""
            ),
            ProcessExecutionResult(exitCode: 0, standardOutput: "n\(executable)\n", standardError: ""),
            ProcessExecutionResult(exitCode: 0, standardOutput: "n\(inheritedExecutable)\n", standardError: ""),
        ])

        let result = await CodexAppInspector(processRunner: runner).inspect(appURL: appURL, port: 9_340)

        XCTAssertTrue(result.canApply)
        XCTAssertEqual(result.portStatus, .ownedByCodex(pid: 481))
        XCTAssertTrue(result.issues.isEmpty)
    }

    func testRejectsAForeignListenerUsingASeparateSocketOnTheSamePort() async throws {
        let appURL = try makeAppFixture()
        let executable = appURL.appending(path: "Contents/MacOS/ChatGPT").path
        let runner = RecordingProcessRunner(responses: [
            ProcessExecutionResult(exitCode: 0, standardOutput: "", standardError: ""),
            ProcessExecutionResult(
                exitCode: 0,
                standardOutput: "p481\ncChatGPT\nf60\nd0xabc\nn127.0.0.1:9340\np999\ncForeign\nf61\nd0xdef\nn127.0.0.1:9340\n",
                standardError: ""
            ),
            ProcessExecutionResult(exitCode: 0, standardOutput: "n\(executable)\n", standardError: ""),
            ProcessExecutionResult(exitCode: 0, standardOutput: "n/tmp/foreign\n", standardError: ""),
        ])

        let result = await CodexAppInspector(processRunner: runner).inspect(appURL: appURL, port: 9_340)

        XCTAssertFalse(result.canApply)
        XCTAssertEqual(result.portStatus, .conflict)
        XCTAssertEqual(result.issues.map(\.code), [.portConflict])
    }

    func testRejectsWildcardOrForeignDebugListeners() async throws {
        let appURL = try makeAppFixture()
        let runner = RecordingProcessRunner(responses: [
            ProcessExecutionResult(exitCode: 0, standardOutput: "", standardError: ""),
            ProcessExecutionResult(exitCode: 0, standardOutput: "p999\ncnode\nn*:9340\n", standardError: ""),
        ])

        let result = await CodexAppInspector(processRunner: runner).inspect(appURL: appURL, port: 9_340)

        XCTAssertFalse(result.canApply)
        XCTAssertEqual(result.portStatus, .conflict)
        XCTAssertEqual(result.issues.map(\.code), [.portConflict])
    }

    private func makeAppFixture() throws -> URL {
        let app = FileManager.default.temporaryDirectory
            .appending(path: "ChatGPT-\(UUID().uuidString).app", directoryHint: .isDirectory)
        let executable = app.appending(path: "Contents/MacOS/ChatGPT")
        let node = app.appending(path: "Contents/Resources/cua_node/bin/node")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: node.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: executable)
        try Data("#!/bin/sh\n".utf8).write(to: node)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: node.path)
        return app
    }

    private func recursivePaths(at root: URL) throws -> [String] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        return enumerator.compactMap { ($0 as? URL)?.path.replacingOccurrences(of: root.path, with: "") }.sorted()
    }
}

private actor RecordingProcessRunner: ProcessRunning {
    private var recorded: [ProcessInvocation] = []
    private var responses: [ProcessExecutionResult]

    init(responses: [ProcessExecutionResult]) {
        self.responses = responses
    }

    func run(_ invocation: ProcessInvocation) async throws -> ProcessExecutionResult {
        recorded.append(invocation)
        guard !responses.isEmpty else { throw TestProcessError.noResponse }
        return responses.removeFirst()
    }

    func invocations() -> [ProcessInvocation] { recorded }
}

private enum TestProcessError: Error {
    case noResponse
}
