# 蒂法 · 第七天堂练习场 Skin Brief

## 基本信息

- id：tifa-seventh-heaven-flow
- version：1.0.1
- 人物/IP：蒂法武术酒馆人物公开非商用 fan-made 概念
- 作者：OPCspace
- 使用范围：公开非商用预览和流程验证
- 素材来源：Codex 图像生成 + 本地去绿幕/合成的原创 PNG
- 目标管理器版本：1.1.0

## 视觉方向

- 关键词：高质感武术酒馆、练习场、拳套、酒馆木色、深红、青蓝强调
- 主色：#AC2E3A
- 强调色：#57AEB8
- 字体方向：沿用管理器模板系统字体
- 人物与背景焦点：同人角色主体在右侧，不使用官方角色图、Logo 或截图
- 必须保留的原生功能：任务列表、Composer、代码、Diff、终端和审批

## 模板决策

- template：seventh-heaven-v1
- 新增理由：独立模板保留厚重暗红和右侧 hero 结构，同时替换红莲业火文案，避免验证包应用后混入孟川/红莲信息

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
- [x] 公开非商用权利声明

## 已知问题与下一步

- 2026-07-17：旧 `1.0.0` 视觉质量不达标，已按搜索后的推荐方向重制为高质感武术酒馆人物皮肤。
- 2026-07-17：继续升级为 `1.0.1`，接入独立 `seventh-heaven-v1` 模板，避免同版本内容冲突和旧红莲业火文案残留。
- `dist/v1.1.1/Tifa-Seventh-Heaven-Flow-1.0.1.codexskin` 的 SHA-256 为 `dfdad3d11227342cb420b24463805847885e73b9032b15281e88533f9099af42`。
- 已通过真实管理器导入到 `~/Library/Application Support/CodexSkinManager/skins/tifa-seventh-heaven-flow/1.0.1`。
- 已通过 headless CDP fixture 验证应用、校验和恢复流程，运行时模板为 `seventh-heaven-v1`。
- 作为公开非商用验证皮肤上传 Release；包内声明非官方、无背书、不含官方角色图、Logo 或截图。
