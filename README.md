# Codex Skin Manager

一款原生 macOS Codex 皮肤管理器，支持安全导入、预览、切换、重新应用、恢复和受权导出 `.codexskin` 包。

当前公开提供两套非商用同人皮肤：

- 孟川 · 红莲业火
- 孟川 · 玄刃夜行

源码版 `1.1.0` 还支持“柳七月 · 不死凰焰”的本机私有迁移；该素材授权不允许公开再分发，因此不会放入仓库、内置皮肤或 GitHub Release。

> 本项目为非官方本地工具，与 OpenAI 或《沧元图》官方无隶属或背书关系。内置素材只允许按各自 `LICENSES/assets.txt` 随皮肤包进行非商用公开分发；这不授予任何角色、作品名、商标或其他第三方权利。

![Codex 皮肤管理器](docs/screenshots/codex-skin-manager.png)

## 主要能力

- 原生 SwiftUI 三栏皮肤资料库。
- `.codexskin` 数据包导入、完整性校验与安全安装。
- 仅允许管理器签名内置的 CSS 模板；包内脚本、CSS、二进制、远程 URL、符号链接和路径穿越会被拒绝。
- 只连接 `127.0.0.1:9340`，并检查监听端口属于官方 Codex 进程。
- 不修改或重签名 `/Applications/ChatGPT.app`，也不会强制结束 Codex。
- 区分“上次使用记录”和本次已经运行时校验的“已验证生效”。
- 同一皮肤可重新应用；失败时可直接重试或打开注入日志。
- 恢复默认后无需重启 Codex，即可再次应用任一皮肤。

## 环境要求

直接使用 Release：

- macOS 13 或更高版本
- 官方 Codex 桌面应用安装在 `/Applications/ChatGPT.app`

从源码构建或运行自动化测试：

- macOS 13 或更高版本
- Swift 6 工具链
- Node.js 与 npm
- Google Chrome，或通过 `PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH` 指定 Chromium（仅浏览器自动化测试需要）

## 直接下载

前往 [GitHub Releases](https://github.com/LouisDM/CodexSkinManager/releases) 下载：

- `Codex-Skin-Manager-v1.0.1-macOS.zip`：管理器应用，已内置两套皮肤。
- `Meng-Chuan-Nightblade-1.0.1.codexskin`：孟川 · 玄刃夜行。
- `Meng-Chuan-Red-Lotus-1.0.1.codexskin`：孟川 · 红莲业火。
- `SHA256SUMS.txt`：下载文件完整性校验。

解压管理器并移动到 `~/Applications`。应用目前使用 ad-hoc 本地签名而非 Apple Developer ID 公证；首次打开如被 macOS 阻止，请在 Finder 中右键应用并选择“打开”。安装管理器后，双击下载的 `.codexskin` 即可导入，也可以直接使用应用内置版本。

## 旧启动器皮肤迁移（本机私有）

`.command` 是启动脚本，不能直接导入管理器。若本机已有“柳七月 · 不死凰焰”旧启动器资源，可先构建安全的数据包：

```bash
python3 scripts/build_private_liu_qiyue_skin.py \
  --runtime "$HOME/Library/Application Support/CodexLiuQiyueUndyingPhoenixSkin/runtime" \
  --output "$HOME/Applications/Liu-Qiyue-Undying-Phoenix-1.0.0.codexskin"
```

然后双击输出文件，或在管理器中按 `⌘O` 导入。转换器只打包两张 PNG、`theme.json`、`rights.json` 和许可文本，不会打包或执行旧启动器中的脚本和 CSS。输出包是本机私用版本，管理器会禁用公开导出。

## 构建与安装

```bash
git clone https://github.com/LouisDM/CodexSkinManager.git
cd CodexSkinManager
npm install
python3 scripts/build_codex_skin_manager_app.py --install
```

应用会被原子安装到：

```text
~/Applications/Codex 皮肤管理器.app
```

首次切换时，如果 Codex 正以普通模式运行，管理器会等待你在 Codex 中按 `⌘Q`，然后以仅绑定本机回环地址的调试会话重新启动官方应用。

快捷键：

- `⌘O`：导入皮肤
- `⌘↩`：切换、重新应用或重试
- `⇧⌘R`：恢复默认

## 自动化测试

```bash
npm test
npm run test:bundle
npm run test:e2e
npm run build:release
```

完整测试覆盖 Swift 核心、皮肤包安全策略、真实 Chrome CDP 注入、模板切换、恢复后重新应用、应用包签名和隔离启动。`test:e2e` 使用已经安装的应用，但使用临时资料库，不会修改真实皮肤状态。

## 项目结构

- `skin-manager/`：Swift Package、SwiftUI 应用、核心库与单元测试。
- `scripts/`：应用构建、签名和原子安装脚本。
- `scripts/build_release_assets.py`：使用核心导出器生成版本化 Release 资产和 SHA-256 清单。
- `tests/`：资源、浏览器/CDP、应用包和隔离启动验收。
- `docs/skin-manager/PRODUCT_PRINCIPLES.md`：产品判断与体验原则。
- `docs/skin-manager/ARCHITECTURE.md`：安全边界、切换流程和模板契约。
- `.ai-context/当前进度.md`：跨设备 AI 接手时应首先读取的当前状态。
- `AGENTS.md`：Codex、Cursor 等 AI 工具的通用上下文入口。

## 状态与日志

运行数据位于：

```text
~/Library/Application Support/CodexSkinManager/
```

- `active.json`：最近一次成功应用的持久记录，不代表当前页面一定仍然加载皮肤。
- `runtime/injector.log`：页面注入与守护进程日志。
- UI 显示“皮肤已验证生效”时，代表本次管理器进程已经完成注入与运行时模板校验。

## 设计与维护

产品方向不是复制某个“世界最好产品”的外观，而是采用 Apple 的可预测与可逆、Raycast 的低摩擦任务路径，以及 VS Code 的预览后确认思维。详见 [产品原则](docs/skin-manager/PRODUCT_PRINCIPLES.md)。

代码采用 MIT License。内置皮肤素材不属于 MIT 代码许可；它们只允许在保留各自 `LICENSES/assets.txt` 的前提下，随本皮肤包进行非商用公开分发。相关角色、作品名、商标和其他第三方权利仍归各自权利人所有。
