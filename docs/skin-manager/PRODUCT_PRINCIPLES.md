# Codex 皮肤管理器：产品原则

## 产品判断

“世界上最好的产品”没有客观唯一答案。本工具不复制某个产品的外观，而是组合三类已被验证的用户思维：

- Apple：操作结果应可预测、可见且容易撤销，让用户敢于尝试。
- Raycast：围绕一个明确任务缩短路径，先展示足够的来源与兼容信息，再让用户执行安装或切换。
- Visual Studio Code：选择主题时先预览，确认后再提交，降低试错成本。

参考资料：

- [Apple Human Interface Guidelines：Undo and redo](https://developer.apple.com/design/human-interface-guidelines/undo-and-redo/)
- [Raycast Manual：Themes](https://manual.raycast.com/themes)
- [Raycast Manual：Extensions](https://manual.raycast.com/extensions)
- [Visual Studio Code：Color themes](https://code.visualstudio.com/docs/configure/themes)

## 本项目采用的原则

### 1. 只报告真实状态

`active.json` 只代表“上次使用记录”，不等于当前 Codex 页面已经加载皮肤。只有本次注入与运行时校验完成后，界面才能显示“皮肤已验证生效”。

### 2. 主操作描述结果

按钮文案随上下文变化：

- 未使用的皮肤：`切换到此皮肤`
- 上次使用或当前已验证的皮肤：`重新应用`
- 上次操作失败：`重试切换`

用户不需要先理解 CDP、注入器或守护进程。

### 3. 失败后给出最短恢复路径

失败状态同时提供“重试切换”和“查看日志”。同一皮肤允许重新应用，用来修复 Codex 刷新、升级或守护进程中断造成的状态漂移。

### 4. 风险信息在操作前出现

皮肤详情必须明确显示包校验状态和素材使用权。App 不因签名状态或权利声明阻止导入、切换、导出；公开发布和对外分享仍必须保留非商用、同人、无背书和第三方权利边界。

### 5. 默认可逆

“恢复默认”始终是一等操作。管理器不修改、不重签名官方 Codex 应用，也不强制结束 Codex；需要重启时等待用户正常退出。

### 6. 键盘与鼠标同等高效

同一对象的相反操作应放在一起。`.codexskin` 的导入与导出并排出现在顶部工具栏，不再分散在资料库底部和详情菜单；导出入口保持稳定，权利信息作为分享提醒展示，而不是阻断本地流程。

主要路径保留快捷键：`⌘O` 导入、`⇧⌘E` 导出、`⌘↩` 切换或重新应用、`⇧⌘R` 恢复默认。

## 后续路线

下一阶段可加入选择即预览、Enter 确认的临时预览模式。预览必须与真正应用明确区分，并在窗口关闭或取消后自动恢复，不能牺牲状态可信度。
