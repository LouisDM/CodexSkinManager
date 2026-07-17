import AppKit
import Darwin
import Foundation

public struct SkinRuntimeResources: Equatable, Sendable {
    public let nodeURL: URL
    public let injectorURL: URL
    public let templatesURL: URL
    public let stateRootURL: URL
    public let port: Int

    public init(nodeURL: URL, injectorURL: URL, templatesURL: URL, stateRootURL: URL, port: Int = 9_340) {
        self.nodeURL = nodeURL
        self.injectorURL = injectorURL
        self.templatesURL = templatesURL
        self.stateRootURL = stateRootURL
        self.port = port
    }
}

public enum SkinApplicationState: Equatable, Sendable {
    case idle
    case checking
    case waitingForQuit
    case startingCodex
    case applying(ActiveSkinRecord)
    case active(ActiveSkinRecord)
    case restoring
    case cancelled
    case failed(String)
}

public protocol CodexApplicationLifecycle: Sendable {
    func isRunning(executableURL: URL) async -> Bool
    func launch(appURL: URL, arguments: [String]) async throws
}

public protocol SkinEngineControlling: Sendable {
    func apply(_ package: StoredSkinPackage, resources: SkinRuntimeResources) async throws
    func restore(_ package: StoredSkinPackage, resources: SkinRuntimeResources) async throws
    func stopWatcher() async
}

public protocol SkinApplicationClock: Sendable {
    func sleepForPoll() async throws
}

public struct SystemSkinApplicationClock: SkinApplicationClock {
    public init() {}
    public func sleepForPoll() async throws {
        try await Task.sleep(for: .milliseconds(500))
    }
}

public struct SystemCodexApplicationLifecycle: CodexApplicationLifecycle {
    public init() {}

    public func isRunning(executableURL: URL) async -> Bool {
        await MainActor.run {
            let expected = executableURL.resolvingSymlinksInPath().standardizedFileURL
            return NSWorkspace.shared.runningApplications.contains {
                $0.executableURL?.resolvingSymlinksInPath().standardizedFileURL == expected
            }
        }
    }

    public func launch(appURL: URL, arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Task { @MainActor in
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.arguments = arguments
                configuration.activates = true
                configuration.createsNewApplicationInstance = true
                NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: ()) }
                }
            }
        }
    }
}

public enum SkinEngineError: Error, LocalizedError, Sendable {
    case commandFailed(String)
    case watcherFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .commandFailed(message): "皮肤注入失败：\(message)"
        case let .watcherFailed(message): "皮肤守护进程启动失败：\(message)"
        }
    }
}

enum SkinWatcherCommandValidator {
    static func isOwnedWatcher(
        command: String,
        nodeURL: URL,
        injectorURL: URL,
        stateRootURL: URL
    ) -> Bool {
        let command = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.contains("\0"), !command.contains("\n") else { return false }
        let exactPrefix = "\(nodeURL.path) \(injectorURL.path) "
        guard command.hasPrefix(exactPrefix), containsArgument("--watch", in: command) else { return false }
        return containsArgument("--state-root", value: stateRootURL.path, in: command)
    }

    private static func containsArgument(_ argument: String, in command: String) -> Bool {
        command == argument
            || command.hasPrefix("\(argument) ")
            || command.hasSuffix(" \(argument)")
            || command.contains(" \(argument) ")
    }

    private static func containsArgument(_ argument: String, value: String, in command: String) -> Bool {
        let pair = "\(argument) \(value)"
        return command == pair
            || command.hasPrefix("\(pair) ")
            || command.hasSuffix(" \(pair)")
            || command.contains(" \(pair) ")
    }
}

