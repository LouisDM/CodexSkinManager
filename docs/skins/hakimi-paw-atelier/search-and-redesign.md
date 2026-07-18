# 哈基米 · 爪印工坊重制记录

## 为什么上一版失败

上一版为了批量验证 `.codexskin` 导入流程，优先满足了包结构、权限字段和自动化测试，视觉只用了本地几何图形。它和孟川、柳七月成品的差距主要在：

- 缺少真实空间和光影纵深；
- 角色像贴纸，占位感强；
- `preview.png` 不像真实皮肤截图；
- 主题符号只有猫爪图案，没有“陪伴工作台”的完整气质；
- 三套同时做导致每套都没有独立审美判断。

## 搜索结论

- “哈基米”原是日语“蜂蜜”的空耳，后来在中文互联网中被用于称呼猫或其他可爱事物；因此用猫咪作为主题主体是合理的。
- 公开资料也显示该词和部分负面/黑色梗发生过缠绕，因此本皮肤明确只采用温暖、陪伴、可爱物的语义，不使用虐猫、猎奇、恶搞或攻击性元素。
- 相比蔡徐坤和蒂法，哈基米不需要真人肖像或官方 IP 素材，最适合作为可公开非商用的验证皮肤。

参考来源：

- https://zh.wikipedia.org/zh-hans/%E5%93%88%E5%9F%BA%E7%B1%B3_%28%E7%BD%91%E7%BB%9C%E7%94%A8%E8%AF%AD%29
- https://www.bilibili.com/opus/1062047139181363216
- https://www.huxiu.com/article/4007694.html
- https://www.sohu.com/a/716406454_121124334

## 推荐决策

本轮先重制并交付 `hakimi-paw-atelier`：

- 版本从 `1.0.0` 升级到 `1.0.2`，避免已导入的旧包同版本内容冲突；
- 新增 `paw-atelier-v1` 模板，保留深色工作台和右侧透明 hero 结构，同时替换夜刃文案；
- 视觉方向改为“高质感猫咪陪伴工作台”，而不是“简单猫爪几何插画”；
- 权利保持可公开非商用分发，素材为原创生成和本地后处理。

## 新资产

- `assets/background.png`：深青色猫咪工作台环境，保留左侧 UI 可读区域；
- `assets/hero.png`：透明背景的高质感猫咪伙伴；
- `preview.png`：按管理器截图构图重新合成，显示侧栏、主面板、能力卡和 composer 的真实皮肤预览感。

## 验证

- 打包输出：`dist/validation-skins/Hakimi-Paw-Atelier-1.0.2.codexskin`
- SHA-256：`2c6b35f196dd035cbf112f43fe1dc34270b7c2d8f0462f2e75844003084f907b`
- 包内只包含 `manifest.json`、`theme.json`、`rights.json`、`LICENSES/assets.txt`、PNG 资产；
- 已通过真实 Codex 皮肤管理器导入到 `~/Library/Application Support/CodexSkinManager/skins/hakimi-paw-atelier/1.0.2`；
- 已通过 headless CDP fixture 验证应用、校验和恢复流程，运行时 `skinId=hakimi-paw-atelier`，模板标记为 `paw-atelier-v1`。

## 后续

蔡徐坤与蒂法不应继续用粗糙抽象图批量生成。若继续制作：

- 蔡徐坤：只做公开非商用 fan-made，参考官方站点的 Tour / Music / Videos 信息架构，不使用官方照片、姓名背书、签名或歌词。
- 蒂法：只做公开非商用 fan-made，参考 Seventh Heaven、拳套、格斗训练语义，不使用官方角色图、Logo 或截图。
