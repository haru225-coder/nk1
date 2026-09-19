# P6 旗标联动与结局 — 实施追踪

## 步骤
- [x] 旗标门槛 API（require_flag / require_any / hide_if_flag / require_chapter）
- [x] apply_effects 消费 network / merchant_credit / ledger_note 等
- [x] 修 ending 继续按钮盖掉第一章三选一
- [x] chapter2_letter 守回泉州旗标
- [x] 酒馆旧事钩子
- [x] 职事旗标门槛（净海记名沙弥）
- [x] 章三 / 章四短过场
- [x] 第四章四条结局
- [x] 三套 Python 校验 + Godot 无头冒烟

## 验证
```
python3 tools/check_symbols.py && python3 tools/verify_economy.py && python3 tools/simulate_run.py
godot --headless --path . --import
godot --headless --path . -s res://tools/godot_smoke.gd
```
