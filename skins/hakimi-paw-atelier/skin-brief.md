# 哈基米 · 爪印工坊 Skin Brief

## 基本信息

- id：hakimi-paw-atelier
- version：1.0.2
- 人物/IP：原创猫爪工作台主题
- 作者：OPCspace
- 使用范围：可公开非商用分发
- 素材来源：Codex 图像生成 + 本地去绿幕/合成的原创 PNG
- 目标管理器版本：1.1.0

## 视觉方向

- 关键词：高质感猫咪伙伴、工作台、低干扰、青绿、暖金
- 主色：#6ECBB9
- 强调色：#F1BE66
- 字体方向：沿用管理器模板系统字体
- 人物与背景焦点：主体位于右侧，左侧保留操作安全区
- 必须保留的原生功能：任务列表、Composer、代码、Diff、终端和审批

## 模板决策

- template：paw-atelier-v1
- 新增理由：独立模板保留冷暗工作台和右侧透明 hero 结构，同时替换夜刃文案，避免哈基米包应用后混入孟川/玄刃夜行信息

## 资源

- preview：preview.png
- hero：assets/hero.png
- background：assets/background.png
- LICENSES：LICENSES/assets.txt

## 当前进度

- [x] 方案确认
- [x] 素材完成
- [x] skin.json
- [x] 权利声明
- [x] 打包测试
- [x] 管理器导入
- [x] 应用与恢复验证
- [x] 导出回导与 SHA-256 验证

## 已知问题与下一步

- 2026-07-17：旧 `1.0.0` 视觉质量不达标，已按搜索后的推荐方向重制为高质感猫咪陪伴工作台。
- 2026-07-17：继续升级为 `1.0.2`，接入独立 `paw-atelier-v1` 模板，避免同版本内容冲突和旧夜刃文案残留。
- 已生成 `dist/validation-skins/Hakimi-Paw-Atelier-1.0.2.codexskin`，SHA-256 为 `2c6b35f196dd035cbf112f43fe1dc34270b7c2d8f0462f2e75844003084f907b`。
- 已通过真实管理器导入到 `~/Library/Application Support/CodexSkinManager/skins/hakimi-paw-atelier/1.0.2`。
- 已通过 headless CDP fixture 验证应用、校验和恢复流程，运行时模板为 `paw-atelier-v1`。
