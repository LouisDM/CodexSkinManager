# Codex 皮肤管理器：架构与维护边界

## 目录

- `skin-manager/`：Swift Package；包含 `SkinCore`、SwiftUI 应用和单元测试。
- `skin-manager/Sources/CodexSkinManager/Resources/Engine/`：管理器拥有的通用 CDP 注入与页面修复引擎。
- `skin-manager/Sources/CodexSkinManager/Resources/Templates/`：经过允许列表限制的内置 CSS 模板。
- `skin-manager/Sources/CodexSkinManager/Resources/BuiltinSkins/`：内置皮肤数据、预览、图片和权利声明。
- `scripts/build_codex_skin_manager_app.py`：构建、临时签名并原子安装 macOS `.app`。
- `scripts/build_release_assets.py`：调用 `SkinReleasePackager` 与核心导出器，生成确定性的公开皮肤包、应用 ZIP 和 SHA-256 清单。
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

## 公开发行契约

- 公开包必须使用不会覆盖既有私用包内容的递增语义版本；同 ID 内容或权利边界变化时必须升版本。
- `.codexskin` 必须由 `SkinPackageExporter` 生成，使用项目支持的 stored ZIP v1，不允许另行手工压缩。
- 导出器会基于已经净化并落盘的文件重建 manifest。回导同 ID/版本时，资料库比较稳定 manifest 元数据与实际文件内容，不比较 JSON 排版或净化前的旧描述符；实际名称、模板、作者或文件内容不同仍判定为版本冲突。
- `rights.json` 必须声明允许重新分发、禁止商业使用、同人、非官方和无背书。
- `LICENSES/assets.txt` 必须随包保留；公开许可只覆盖 OPCspace 可控制的 AI 辅助原创图像，不授予底层角色、作品名、商标或第三方权利。
- 每个 Release 必须包含 `SHA256SUMS.txt`，并通过两次构建字节一致性测试。

## 模板契约

模板根类由通用引擎生成：

- 玄刃夜行：`codex-skin-template-nightblade-v1`
- 红莲业火：`codex-skin-template-red-lotus-v1`
- 柳七月 · 不死凰焰：`codex-skin-template-undying-phoenix-v1`

模板装饰节点必须使用通用 ID `codex-skin-manager-chrome`。不得重新引入旧启动器专属的 `codex-meng-chuan-*` 根类或节点 ID。

侧栏皮肤身份区必须位于所有 Codex 原生导航内容之前。当前模板把装饰标题、主题名和原生内容的 Flex 顺序固定为 `-2 / -1 / 0`；不得把主题名作为默认顺序的 `::after` 留在侧栏末尾，因为 Codex 原生账户栏以绝对定位占用底部 46px。新增或修改模板时必须通过三模板侧栏身份布局契约测试，并确认主题身份与账户栏没有交叠。

## 旧启动器迁移边界

旧 `.command` 不能作为皮肤包导入或执行。迁移器只从已知运行时目录读取声明过的 PNG 与许可文本，生成数据包；旧 CSS、JavaScript、启动脚本和其他主动内容一律不进入归档。权利不明的旧素材必须保持 `redistributionAllowed: false`。柳七月公开版改由 `skins/liu-qiyue-undying-phoenix` 源目录生成，作为 `1.0.2` 发布，避免覆盖旧私用 `1.0.1`。

## 验证命令

```bash
cd skin-manager && swift test && swift build -c release
cd .. && npm test
python3 scripts/build_codex_skin_manager_app.py --install
python3 tests/test_codex_skin_manager_bundle.py --installed
python3 tests/test_skin_manager_end_to_end.py
python3 scripts/build_release_assets.py
```

浏览器/CDP 测试默认使用本机 Google Chrome；也可通过 `PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH` 指定 Chromium 可执行文件。
