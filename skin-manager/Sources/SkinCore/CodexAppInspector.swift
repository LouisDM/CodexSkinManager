import Foundation

public enum CodexAppIssueCode: String, Codable, Equatable, Hashable, Sendable {
    case missingExecutable
    case missingNode
    case invalidSignature
    case invalidPort
    case portConflict
    case inspectionFailed
}

public struct CodexAppIssue: Equatable, Sendable {
    public let code: CodexAppIssueCode
    public let detail: String

    public init(code: CodexAppIssueCode, detail: String) {
        self.code = code
        self.detail = detail
    }
}

public enum CodexDebugPortStatus: Equatable, Sendable {
    case available
    case ownedByCodex(pid: Int32)
    case conflict

    public var isUsable: Bool {
        switch self {
        case .available, .ownedByCodex: true
        case .conflict: false
        }
    }

    public var isReady: Bool {
        if case .ownedByCodex = self { return true }
        return false
    }
}

public struct CodexAppInspection: Equatable, Sendable {
    public let appURL: URL
    public let executableURL: URL
    public let nodeURL: URL
    public let signatureValid: Bool
    public let portStatus: CodexDebugPortStatus
    public let issues: [CodexAppIssue]

    public init(
        appURL: URL,
        executableURL: URL,
        nodeURL: URL,
        signatureValid: Bool,
        portStatus: CodexDebugPortStatus,
        issues: [CodexAppIssue]
    ) {
        self.appURL = appURL
        self.executableURL = executableURL
        self.nodeURL = nodeURL
        self.signatureValid = signatureValid
        self.portStatus = portStatus
        self.issues = issues
    }

    public var canApply: Bool { signatureValid && portStatus.isUsable && issues.isEmpty }
    public var canImport: Bool { true }
}

public protocol CodexAppInspecting: Sendable {
    func inspect(appURL: URL, port: Int) async -> CodexAppInspection
}

private struct CodexListenerRecord {
    let pid: Int32
    let endpoints: [String]
    let socketIdentifiers: [String]
}

public struct CodexAppInspector: CodexAppInspecting, Sendable {
    private let processRunner: any ProcessRunning

    public init(processRunner: any ProcessRunning = SystemProcessRunner()) {
        self.processRunner = processRunner
    }

    public func inspect(appURL: URL, port: Int = 9_340) async -> CodexAppInspection {
        let app = appURL.standardizedFileURL
        let executable = app.appending(path: "Contents/MacOS/ChatGPT")
        let node = app.appending(path: "Contents/Resources/cua_node/bin/node")
        var issues: [CodexAppIssue] = []

        let hasExecutable = FileManager.default.isExecutableFile(atPath: executable.path)
        let hasNode = FileManager.default.isExecutableFile(atPath: node.path)
        if !hasExecutable {
            issues.append(CodexAppIssue(code: .missingExecutable, detail: "找不到可执行的官方 Codex：\(executable.path)"))
        }
        if !hasNode {
            issues.append(CodexAppIssue(code: .missingNode, detail: "官方 Codex 缺少内置 Node：\(node.path)"))
        }

        var signatureValid = false
        if hasExecutable, hasNode {
            do {
                let result = try await processRunner.run(ProcessInvocation(
                    executableURL: URL(fileURLWithPath: "/usr/bin/codesign"),
                    arguments: ["--verify", "--deep", "--strict", app.path]
                ))
                signatureValid = result.exitCode == 0
                if !signatureValid {
                    let detail = Self.diagnostic(result, fallback: "官方 Codex 代码签名校验失败")
                    issues.append(CodexAppIssue(code: .invalidSignature, detail: detail))
                }
            } catch {
                issues.append(CodexAppIssue(code: .inspectionFailed, detail: "无法校验官方 Codex 签名：\(error.localizedDescription)"))
            }
        }

        let portStatus: CodexDebugPortStatus
        if !(1 ... 65_535).contains(port) {
            portStatus = .conflict
            issues.append(CodexAppIssue(code: .invalidPort, detail: "非法 CDP 端口：\(port)"))
        } else {
            portStatus = await inspectPort(port, expectedExecutable: executable, issues: &issues)
        }

        return CodexAppInspection(
            appURL: app,
            executableURL: executable,
            nodeURL: node,
            signatureValid: signatureValid,
            portStatus: portStatus,
            issues: issues
        )
    }

