# Codex 皮肤管理器：架构与维护边界

## 目录

- `skin-manager/`：Swift Package；包含 `SkinCore`、SwiftUI 应用和单元测试。
- `skin-manager/Sources/CodexSkinManager/Resources/Engine/`：管理器拥有的通用 CDP 注入与页面修复引擎。
- `skin-manager/Sources/CodexSkinManager/Resources/Templates/`：经过允许列表限制的内置 CSS 模板。
- `skin-manager/Sources/CodexSkinManager/Resources/BuiltinSkins/`：内置皮肤数据、预览、图片和权利声明。
- `scripts/build_codex_skin_manager_app.py`：构建、临时签名并原子安装 macOS `.app`。
- `tests/`：资源、浏览器/CDP、应用包和隔离启动验收。

## 安全边界

`.codexskin` 包只能携带声明过的 JSON、PNG/JPEG、预览和许可文本。包内 CSS、JavaScript、可执行文件、符号链接、远程 URL 和路径穿越均被拒绝。皮肤只能选择管理器内置模板；跨入渲染进程的数据为校验后的结构化数据。

管理器只接受回环地址上的 CDP 端点，并检查 9340 端口归属。它不修改 `/Applications/ChatGPT.app`，不替换官方签名，也不会向外网开放调试端口。

## 切换流程

1. 检查官方应用路径、签名、Node 运行时和 9340 端口归属。
2. 如 Codex 正以普通模式运行，等待用户使用 `⌘Q` 正常退出。
3. 以绑定 `127.0.0.1:9340` 的本地调试参数启动官方 Codex。
4. 根据皮肤包的 `template` 选择内置模板，将本地声明图片转换为 data URL。
5. 一次性注入并校验目标页面，再启动管理器拥有的修复守护进程。
6. 校验成功后写入活动记录，并在本次进程内标记为“已验证生效”。

## 状态语义

- `active.json`：最近一次成功应用的持久记录。
- `SkinApplicationState.active`：本次管理器进程已经完成注入与校验。
- 应用启动时不得从 `active.json` 直接推导 `SkinApplicationState.active`。
- “最近使用”和“已验证生效”必须在 UI 中使用不同文案与图标。

## 模板契约

模板根类由通用引擎生成：

- 玄刃夜行：`codex-skin-template-nightblade-v1`
- 赤莲业火：`codex-skin-template-red-lotus-v1`

模板装饰节点必须使用通用 ID `codex-skin-manager-chrome`。不得重新引入旧启动器专属的 `codex-meng-chuan-*` 根类或节点 ID。

## 验证命令

```bash
cd skin-manager && swift test && swift build -c release
cd .. && npm run test:manager
python3 scripts/build_codex_skin_manager_app.py --install
python3 tests/test_codex_skin_manager_bundle.py --installed
python3 tests/test_skin_manager_end_to_end.py
```

浏览器/CDP 测试默认使用本机 Google Chrome；也可通过 `PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH` 指定 Chromium 可执行文件。