public actor SystemSkinEngineController: SkinEngineControlling {
    private let processRunner: any ProcessRunning
    private var watcher: Process?
    private var watcherLog: FileHandle?
    private var lastResources: SkinRuntimeResources?

    public init(processRunner: any ProcessRunning = SystemProcessRunner()) {
        self.processRunner = processRunner
    }

    public func apply(_ package: StoredSkinPackage, resources: SkinRuntimeResources) async throws {
        guard await stopWatcher(resources: resources) else {
            throw SkinEngineError.watcherFailed("旧的管理器守护进程未能正常退出")
        }
        lastResources = resources
        try FileManager.default.createDirectory(at: resources.stateRootURL, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: resources.stateRootURL.appending(path: "skin-disabled"))
        let result = try await processRunner.run(ProcessInvocation(
            executableURL: resources.nodeURL,
            arguments: arguments(mode: "--once", package: package, resources: resources, wait: true)
        ))
        guard result.exitCode == 0 else {
            throw SkinEngineError.commandFailed(Self.diagnostic(result))
        }
        try await launchWatcher(package, resources: resources)
    }

    public func restore(_ package: StoredSkinPackage, resources: SkinRuntimeResources) async throws {
        lastResources = resources
        let result = try await processRunner.run(ProcessInvocation(
            executableURL: resources.nodeURL,
            arguments: arguments(mode: "--restore", package: package, resources: resources, wait: false)
        ))
        _ = await stopWatcher(resources: resources)
        guard result.exitCode == 0 else {
            throw SkinEngineError.commandFailed(Self.diagnostic(result))
        }
    }

    public func stopWatcher() async {
        if let lastResources {
            _ = await stopWatcher(resources: lastResources)
        } else {
            _ = await stopInMemoryWatcher()
        }
    }

    private func launchWatcher(_ package: StoredSkinPackage, resources: SkinRuntimeResources) async throws {
        let logURL = resources.stateRootURL.appending(path: "injector.log")
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        let log = try FileHandle(forWritingTo: logURL)
        try log.seekToEnd()
        let process = Process()
        process.executableURL = resources.nodeURL
        process.arguments = arguments(mode: "--watch", package: package, resources: resources, wait: false)
        process.standardOutput = log
        process.standardError = log
        do {
            try process.run()
            try await Task.sleep(for: .milliseconds(150))
            guard process.isRunning else {
                throw SkinEngineError.watcherFailed("进程提前退出，详见 \(logURL.path)")
            }
            watcher = process
            watcherLog = log
            lastResources = resources
            try Data("\(process.processIdentifier)\n".utf8).write(
                to: resources.stateRootURL.appending(path: "injector.pid"),
                options: .atomic
            )
        } catch {
            log.closeFile()
            throw error
        }
    }

    private func stopWatcher(resources: SkinRuntimeResources) async -> Bool {
        guard await stopInMemoryWatcher() else { return false }
        let pidURL = resources.stateRootURL.appending(path: "injector.pid")
        guard let data = try? Data(contentsOf: pidURL),
              let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let pid = Int32(raw), pid > 1, pid != getpid()
        else {
            try? FileManager.default.removeItem(at: pidURL)
            return true
        }
        guard Self.isAlive(pid) else {
            try? FileManager.default.removeItem(at: pidURL)
            return true
        }
        let invocation = ProcessInvocation(
            executableURL: URL(fileURLWithPath: "/bin/ps"),
            arguments: ["-p", String(pid), "-o", "command="]
        )
        guard let result = try? await processRunner.run(invocation),
              result.exitCode == 0,
              SkinWatcherCommandValidator.isOwnedWatcher(
                  command: result.standardOutput,
                  nodeURL: resources.nodeURL,
                  injectorURL: resources.injectorURL,
                  stateRootURL: resources.stateRootURL
              )
        else {
            // A stale/reused PID must never authorize terminating an unrelated process.
            try? FileManager.default.removeItem(at: pidURL)
            return true
        }
        guard Darwin.kill(pid, SIGTERM) == 0 || errno == ESRCH else { return false }
        for _ in 0 ..< 50 {
            if !Self.isAlive(pid) {
                try? FileManager.default.removeItem(at: pidURL)
                return true
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    private func stopInMemoryWatcher() async -> Bool {
        guard let watcher else {
            watcherLog?.closeFile()
            watcherLog = nil
            return true
        }
        if watcher.isRunning {
            watcher.terminate()
            for _ in 0 ..< 30 {
                if !watcher.isRunning { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        let stopped = !watcher.isRunning
        self.watcher = nil
        watcherLog?.closeFile()
        watcherLog = nil
        return stopped
    }

    private static func isAlive(_ pid: Int32) -> Bool {
        Darwin.kill(pid, 0) == 0 || errno == EPERM
    }

    private func arguments(
        mode: String,
        package: StoredSkinPackage,
        resources: SkinRuntimeResources,
        wait: Bool
    ) -> [String] {
        var values = [
            resources.injectorURL.path,
            mode,
            "--port", String(resources.port),
            "--target-url-prefix", "app://",
            "--skin", package.installed.directoryURL.path,
            "--templates", resources.templatesURL.path,
            "--state-root", resources.stateRootURL.path,
        ]
        if wait { values.append(contentsOf: ["--wait-timeout", "40000"]) }
        return values
    }

    private static func diagnostic(_ result: ProcessExecutionResult) -> String {
        let message = [result.standardError, result.standardOutput]
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? "helper exited with code \(result.exitCode)" : message
    }
}

public actor SkinApplicationController {
    private let repository: SkinRepository
    private let inspector: any CodexAppInspecting
    private let lifecycle: any CodexApplicationLifecycle
    private let engine: any SkinEngineControlling
    private let resources: SkinRuntimeResources
    private let appURL: URL
    private let clock: any SkinApplicationClock
    private var stateHandler: (@Sendable (SkinApplicationState) -> Void)?

    private var state: SkinApplicationState = .idle
    private var history: [SkinApplicationState] = [.idle]
    private var waitingCancelled = false
    private var ownsDebugSession = false

    public init(
        repository: SkinRepository,
        inspector: any CodexAppInspecting = CodexAppInspector(),
        lifecycle: any CodexApplicationLifecycle = SystemCodexApplicationLifecycle(),
        engine: any SkinEngineControlling = SystemSkinEngineController(),
        resources: SkinRuntimeResources,
        appURL: URL = URL(fileURLWithPath: "/Applications/ChatGPT.app"),
        clock: any SkinApplicationClock = SystemSkinApplicationClock(),
        stateHandler: (@Sendable (SkinApplicationState) -> Void)? = nil
    ) {
        self.repository = repository
        self.inspector = inspector
        self.lifecycle = lifecycle
        self.engine = engine
        self.resources = resources
        self.appURL = appURL
        self.clock = clock
        self.stateHandler = stateHandler
    }

    public func currentState() -> SkinApplicationState { state }
    public func stateHistory() -> [SkinApplicationState] { history }
    public func ownsWatcher() -> Bool { ownsDebugSession }

    public func setStateHandler(_ handler: (@Sendable (SkinApplicationState) -> Void)?) {
        stateHandler = handler
        handler?(state)
    }

    public func cancelWaiting() {
        guard state == .waitingForQuit else { return }
        waitingCancelled = true
    }

    public func apply(id: String, version: String) async {
        waitingCancelled = false
        transition(.checking)
        let inspection = await inspector.inspect(appURL: appURL, port: resources.port)
        guard inspection.canApply else {
            transition(.failed(inspection.issues.map(\.detail).joined(separator: "\n")))
            return
        }
        let requested = ActiveSkinRecord(id: id, version: version)
        let package: StoredSkinPackage
        let previous: ActiveSkinRecord?
        do {
            package = try await repository.load(id: id, version: version)
            previous = try await repository.activeSkin()
        } catch {
            transition(.failed(error.localizedDescription))
            return
        }

        let debugReady = inspection.portStatus.isReady || ownsDebugSession
        if !debugReady, await lifecycle.isRunning(executableURL: inspection.executableURL) {
            transition(.waitingForQuit)
            do {
                while await lifecycle.isRunning(executableURL: inspection.executableURL) {
                    if waitingCancelled {
                        transition(.cancelled)
                        return
                    }
                    try await clock.sleepForPoll()
                }
            } catch {
                transition(.cancelled)
                return
            }
            if waitingCancelled {
                transition(.cancelled)
                return
            }
        }

        if !debugReady {
            transition(.startingCodex)
            do {
                try await lifecycle.launch(appURL: inspection.appURL, arguments: [
                    "--remote-debugging-address=127.0.0.1",
                    "--remote-debugging-port=\(resources.port)",
                ])
            } catch {
                transition(.failed("无法启动官方 Codex：\(error.localizedDescription)"))
                return
            }
        }

        transition(.applying(requested))
        do {
            try await engine.apply(package, resources: resources)
            try await repository.setActive(id: id, version: version)
            ownsDebugSession = true
            transition(.active(requested))
        } catch {
            await rollback(previous: previous, failed: requested, originalError: error)
        }
    }

    public func restore() async {
        transition(.restoring)
        do {
            guard let active = try await repository.activeSkin() else {
                await engine.stopWatcher()
                ownsDebugSession = false
                transition(.idle)
                return
            }
            let package = try await repository.load(id: active.id, version: active.version)
            try await engine.restore(package, resources: resources)
            try await repository.clearActive()
            ownsDebugSession = false
            transition(.idle)
        } catch {
            transition(.failed("恢复默认界面失败：\(error.localizedDescription)"))
        }
    }

    public func stopOwnedWatcher() async {
        await engine.stopWatcher()
        ownsDebugSession = false
    }

    private func rollback(previous: ActiveSkinRecord?, failed: ActiveSkinRecord, originalError: Error) async {
        guard let previous, previous != failed else {
            await engine.stopWatcher()
            ownsDebugSession = false
            transition(.failed("应用皮肤失败：\(originalError.localizedDescription)"))
            return
        }
        do {
            let previousPackage = try await repository.load(id: previous.id, version: previous.version)
            try await engine.apply(previousPackage, resources: resources)
            try await repository.setActive(id: previous.id, version: previous.version)
            ownsDebugSession = true
            transition(.failed("应用皮肤失败，已恢复先前皮肤：\(originalError.localizedDescription)"))
        } catch {
            await engine.stopWatcher()
            ownsDebugSession = false
            transition(.failed("应用失败且无法恢复先前皮肤：\(error.localizedDescription)"))
        }
    }

    private func transition(_ newState: SkinApplicationState) {
        state = newState
        history.append(newState)
        stateHandler?(newState)
    }
}
