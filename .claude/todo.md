# nk-1 实施追踪（2026-09-25 云端优先合并后）

历史清单（P6 收官 / 窗口点验回收 / 哗变）已全部落地并进入 main，细节见 git log 与 `docs/云端优先合并台账_2026-09-25.md`。

## 点验（哈德 09-25 晚截图点验，探针 `~/tmp/nk1-align/probe_shots*.gd`）
- [x] 海图：航法三策栏、三张航向牌、真实岸线、沿 sealanes 的折线航迹、船况面板航段细节——通过；海图重制后 -30 又按走查反馈修了提示位置、港名字号、图带取景、岸线切角
- [x] 船屋坞位工席；兴化住处进玉湖陈宅——通过
- [x] 章一晋升册页「2 年后」摘要与代价，日期真跳、新闻随即投放——通过
- [x] 1276-11 兴化守城页、1279-02 广州崖山卡——守城页与终局页原把卡塞进云端已隐藏的左右栏、1279 年号「未纪零年」，已修在 `fix/siege-shore-band`（feb0499 + d4e90bc），等换皮收尾后合入
- [x] 海图帧率——重制后不再逐帧重画岸线，巡检 76 项 5 秒
- [ ] Snow 上手：缩放拖拽手感、换皮后的整体观感（截图代替不了）

## 排队（换皮收尾后）
- [ ] merge `fix/siege-shore-band`（-54 负责，岸带布局按哈德、样式按 -54）
- [ ] 接 b05c 两项：行会入行、贡院赴试（见 `docs/P7留档评估_2026-09-25.md`），其余 P7 留档不动
- [ ] push main（Snow 已授权「全部 ready 后」；先 `gh auth login`，本机现无 GitHub 写凭据）

## 验证
```
python3 tools/check_symbols.py && python3 tools/verify_economy.py && python3 tools/simulate_run.py \
 && python3 tools/verify_coastline.py && python3 tools/check_assets.py \
 && python3 tools/verify_story_data.py && python3 tools/simulate_endgame.py
godot --headless --editor --path . --quit
godot --headless --path . -s res://tools/godot_smoke.gd
godot --headless --path . -s res://tools/godot_compile_check.gd
godot --headless --path . -s res://tools/godot_story_check.gd
godot --path . -s res://tools/patrol_shell.gd
```
