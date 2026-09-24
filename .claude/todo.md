# nk-1 实施追踪（2026-09-25 云端优先合并后）

历史清单（P6 收官 / 窗口点验回收 / 哗变）已全部落地并进入 main，细节见 git log 与 `docs/云端优先合并台账_2026-09-25.md`。

## 待 Snow 真机点验
- [ ] 海图：航法三策栏、三张航向牌、真实岸线叠层、沿 sealanes 的折线航迹、船况面板里的航段细节（八成 / 保货 / 受潮 / 委办）
- [ ] 船屋坞位工席（换上 / 待售）；兴化住处进玉湖陈宅，别港进「住处」
- [ ] 章一晋升册页正文前的「2 年后」摘要与代价
- [ ] 1276-11 兴化守城页、1279-02 广州崖山卡（headless 已验第四扇门，看手感）
- [ ] 海图帧率：386 环已按视窗缓存，若仍卡再查 `_draw_shoal` / 截图开销

## 待拍板
- [ ] 云端两套 P7 留档里要不要挑：港口节拍（21ce `data/port_beats.json`）、数据驱动结局（b05c `data/endings.json`）
- [ ] 是否 push（目前 main 领先 origin/main 160+ 提交，全部本地）

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
