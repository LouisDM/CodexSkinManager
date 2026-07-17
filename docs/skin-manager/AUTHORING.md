# `.codexskin` 制作规范

新皮肤直接从声明式源目录生成 `.codexskin`。不要先制作 `.command` 再转换，也不要把 CSS、JavaScript、Shell 或其他可执行内容放进皮肤包。

## 流程

```text
选择或开发管理器模板
        ↓
准备 skin.json、图片与许可文本
        ↓
build_codexskin.py 校验并生成确定性包
        ↓
双击 .codexskin 或在管理器中按 ⌘O
        ↓
预览权利信息，应用或恢复
```

管理器拥有 CDP、注入器、恢复逻辑和 CSS 模板。皮肤包只提供经过允许列表约束的数据，因此不需要每套皮肤各自维护端口和运行时。

## 源目录

```text
my-skin/
├── skin.json
├── preview.png
├── assets/
│   ├── background.png
│   ├── hero.png
│   └── avatar.png
└── LICENSES/
    └── assets.txt
```

`avatar.png` 可选。`LICENSES/` 至少需要一个非空 UTF-8 `.txt`。

## `skin.json`

```json
{
  "schemaVersion": 1,
  "id": "sample-night-skin",
  "name": "示例 · 夜行皮肤",
  "version": "1.0.0",
  "template": "nightblade-v1",
  "minManagerVersion": "1.1.0",
  "preview": "preview.png",
  "author": {
    "name": "Skin Author",
    "website": null
  },
  "theme": {
    "tokens": {
      "accent": "#8FD8FF",
      "canvas": "#080D15",
      "panelRadius": "12"
    },
    "assets": {
      "background": "assets/background.png",
      "hero": "assets/hero.png"
    },
    "focalPoints": {
      "background": {
        "x": 0.62,
        "y": 0.5
      },
      "hero": {
        "x": 0.5,
        "y": 0.2
      }
    }
  },
  "rights": {
    "redistributionAllowed": false,
    "commercialUse": false,
    "fanMade": true,
    "unofficial": true,
    "noEndorsement": true,
    "notice": "Private local preview only."
  }
}
```

`preview` 是管理器资料库和详情页直接展示的最终主图，不会自动套用模板或叠加 `theme.assets`。它必须是与实际皮肤一致的 16:10 合成图或真实界面截图；当皮肤使用独立的 `background` 与透明 `hero` 时，不能只把背景图填入 `preview`。

当前模板：

- `nightblade-v1`
- `red-lotus-v1`
- `undying-phoenix-v1`

素材槽：

- `avatar`
- `background`
- `hero`

颜色令牌：

- `accent`
- `accentStrong`
- `canvas`
- `focus`
- `ink`
- `line`
- `mutedInk`
- `surface`
- `surfaceRaised`

数值令牌：

- `controlRadius`
- `motionDuration`
- `panelRadius`

颜色使用 `#RRGGBB` 或 `#RRGGBBAA`。数值使用字符串形式的 `0–1000`。素材焦点的 `x`、`y` 均为 `0–1`。

## 构建

```bash
npm run build:skin -- \
  --source "/绝对路径/my-skin" \
  --output "/绝对路径/sample-night-skin-1.0.0.codexskin"
```

或：

```bash
python3 scripts/build_codexskin.py \
  --source "/绝对路径/my-skin" \
  --output "/绝对路径/sample-night-skin-1.0.0.codexskin"
```

打包器会：

- 严格校验 `skin.json` 字段、模板、令牌、相对路径和权利声明；
- 验证引用的 PNG/JPEG 文件头、大小和符号链接边界；
- 只收集最终预览、主题引用图片与 `LICENSES/**/*.txt`；
- 自动生成 `theme.json`、`rights.json`、`manifest.json`、字节数与 SHA-256；
- 生成固定顺序、固定时间戳、无压缩的确定性 ZIP；
- 忽略源目录中的 `.command`、CSS、JS 和其他未声明内容。

## 导入

双击输出文件，或：

```bash
open -a "$HOME/Applications/Codex 皮肤管理器.app" \
  "/绝对路径/sample-night-skin-1.0.0.codexskin"
```

管理器会再次执行完整包校验和图片安全解码。通用打包器当前生成未签名包，因此信任状态显示为“未签名”；这不等同于允许公开分发，公开导出仍由 `rights.redistributionAllowed` 控制。

