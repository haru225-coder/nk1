# 东亚海域立志传（nk1）

> 南宋末年泉州海商题材的航海经营游戏。海图点选、按日推进、遭遇弹窗——以光荣《大航海时代 II》的经济与航海内核为骨架，套用《大航海时代 IV》的剧情舰队结构。

## 这是什么

你扮演南宋末年的泉州海商，驾驶舰队往返东亚海域（泉州、博多、耽罗、占城、广州……）低买高卖、走私违禁品、迎战海盗、招募职事、改装船只，在朝代更迭的乱世里经营一支海商舰队。

核心循环是**套利贸易**：货物在产地与消费地之间有真实的异地差价，去程南下、回程北上各有不同的盈利路线。发舶前要选航法——针路平稳，外洋赶期限但风涛和海盗更密，傍岸慢、好找岸影，也更容易擦到浅滩；海图上没有连线的生路会迷航。牙行可以接下有期限的委办，酬金略高于直接卖掉，而且交货不砸盘，误期则赔钱、掉名声。海上遇到商船可以变现或记下行情。季风决定航期（去日本要等夏季西南风、回泉州要赶冬季东北风），补给和船员是远洋的硬约束，砸盘、查扣、风暴、海战都是真实的经营风险。

**剧情为骨、沙盒为肉**：104 个历史考据扎实的剧情场景作章节闸门，解锁港口与船种；章节之间是完全自由的沙盒贸易。

## 引擎

- **Godot 4.6**（GDScript）
- 主场景：`res://scenes/Main.tscn`
- 无第三方依赖，开箱即用

## 运行

用 Godot 4.6 打开本目录，直接运行主场景即可。

```bash
godot --path .        # 或直接用 Godot 编辑器打开 project.godot
```

## 验证

