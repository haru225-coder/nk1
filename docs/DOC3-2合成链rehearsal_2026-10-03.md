# DOC3-2 合成链 rehearsal 记录（2026-10-03，lane w23-a3）

> 来源：`docs/待策划拍板清单_2026-09-28.md` §八之四 **P3 行**——「DOC3-2 合成链 rehearsal 记录」（机械前置，零代码、零 data 变更；DOC3-1 一拍板即可照此整条跑）。
> 执行环境：worktree `/tmp/nk1-a3`（基 main `c0e27b6`），Godot 4.6.3 `/home/box/.local/bin/godot`，执行模型 kimi-k3 / effort max。

## 一、这条链是什么

清单 §八之二 DOC3-2 行点明的合成链（下拍板时刻要照原样跑的命令串）：

1. `tools/art/fix_bg_customs_jar.py`（含「挪名」一步）——把 bg_customs_room 的青花罐改成龙泉粉青素面；C2 算盘补区要跟这次合成一次做（`docs/资产史实待修_2026-09-27.md` C2 / L3 行，等 DOC3-1 口径）。
2. `godot --headless --import --path .`——刷新导入缓存（.import 侧车与 .godot/imported 产物）。
3. `python3 tools/check_assets.py`——资产引用完整性门禁。
4. `qa_p7` 截图一步肉眼验收——主表写的是「qa_p7 截图」；实际覆盖市舶司页的截图门禁是 `tools/patrol_shell.gd`（PORT_PORTS × FACILITIES 含 yamen，泉州 / 福州 / 兴化三港衙门页各一张），见 §四注。

## 二、rehearsal 实跑（每步 r、c、产物）

| # | 命令 | rc / 输出现值 | 产物与判读 |
|---|---|---|---|
| 1 | `python3 tools/art/fix_bg_customs_jar.py --out /tmp/w23/a3-rehearsal-candidate.jpg` | 脚本报「输入 assets/bg_customs_room.jpg（524686 字节）：罐身 mask 内蓝像素 0.0%（V≥0.10 时 0.0%）→ 蓝像素占比 < 3%，罐身均色 (40,41,34)：判定已处理过（或罐已非青花），跳过，未写文件」；shell rc=0，候选文件未产生 | **幂等自检正常**：B 案（龙泉粉青素面）09-26 本地落地、09-28 进 main，现图已是处理后态。拍板后这一刀真正要合成的是 **C2 算盘补区**——该刀要等 DOC3-1 口径定夺（补算盘还是留素面），本 rehearsal 无法代跑；届时若仍用本题脚本，须先按工单把脚本挪名（`tools/art/fix_customs_jar.py`）并扩展补区逻辑 |
| 2 | `HOME=/tmp/w23/a3-fakehome godot --headless --import --path .`（临时 HOME，避免动共享 `.godot` 配置） | rc=0，日志尾「[ DONE ] loading_editor_layout」；`git status --porcelain` 仅出现本片既有的 `tools/godot_story_check.gd` 临时改动（本片 V0928-8 取样用途，落地前恢复） | 导入缓存刷新链路通；无新增侧车脏。09-27 文档记的等价命令是 `godot --headless --editor --path . --quit`，两者都是「编辑器 headless 拉起并退出」，本条现用变体与一键门禁 19 步的第 0 步同形，推荐统一用本形 |
| 3 | `python3 tools/check_assets.py` | rc=0；「资产引用 71 个完整路径 + PORT_BG/FACILITY_BG/ENDING_BG/PROLOGUE_PAGE_BG 表 + _set_background_file 直写 3 处 + 港页变体 0 张 + 前缀拼接展开 + 货图 0 张 + 人物立绘 76 张，全部存在 → 结果：全部通过」 | 资产门禁现态绿；合成换图后须仍为绿（同名覆盖不引新引用，其为绿是结构性的，但 sha1 / 尺寸变化不在这条门里判，过场图走 import_cutscene_bgs 清单一门，见 DOC3-3 预演档） |
| 4 | 截图一步肉眼看 | **本步不代跑、无 rc**：「肉眼看」是人事，且本片不改图，截图与现状图一一相同，无对照价值 | 拍板合成后照 §四 现行口径跑 `patrol_shell`（19 步内）三港衙门页 + 走一遍 `ending_gangshou` 过场（底图会被 `_grade_backdrop` 调色、活背景推拉放大——2× 下干净的补区在上屏色程里仍可能露馅，这是 09-27 文档点名要人眼的原由） |

## 三、整条链的卡点结论

- **链路本身全通**：script / import / gate 三段今天全部实跑绿；唯一跑不动的是「合成内容」——C2 算盘补区的画法定稿等 DOC3-1。
- 第 1 步的幂等跳过是**特性不是故障**：脚本以「蓝像素占比 < 3%」自判已处理，拍板后跑 C2 补区时若罐区已无青花，本脚本只会处理补区（或需按工单口径另写补区段），不会把粉青罐重画一遍。
- 两个脚本共一底图的并发约束仍有效：`fix_bg_customs_jar.py` 与 `fix_bg_signs.py` 都是「以 HEAD 为底重画同一张图」，拍板落地时**跑一个就先提交一个**（`docs/资产史实待修_2026-09-27.md` §三末口径），勿同批跑。

## 四、截图一步的口径注（与主表字面的出入）

主表写「qa_p7 截图」是 09-14 老叫法；现 tools/ 下 `qa_p7_screenshots.gd` 截的是行会 / 贡院页（guild / exam），**不覆盖市舶司衙门页**。覆盖衙门页的现成截图链是：

- `tools/patrol_shell.gd`（一键 19 步内的 patrol 那一道）：PORTS = 泉州 / 福州 / 兴化，FACILITIES 含 `yamen`，每港衙门页各截一张（NK1_SHOT_DIR 指到 QA 目录）——所有港的市舶司页背景都是 `bg_customs_room.jpg`（`scripts/Main.gd` 的 `"_yamen"` 映射），三张衙门页即三份对照。
- `ending_gangshou` 第 2 镜（`data/cutscenes.json` 第 457 行同底图）无现成截图探针，验收时须人工过一遍该结局过场（或在 QA 探针 lane 下补一支），本片只登记缺口、不补探针（探针属别的 lane 归属）。

改前改后对照截图的肉看判读归拍板落地那一 lane；本篇留的是「命令链全能跑」的可复现记录。