## 权利边界

只有在人物、图片、文字和其他素材均明确允许重新分发时，才能把 `redistributionAllowed` 设为 `true`。不能确认时使用：

```json
{
  "redistributionAllowed": false,
  "commercialUse": false,
  "fanMade": true,
  "unofficial": true,
  "noEndorsement": true,
  "notice": "Private local preview only. Redistribution and commercial use are not permitted."
}
```

同时在 `LICENSES/assets.txt` 记录每项素材来源、作者、许可和使用边界。

## Git 提交与发布

如果用户明确要求提交、push、创建 PR 或发布，新皮肤不能只把模板代码或文档上传到 GitHub。除非用户明确缩小范围，默认同时提交：

- `skin.json`、被引用的 `assets/`、`LICENSES/` 和皮肤任务档案；
- 对应皮肤的宽屏与窄屏截图；
- 新增或修改的管理器模板、测试和上下文；
- 获准重新分发的 `.codexskin` 与 SHA-256。仓库不跟踪发行二进制时，把它们上传到对应 GitHub Release，并在 PR 中提供链接。

提交前先检查 `rights.redistributionAllowed` 和许可文本：

- 为 `true` 时，才可以把对应源素材、截图和成品上传到公开 Git/Release；
- 为 `false` 或权利不明时，不得公开上传。只有用户明确确认私有目标和权限时才通过私有仓库/私有渠道交付；
- 私有素材被排除时，PR 和最终交接必须列出未上传文件与原因，不能让其他设备误以为仓库包含完整素材。

建议截图路径：

```text
docs/screenshots/<skin-id>.png
docs/screenshots/<skin-id>-narrow.png
```

提交前检查：

```bash
git status --short
git diff --cached --name-status
```

只精确暂存当前皮肤相关文件，避免带入其他工作区改动。完成后报告分支、commit、PR/Release 链接、实际上传清单和任何权利排除项。

## 新增模板

只有现有模板无法表达新布局时才新增模板。至少同步更新：

- `skin-manager/Sources/SkinCore/SkinPackageModels.swift`
- `skin-manager/Sources/CodexSkinManager/Resources/Engine/injector.mjs`
- `skin-manager/Sources/CodexSkinManager/Resources/Templates/<template>.css`
- `scripts/build_codexskin.py`
- 资源、引擎、应用包和模板契约测试

模板 CSS 由管理器持有，不能进入 `.codexskin`。Swift、Node 和打包器的模板允许列表必须一致。

模板还必须保留 Codex 原生交互安全区：侧栏主题身份只能放在原生导航内容之前，不能占用左下角账户栏；现有模板使用装饰标题 `order: -2`、主题名 `order: -1`、原生内容 `order: 0`。修改侧栏装饰后必须运行引擎测试，并在真实 Codex 中检查用户名、任务列表和窄窗口。

## 非 `.codexskin` 皮肤转换

CodexUI 仓库提供 `$convert-to-codexskin` Skill，可只读检查 `.command`、CSS+图片目录、ZIP、旧主题 JSON 和复制出来的运行时。

```text
使用 $convert-to-codexskin，把“/我的皮肤路径”转换为 Codex Skin Manager 可导入的 .codexskin。先只读检查，不执行任何旧脚本；先给我迁移摘要，我确认后再打包和测试。
```

转换时：

- 保留原输入不变；
- 只复制获准使用的 PNG/JPEG 与许可文本；
- 其他图片先生成 PNG/JPEG 衍生文件；
- 把旧 CSS 映射或审核迁移为管理器模板；
- 不复制或执行旧 `.command`、Shell、JavaScript、Python、二进制、端口、PID 或守护进程配置；
- 权利不明时固定使用 `redistributionAllowed: false`。

建立标准源目录后再运行通用打包器。现有模板无法表达布局时，先新增允许列表模板与测试，不能把 CSS/脚本放进包或降低导入器校验。

## 测试

```bash
python3 tests/test_skin_authoring_packager.py
cd skin-manager && swift test --filter SkinAuthoringPackagerCompatibilityTests
cd .. && npm test
```

第一项验证确定性和主动内容隔离；第二项把 Python 生成的真实包交给 Swift 导入器，防止两端合约漂移。