    private func inspectPort(
        _ port: Int,
        expectedExecutable: URL,
        issues: inout [CodexAppIssue]
    ) async -> CodexDebugPortStatus {
        let listenerResult: ProcessExecutionResult
        do {
            listenerResult = try await processRunner.run(ProcessInvocation(
                executableURL: URL(fileURLWithPath: "/usr/sbin/lsof"),
                arguments: ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN", "-Fpcdn"]
            ))
        } catch {
            issues.append(CodexAppIssue(code: .inspectionFailed, detail: "无法检查 CDP 端口：\(error.localizedDescription)"))
            return .conflict
        }
        if listenerResult.exitCode != 0 || listenerResult.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .available
        }

        let records = Self.listenerRecords(listenerResult.standardOutput)
        guard !records.isEmpty,
              records.allSatisfy({ !$0.endpoints.isEmpty && $0.endpoints.allSatisfy { $0 == "127.0.0.1:\(port)" } })
        else {
            issues.append(CodexAppIssue(code: .portConflict, detail: "端口 \(port) 未仅绑定到 127.0.0.1"))
            return .conflict
        }

        var officialPIDs: [Int32] = []
        var officialSocketIdentifiers = Set<String>()
        var lookupFailed = false
        for record in records {
            do {
                let executableResult = try await processRunner.run(ProcessInvocation(
                    executableURL: URL(fileURLWithPath: "/usr/sbin/lsof"),
                    arguments: ["-a", "-p", String(record.pid), "-d", "txt", "-Fn"]
                ))
                let paths = executableResult.standardOutput.split(separator: "\n")
                    .filter { $0.first == "n" }
                    .map { String($0.dropFirst()) }
                if executableResult.exitCode == 0, paths.contains(expectedExecutable.path) {
                    officialPIDs.append(record.pid)
                    officialSocketIdentifiers.formUnion(record.socketIdentifiers)
                }
            } catch {
                lookupFailed = true
            }
        }
        guard let ownerPID = officialPIDs.first else {
            let detail = lookupFailed
                ? "无法确认端口 \(port) 的进程归属"
                : "端口 \(port) 不属于官方 Codex"
            issues.append(CodexAppIssue(code: .portConflict, detail: detail))
            return .conflict
        }

        let officialPIDSet = Set(officialPIDs)
        let hasUnrelatedSocket = records.contains { record in
            if officialPIDSet.contains(record.pid) { return false }
            let inheritedSockets = Set(record.socketIdentifiers)
            return inheritedSockets.isEmpty || !inheritedSockets.isSubset(of: officialSocketIdentifiers)
        }
        guard !hasUnrelatedSocket else {
            issues.append(CodexAppIssue(code: .portConflict, detail: "端口 \(port) 存在非官方独立监听器"))
            return .conflict
        }
        return .ownedByCodex(pid: ownerPID)
    }

    private static func diagnostic(_ result: ProcessExecutionResult, fallback: String) -> String {
        let merged = [result.standardError, result.standardOutput]
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return merged.isEmpty ? fallback : merged
    }

    private static func listenerRecords(_ output: String) -> [CodexListenerRecord] {
        var records: [CodexListenerRecord] = []
        var currentPID: Int32?
        var endpoints: [String] = []
        var socketIdentifiers: [String] = []
        func finish() {
            if let currentPID {
                records.append(CodexListenerRecord(
                    pid: currentPID,
                    endpoints: endpoints,
                    socketIdentifiers: socketIdentifiers
                ))
            }
            currentPID = nil
            endpoints = []
            socketIdentifiers = []
        }
        for line in output.split(separator: "\n").map(String.init) {
            if line.first == "p" {
                finish()
                currentPID = Int32(line.dropFirst())
            } else if line.first == "d", currentPID != nil {
                socketIdentifiers.append(String(line.dropFirst()))
            } else if line.first == "n", currentPID != nil {
                endpoints.append(String(line.dropFirst()))
            }
        }
        finish()
        return records
    }
}
