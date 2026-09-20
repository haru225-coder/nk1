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

## 验证
```
python3 tools/check_symbols.py && python3 tools/verify_economy.py && python3 tools/simulate_run.py
godot --headless --path . --import
godot --headless --path . -s res://tools/godot_smoke.gd
```
