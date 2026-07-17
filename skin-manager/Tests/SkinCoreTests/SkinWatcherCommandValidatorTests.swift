import Foundation
import XCTest
@testable import SkinCore

final class SkinWatcherCommandValidatorTests: XCTestCase {
    private let node = URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node")
    private let injector = URL(fileURLWithPath: "/Users/tester/Applications/Codex 皮肤管理器.app/Contents/Resources/Engine/injector.mjs")
    private let state = URL(fileURLWithPath: "/Users/tester/Library/Application Support/CodexSkinManager/runtime")

    func testAcceptsOnlyTheExactManagerWatcherCommand() {
        let command = "\(node.path) \(injector.path) --watch --port 9340 --skin /tmp/skin --templates /tmp/templates --state-root \(state.path)"

        XCTAssertTrue(SkinWatcherCommandValidator.isOwnedWatcher(
            command: command,
            nodeURL: node,
            injectorURL: injector,
            stateRootURL: state
        ))
    }

    func testNeverAcceptsCodexOrSubstringImpostors() {
        let codex = "/Applications/ChatGPT.app/Contents/MacOS/ChatGPT --watch \(injector.path) --state-root \(state.path)"
        let wrapper = "/tmp/wrapper \(node.path) \(injector.path) --watch --state-root \(state.path)"
        let once = "\(node.path) \(injector.path) --once --state-root \(state.path)"
        let otherState = "\(node.path) \(injector.path) --watch --state-root /tmp/other"

        for command in [codex, wrapper, once, otherState] {
            XCTAssertFalse(SkinWatcherCommandValidator.isOwnedWatcher(
                command: command,
                nodeURL: node,
                injectorURL: injector,
                stateRootURL: state
            ), command)
        }
    }
}
