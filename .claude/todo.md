# P6 收官 — 实施追踪

## 已完成（旗标与结局）
- [x] 旗标门槛 API（require_flag / require_any / hide_if_flag / require_chapter）
- [x] apply_effects 消费 network / merchant_credit / ledger_note 等
- [x] 修 ending 继续按钮盖掉第一章三选一
- [x] chapter2_letter 守回泉州旗标
- [x] 酒馆旧事钩子
- [x] 职事旗标门槛（净海记名沙弥）
- [x] 章三 / 章四短过场
- [x] 第四章四条结局
- [x] 三套 Python 校验 + Godot 无头冒烟

## 收官（2026-09-20）
- [x] 拆除 crate / 海鸟 / 鲸影 / 野海盗刷怪，不恢复自由航行拾取
- [x] simulate_run 从开局真跑到占城「南海一纲」，不垫 F12（28 趟 / 峰值 83090）
- [x] 三套 Python 校验全绿
- [x] 合入候选 PR 标成可合并（不硬合 PR #1）
- [x] 存档 / 升章 / 了结弹窗套绢本主题
- [x] Godot 4.6 无头冒烟重跑（Crate 拆除 + style_dialog；Main 20 帧无脚本错误）
- [x] 剧情字阶 + 选项挑签 hover
- [x] 海图收进绢本字阶；死生态位图拆除；海洋贴图 UID 对齐
- [x] 海图遭遇弹层改 CenterContainer 居中（原 360,200 钉右下裁第三钮）

## 后续（2026-09-20）
- [x] 名声换爵：titles.json 五档职衔，折抽解、加赊贷，不另开章门
- [x] 港口修埠：市舶司投钱，产地/消费地同向调价 + 加深市场
- [x] add_fame 统一入口（呈报 / 海战 / 剧情 / 修埠）
- [x] 三套 Python 校验 + Godot 冒烟接职衔/修埠

## 窗口点验回收（2026-09-21）
- [x] load_texture 先按文件头解码，避开 icon_*.import valid=false 的 ERROR
- [x] 旅店按港改写成 {港}_inn（原先 city_inn 被收成 _setup_inn("city")）
- [x] 游戏港行会/贡院/住宅不再送回兴化序章
- [x] 港卡「衙门/市场」改成「市舶司/牙行」，与内页一致
- [x] 行会钉出港行情抄本（信用≥8 抄 5 条，不耗日）
- [x] 贡院誊录三日换工钱与学者倾向，不给名声
- [x] 住宅看边记、5 钱/日歇息（候风仍去旅店）
- [x] load_scene 跳过 city_ 前缀，避免盖掉兴化序章调查页
- [x] 窗口点验：F11 泉州行会行情 / 贡院誊录 / 住宅歇 1 日
- [x] 通用港 GENERIC_FACILITIES 补行会/贡院/住宅（博多不再只剩五卡）
- [x] 兴化回访（已到泉州）走动态页，序章调查页只留给未到泉州时
- [x] 窗口点验：福州通用八卡 + 兴化回访行会（不是应对烂账）

## 验证
```
python3 tools/check_symbols.py && python3 tools/verify_economy.py && python3 tools/simulate_run.py
godot --headless --path . --import
godot --headless --path . -s res://tools/godot_smoke.gd
```