一次改动闭环 = 下面十七道门禁全绿（逐道判什么、红了长什么样、`--json` 机读见 `docs/GATES.md`）。云端 cursor/* 线与本地 main 线在 2026-09-25 合并（见 `docs/云端优先合并台账_2026-09-25.md`），两边的门禁都保留。

```bash
# 十一道 Python（无 Godot 也能跑）
python3 tools/check_symbols.py      # autoload 顺序与跨文件符号、海战精灵 PNG 取证、绢本文案规范、各功能契约
python3 tools/verify_economy.py     # 数据完整性 / 套利 / 砸盘 / 季风 / 航法与委办 / 哗变 / 风涛分摊 / 结局旗标
python3 tools/simulate_run.py       # 端到端跑一局，找死锁与账目溢出
python3 tools/verify_coastline.py   # 真实岸线 / 绕岸航线 / 海名标注数据与代码接线
python3 tools/check_assets.py       # 代码引用的 res://assets 都在
python3 tools/verify_story_data.py  # 剧情效果键白名单、存档字段对称
python3 tools/simulate_endgame.py   # 跳年 / 终局窗口 / 守城数值
python3 tools/check_mac_paths.py    # 已跟踪文件里没有 Mac / Homebrew 专属绝对路径（lane gd21 升进必跑；一键跑里排倒数第四）
python3 tools/check_host_paths.py   # 已跟踪文件里没有本机 Linux 绝对路径：家目录、/workspace 下的仓库根（lane cs21 升进必跑；一键跑里排倒数第三）
python3 tools/check_decision_refs.py  # 拍板清单里的「文件:行」还指着原来那段（lane auditfix1 入册即必跑；一键跑倒数第二；红了 --fix）
python3 tools/art/import_cutscene_bgs.py --data-only  # 过场时长 / 镜数 / 字幕时点 / 产物清单契约（lane w25-j5 依拍板 E-16 升进必跑；一键跑末条；不需 Pillow）

# 六道 Godot 4.6（先扫一遍编辑器让 class_name 注册；.import 标 valid=false 时先删 .godot 重扫）
godot --headless --import --path .                               # 导入步骤：刷新缓存、不判红绿（docs/GATES.md §三.9）
godot --headless --path . -s res://tools/godot_smoke.gd          # 云端冒烟（逐项 ✓，末行 GODOT SMOKE PASS）
godot --headless --path . -s res://tools/godot_compile_check.gd  # 全部脚本可编译
godot --headless --path . -s res://tools/godot_story_check.gd    # 剧情脊柱与存档 round-trip（用完会清第 9 槽）
godot --headless --path . -s res://tools/p7_guild_exam_smoke.gd  # 行会入行 / 贡院赴试 / 誊录：扣费门槛、每章一次、跨月结算时序
DISPLAY=:2 godot --path . -s res://tools/patrol_shell.gd         # 有窗口：三港九页 + 海图三向牌都在 1280×720 内
```

`tools/patrol.py` 是云端留下的一键巡检（静态三套 + 冒烟 + 巡检）；`tools/legacy/verify_narrative.py` 与 `tools/legacy/p7_smoke.gd` 绑定云端 21ce 的 P7 平行实现，本分支未收该实现，两个脚本仅留档、不算门禁（别与上面的 `p7_guild_exam_smoke.gd` 混淆）。

海图（2026-09-25 重制，见 `docs/海图重制设计_2026-09-25.md`）：图面在 `scripts/chart/MapView.gd`，投影 `scripts/chart/ChartProjection.gd`（等距圆锥，参数 `data/chart_projection.json`），底图 `assets/map/terrain_4096.png` + `mapdata_2048.png` 由 `tools/build_terrain.py` 离线生成（ETOPO 2022 高程 + Natural Earth 1:10m 岸线；需 numpy / scipy / shapely / pyshp / tifffile / pillow）。改投影参数必须同时改 json 并重出底图。

数值平衡很脆，参数依据见 `docs/复刻设计_大航海时代标准.md`。

> 注意：`.godot/` 导入缓存与生成它的 Godot 版本绑定。换二进制或从快照恢复后若场景渲染成黑屏，先 `rm -rf .godot && godot --headless --path . --import` 重建再排查。

## 海战操作与调试键

海战（战术层实时操船）：**W/S** 帆档、**A/D** 操舵、**J/K** 左右舷炮、**G** 接舷、**B/Esc** 弃战逃走。开局小艍对海盗停着打必沉（第二轮齐射），这是门禁锁死的数值设计（`verify_economy.py` 海战数值边界 + `check_symbols.py` 齐射封顶断言），不是 bug。

debug 构建下：**F11** 跳泉州港，再按跳福州（通用九卡），再按跳兴化回访；**F10** 海图强刷海盗遭遇；**F12** 预览第四章了结弹窗——云电脑/无头环境点验用，正式构建不响应。

## 海战船图管线

海战船身是一条三维泉州湾南宋海船，不是一张贴图在转。船壳在 `assets/ships/song_quanzhou.glb`（尖底、低干舷、一层露天甲板、艏艉起翘、两桅竹席硬篷）。`Ship` / `PirateShip` 上的 `HullRig` 用固定斜俯相机把这条网格渲进视口，船体绕 Y 跟航向走，至少十六个朝向各是不同的一面。敌我同一船壳，只换帆色（牙白 / 绛红）。

```bash
python3 tools/build_song_ship_mesh.py   # 需 Python 标准库；重生 glb
```

`assets/ship_fu.png` / `ship_falcon.png` 是这条网格的一张朝向，留给船图契约和缺网格时的回落，游戏里不拿它自旋。旧的正俯视抠图 `tools/cut_ship_sprites.py` 只在 `--legacy` 下运行（铁子 `shot_iron.png` 仍由它出）。改完必须重跑 `check_symbols.py`——PNG 取证会拦下平涂占位图和烤进底板的 RGB 图。

## 目录结构

```
data/       港口、货物、船种、章节、职事等 JSON 数据
scripts/    游戏脚本（core/ 为 autoload 单例：Fleet/Economy/Voyage/…）
scenes/     场景与 UI
tools/      Python 静态门禁（必跑十道，另有加跑档）+ Godot 门禁与探针 + 美术 / 船图管线（art_src/ 为生成原稿，gdignore）
docs/       设计文档、台账与门禁说明（索引见 docs/README.md）
assets/     美术资源
```

## 进度

- ✅ P0 地基 / P1 经济内核 / P3 航海层 / P5 职事与发现录 / P6 章节推进
- ✅ P2 舰队深化（海图、分船装载、分船船员、船体改装）
- ✅ P4 海战（炮击接入、接舷白刃夺船、弹数挂炮位 + 伤害乘甲）
- ✅ P6 其余：剧情旗标真正被场景/酒馆/职事消费；第四章四条结局（海口信路 / 账上的距离 / 史册未落笔 / 南海一纲兜底）
- ✅ Godot 4.6-stable 无头已跑通：import + `godot_smoke.gd` PASS，`Main.tscn` 启动无脚本错误
- ✅ 窗口点验已过（云电脑 XFCE + llvmpipe）：序章 → 海路 → 泉州三选一 → 酒馆旧事 → F12 了结预览；F11 进港 → 升帆 → F10 海盗 → 迎战 → J/K 舷炮 → B 逃走
- ✅ 海战船图精绘化：福船（牙色硬帆三桅、高艉楼、龙目）/ 海鹘（炭黑壳、绛红破帆、长桨）/ 铁子，真 RGBA 抠底，管线见上节
- ✅ 收官：拆除 crate / 海鸟 / 鲸影 / 野海盗刷怪（不恢复自由航行拾取）；`simulate_run` 从开局真跑到占城「南海一纲」，不垫 F12
- ✅ 存档 / 升章 / 了结弹窗与人物对话钮收进「绢本墨笔」主题
- ✅ 剧情字阶锁成标题 28 / 正文 18 / 脚注 13；选项 hover 挑签（左金杠滑出）
- ✅ 海图标题 / 状态栏 / 遭遇弹层收进绢本字阶；遭遇弹层居中；死生态位图从 `assets/` 拆除；海洋贴图 UID 对齐导入缓存
- ✅ 名声换爵：市舶职衔五档（籍外散商 → 市舶都保），折抽解、加赊贷；不另开港口/船种闸门
- ✅ 港口修埠：市舶司投钱升等，产地更廉、紧缺更好卖、市场更深；同港不套利
- ✅ 窗口点验回收：港卡改称市舶司/牙行；旅店按港进入候风页；设施图标按文件头加载
- ✅ 港卡三页接线：行会出港行情（信用加条数）、贡院誊录（工钱+学者倾向、不给名声）、住宅边记与便宜歇息（候风仍去旅店）；通用港同样九卡；兴化回访不再进序章调查页
- ✅ 寺观上陆勘见：近侧未入官图的旧迹耗日记入册子，赏格仍回市舶司呈报（寺观不转呈、不给名声）
- ✅ 寺观拓碑：已勘见的近侧旧迹再耗一日写入住处边记，不给名声
- ✅ 绢本界面做实：熟漆面板不透底图，港名泥金匾，设施图标金框，卷首收成册页；字体优先宋体（Noto Serif CJK SC / Songti SC）
- ✅ 晨潮三向 / 今日岸开三处 / 柜上三样 / 坞位一艘 / 顶栏与工席 / 海战顶匾 / 日志三卷（云端 UI 线，`docs/复刻设计_大航海时代标准.md` §十～十七）
- ✅ 哗变：不补水粮走到第 28 日，海上要在散钱、放人、压住里选；风涛按艘分摊
- ✅ 航法三策（针路 / 外洋 / 傍岸）、海上交市、牙行委办、行情传闻、八成日数与保货成数（嵌进三向牌与船况面板）
- ✅ 真实岸线（Natural Earth 386 环）+ 沿 sealanes 折线计里程、逐段罗经；海名岛名标注
- ✅ 本地剧情脊柱：跳年（2+3+4 年）、按月新闻、1268 殿试身份、战况机与战时三遭遇、守城 / 泉州对峙 / 涵江 / 崖山 / 辞呈 / 纲首收官、终局态与结局图；终局特殊卡不受「今日只开三处」限制
- 📎 云端两套 P7（b05c 纪事与终章、21ce 剧情闭环）：与主干 p6 结局系统同名平行实现，未收；设计稿、`data/endings.json` 留档待挑（`data/port_beats.json` 已按拍板 E-10 接回运行时：开关 `nk1/port_beats_runtime` 默认开，进港节拍照演、关掉即回旧行为）
- ⏳ 真机手感待 Snow 点验：十三道门禁（2026-09-27 当时口径；现行十七道见上文「验证」）（含有窗口巡检）全过，未在有人操作的窗口里看过

## 已知坑（点验/改图前必读）

- `assets/icon_*.png` 现已全是真 PNG（2026-09-25 随本地 main 进入）；`GameManager.load_texture` 仍**先按文件头解码**，纹理没有 `resource_path`，门禁核对底图用 `Main._bg_file`。窗口里灰叉多半是 `.godot` 缓存与 4.6 二进制不匹配
- 死生态位图（crate / 海鸟 / 鲸影）已从 `assets/` 与 WorldMap 删除，`godot_smoke.gd` 故意引用它们断言不存在，`check_assets.py` 对该文件放行
- `godot_story_check.gd` 与 `godot_smoke.gd` 共用 `user://saves/` 第 9 槽：前者用完即删，后者断言空卷；别手工往第 9 槽存档
- 海图 386 环岸线投影后缓存在 `MapView.coast_rings` / `coast_boxes`（`scripts/chart/MapView.gd`），按视窗包围盒裁剪、只描线不填色——陆地色由底图 `terrain_4096.png` 出；数据包围盒裁边处断成开放折线
- 新素材的 `.import` 与脚本的 `.uid` 侧车随**本 commit 的源文件**一起提交（仓库现行做法，2026-09-26 起统一；`.gitignore` 故意不忽略它们）：不带的话别处 `git clean` 后重导，uid 会全变、场景引用断开。并行窗口共享工作区时用显式 pathspec，**禁止** `git add .` / 盲加别人 lane 留下的未跟踪侧车噪声
- 视觉资产：皮肤在 `scripts/core/UiTheme.gd` 的 `const SKIN`（`juanben` 绢本 / `yechao` 夜潮）；立绘由 `tools/art/build_portraits.py` 生成，出了新油画直接覆盖 `assets/portraits/<id>.png` 并把 `data/characters.json` 该人 `portrait_status` 改 `painted`；新剧情文字落地后重跑 `python3 tools/art/subset_fonts.py` 补字

## 许可

未定。如需公开复用请先联系作者。
