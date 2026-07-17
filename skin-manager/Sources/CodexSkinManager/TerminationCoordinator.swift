import AppKit

@MainActor
final class TerminationCoordinator: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    private var replyingLater = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, model.watcherOwnedThisSession, !replyingLater else { return .terminateNow }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "退出前如何处理当前皮肤？"
        alert.informativeText = "管理器只会处理自己的守护进程，不会退出或强制结束 Codex。"
        alert.addButton(withTitle: "恢复默认并退出")
        alert.addButton(withTitle: "保留当前页面并退出守护")
        alert.addButton(withTitle: "取消")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            replyingLater = true
            Task { @MainActor [weak self, weak model] in
                guard let self, let model else {
                    NSApp.reply(toApplicationShouldTerminate: false)
                    return
                }
                await model.restoreDefault()
                let succeeded = model.active == nil
                replyingLater = false
                NSApp.reply(toApplicationShouldTerminate: succeeded)
            }
            return .terminateLater
        case .alertSecondButtonReturn:
            replyingLater = true
            Task { @MainActor [weak model] in
                await model?.stopOwnedWatcher()
                NSApp.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        default:
            return .terminateCancel
        }
    }
}
