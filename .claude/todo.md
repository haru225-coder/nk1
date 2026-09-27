# nk-1 实施追踪（2026-09-25 云端优先合并后）

历史清单（P6 收官 / 窗口点验回收 / 哗变）已全部落地并进入 main，细节见 git log 与 `docs/云端优先合并台账_2026-09-25.md`。

## 点验（哈德 09-25 晚截图点验，探针 `~/tmp/nk1-align/probe_shots*.gd`）
- [x] 海图：航法三策栏、三张航向牌、真实岸线、沿 sealanes 的折线航迹、船况面板航段细节——通过；海图重制后 -30 又按走查反馈修了提示位置、港名字号、图带取景、岸线切角
- [x] 船屋坞位工席；兴化住处进玉湖陈宅——通过
- [x] 章一晋升册页「2 年后」摘要与代价，日期真跳、新闻随即投放——通过
- [x] 1276-11 兴化守城页、1279-02 广州崖山卡——守城页与终局页原把卡塞进云端已隐藏的左右栏、1279 年号「未纪零年」，已修在 `fix/siege-shore-band`（feb0499 + d4e90bc），等换皮收尾后合入
- [x] 海图帧率——重制后不再逐帧重画岸线，巡检 76 项 5 秒
- [ ] Snow 上手：缩放拖拽手感、换皮后的整体观感（截图代替不了）

## 点验（哈德 09-26 早，main 3449e08 换皮收尾后第二轮，巡检 ✓108 + 探针 12 张）
- [x] 开局标题、泉州 / 福州 / 兴化港页三扇岸门、船屋坞位、玉湖陈宅、章一跳年册页、1276-11 守城页五扇、1279-02 广州崖山卡、终局港口页札记与「重读结局」、1280 年号「至元十七年」、海图三牌 / 水粮告警朱字 / 船况面板——全部通过
- [x] 巡检截图被海图盖住：patrol_shell 量完海图不拆节点，守城页 / 终局港口页两张截图全是海图，水粮也没归位——已修 f4ae680（断言不受影响，只影响截图证据）
- [x] 底图伪 UI：`assets/bg_fuzhou_yamen.jpg` 左上角画着一块「进士题名 历年名录」的伪界面牌（AI 出图带的，PIL 裁图实证）——09-26 由 -54 抹掉（b19157a，`tools/art/erase_bg_fuzhou_sign.py` 以原画像素做「树冠挡屋角」，描边像素 2792 → 0）；放大看补区上沿有极淡直线，要彻底干净须 Snow 用 Grok 重出
- [x] 船况面板末行「针路 静风 7 日 遇事约 7 日 八成 8 日 水粮足 20 日」在 1280 宽下折行，「日」字孤悬——09-26 由 -30 拆成两行（926d618）

## 排队（换皮收尾后）
- [x] merge `fix/siege-shore-band`（2026-09-26 由 -54 收尾合入：守城页 / 终局港口页取视觉线第二轮重写的 `_build_shore` 页型重排（功能覆盖 feb0499，另修残留、翻倍、匾名累加），年号表取 main，跳年摘要取中文数字版；02 的三条守城岸带探针保留并通过）
- [x] 接 b05c 两项：行会入行、贡院赴试（见 `docs/P7留档评估_2026-09-25.md`），其余 P7 留档不动——09-26 接入：泉州 / 博多 / 广州行会加「入行」工席（2000 / 商誉 8 → 商誉 +4、人脉 +2、`guild_<港>`），贡院加「赴试」工席（每章一次 `exam_sat_ch<章>`、15 日、倾向结算记 `exam_sat`），1268 殿试打平先读 `exam_sat`；check_symbols 补契约。本机无 Godot，未跑 smoke / compile，待真机点验
- [x] 工席成功态 JRPG 过渡（09-26）：`scripts/ui/UiTransition.gd` + `Main.play_transition(title, subtitle, at_black, seal)`——淡入焦墨 → 旧绢题签自左擦出（马善政题名 + 小朱印）、副题浮起 → 停 1 秒（点一下或按键提前收）→ 淡出，约 2.4 秒；全黑时 `load_scene` 换页。接在行会入行成功（「行会・入行」）与贡院赴试成功（「贡院・赴试」+ 日期）。headless / -s 工具脚本 / 巡检下不演、当帧换页。**手动触发**：泉州行会凑够 2000 钱、商誉 8 点「交会费入行」；或泉州 / 兴化贡院本章未赴时点「入场赴试」。中帧 `/workspace/nk1-qa-shots/polish/transition_*.png`；待 Snow 真机看节奏
- [ ] push main（Snow 已授权「全部 ready 后」；先 `gh auth login`，本机现无 GitHub 写凭据）

## 视觉资产线（2026-09-26 合入 main，待 Snow）
- [ ] 真机点验：开场过场的 Esc / 点击手感、标题书法写出、章节卡节奏、抵港横幅、活背景幅度、人物志滚轮与悬停、酒馆整卡点按、「续卷」流程、Retina 下字与剪影卡清晰度
- [ ] 序章与四方沙盘文案重写（`data/scenes.json` 31 幕：去现代腔、引号统一为「」、场景与分支不变）——审稿，不满意可整份退回
- [ ] VisionStage（`scenes/vision/VisionStage.tscn`）待补：舷侧炮焰/水花手绘序列帧；大裱框泥金角花；海战定格底可用宋绢海图残片替换程序椭圆
- [ ] 54 张剪影占位卡待出油画：提示词 `docs/立绘生成提示词_2026-09-25.md`，出图台 `~/tmp/nk1-art-work/artifact/立绘出图台.html`；优先黄氏、陈瓒、断臂老兵、王直库、蒲阿烈、林阿五
- [ ] 标题底图选稿：A 保持现图（有西式罗盘与海怪）/ B 换程序绘制的宋绢本候选 `~/tmp/nk1-art-work/title_bg/cand2_a_qinglv.jpg`（史实对、画意弱）/ C 用 Grok 另出
- [x] 史实：「岸上的根」结算年号改为景炎二年三月，已与 1277 涵江海口卡、`ending_root` 过场对齐（check_symbols 回归）
- [ ] 史实待修：`bg_customs_room.jpg` 青花大罐（C1）+ 案上算盘（C2）——逐条证据、分野、处置、重出提示词见 `docs/资产史实待修_2026-09-27.md` §八（8.2 C1 / C2 行、8.3 P1）；这张归「自动修」（§三 B 龙泉重釉样稿已出），不在 `docs/资产重出工单.md` 三行里，工单收的是同批必须重出的 zhangzhou / ledger / fanfang。待 Snow：A / B 选法（原文 §七 待议 1）、算盘口径（§九 决策包，C2 随之定）
- [ ] 伙伴系统设计稿拍板：`~/tmp/nk1-art-work/companions/伙伴系统设计_草案.md`（40 人，6 个待定问题）

## 验证
```
godot --headless --import --path .   # 导入步骤：刷新缓存、不判红绿，先跑（docs/GATES.md §三.9）
python3 tools/check_symbols.py && python3 tools/verify_economy.py && python3 tools/simulate_run.py \
 && python3 tools/verify_coastline.py && python3 tools/check_assets.py \
 && python3 tools/verify_story_data.py && python3 tools/simulate_endgame.py
godot --headless --path . -s res://tools/godot_smoke.gd
godot --headless --path . -s res://tools/godot_compile_check.gd
godot --headless --path . -s res://tools/godot_story_check.gd
godot --headless --path . -s res://tools/p7_guild_exam_smoke.gd
DISPLAY=:2 godot --path . -s res://tools/patrol_shell.gd
```
