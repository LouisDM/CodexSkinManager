# 私用验证皮肤重制记录

## 搜索结论

- 蔡徐坤官方站点当前以 `Tour`、`Music`、`Videos` 和新专辑/视频入口为主，因此私用验证皮肤采用舞台、巡演、音乐制作和人物肖像语义，但不搬运官方照片、Logo、签名、歌词或官方物料。
- Square Enix 官方商品页明确 Tifa Lockhart 属于 `FINAL FANTASY VII REBIRTH`，并突出手套、靴子、可动姿态和角色设计归属；因此私用验证皮肤采用同人角色立绘、酒馆训练、拳套和木质空间语义，但不搬运官方角色图、Logo、截图或精确官方构图。

参考来源：

- https://kunofficial.com.cn/
- https://eu.store.square-enix-games.com/final-fantasy-vii-rebirth-play-arts-shin-action-figure-tifa-lockhart

## 推荐决策

本轮重制两个私用验证包：

- `cai-xukun-stage-check` 从 `1.0.0` 升级到 `1.0.1`，新增 `stage-check-v1` 模板；
- `tifa-seventh-heaven-flow` 从 `1.0.0` 升级到 `1.0.1`，新增 `seventh-heaven-v1` 模板；
- 两套均保持 `redistributionAllowed=false`，只用于本机导入和应用流程验证；
- 两套均使用原创生成人物资产和本地后处理，不引用官方图、官方照片、Logo、歌词、签名或截图。

## 新资产

- `cai-xukun-stage-check/assets/background.png`：深紫黑舞台练习室，左侧保留 UI 安全区；
- `cai-xukun-stage-check/assets/hero.png`：透明背景的舞台人物肖像；
- `tifa-seventh-heaven-flow/assets/background.png`：深红木质酒馆训练场，左侧保留 UI 安全区；
- `tifa-seventh-heaven-flow/assets/hero.png`：透明背景的同人格斗角色立绘。

## 验证

- `dist/validation-skins/Cai-Xukun-Stage-Check-1.0.1.codexskin`
  SHA-256：`83c0d659918c27dfe9ad0442cd8af17b554c8ae0a98ab8f351160a27108ae914`
- `dist/validation-skins/Tifa-Seventh-Heaven-Flow-1.0.1.codexskin`
  SHA-256：`08fb3c39eb76b1188d389522e0b9d3ca588f935043083c0c4e0b9447ac4d2431`
- 两套均已通过真实 Codex 皮肤管理器导入到 `~/Library/Application Support/CodexSkinManager/skins/<id>/1.0.1`；
- 两套均已通过 headless CDP fixture 验证应用、校验和恢复流程。
