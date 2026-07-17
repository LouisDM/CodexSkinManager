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
  "preview": "assets/background.png",
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
- 只收集引用图片与 `LICENSES/**/*.txt`；
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

## 新增模板

只有现有模板无法表达新布局时才新增模板。至少同步更新：

- `skin-manager/Sources/SkinCore/SkinPackageModels.swift`
- `skin-manager/Sources/CodexSkinManager/Resources/Engine/injector.mjs`
- `skin-manager/Sources/CodexSkinManager/Resources/Templates/<template>.css`
- `scripts/build_codexskin.py`
- 资源、引擎、应用包和模板契约测试

模板 CSS 由管理器持有，不能进入 `.codexskin`。Swift、Node 和打包器的模板允许列表必须一致。

## 旧 `.command` 迁移

`.command` 不能直接导入。迁移时只提取图片与许可数据，把旧 CSS 映射或审核迁移到管理器模板，再建立标准源目录并运行通用打包器。旧端口、守护进程、JS、CSS、PID 和日志配置都不进入新包。

## 测试

```bash
python3 tests/test_skin_authoring_packager.py
cd skin-manager && swift test --filter SkinAuthoringPackagerCompatibilityTests
cd .. && npm test
```

第一项验证确定性和主动内容隔离；第二项把 Python 生成的真实包交给 Swift 导入器，防止两端合约漂移。
