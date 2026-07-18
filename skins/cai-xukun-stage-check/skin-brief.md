# 蔡徐坤 · 舞台练习室 Skin Brief

## 基本信息

- id：cai-xukun-stage-check
- version：1.0.1
- 人物/IP：蔡徐坤舞台人物私用 fan-made 概念
- 作者：OPCspace
- 使用范围：仅本地预览和流程验证
- 素材来源：Codex 图像生成 + 本地去绿幕/合成的原创 PNG
- 目标管理器版本：1.1.0

## 视觉方向

- 关键词：高质感舞台练习室、巡演设备、麦克风架、紫黑、金色追光
- 主色：#D250A0
- 强调色：#ECC35C
- 字体方向：沿用管理器模板系统字体
- 人物与背景焦点：舞台人物主体在右侧，不使用官方照片、Logo、歌词或签名
- 必须保留的原生功能：任务列表、Composer、代码、Diff、终端和审批

## 模板决策

- template：stage-check-v1
- 新增理由：独立模板保留高能 hero 与舞台光效层级，同时替换不死凰焰文案，避免私用验证包应用后混入柳七月/凰焰信息

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
- [x] 仅限本机导出锁定验证

## 已知问题与下一步

- 2026-07-17：旧 `1.0.0` 视觉质量不达标，已按搜索后的推荐方向重制为高质感舞台人物皮肤。
- 2026-07-17：继续升级为 `1.0.1`，接入独立 `stage-check-v1` 模板，避免同版本内容冲突和旧不死凰焰文案残留。
- 已生成 `dist/validation-skins/Cai-Xukun-Stage-Check-1.0.1.codexskin`，SHA-256 为 `83c0d659918c27dfe9ad0442cd8af17b554c8ae0a98ab8f351160a27108ae914`。
- 已通过真实管理器导入到 `~/Library/Application Support/CodexSkinManager/skins/cai-xukun-stage-check/1.0.1`。
- 已通过 headless CDP fixture 验证应用、校验和恢复流程，运行时模板为 `stage-check-v1`。
- 因涉及真实公众人物名称，保持私用不可分发，不上传公开 Release。
