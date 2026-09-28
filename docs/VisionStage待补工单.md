# VisionStage 待补工单（2026-09-28，lane vs1）

> 来源：`.claude/todo.md` 视觉资产线「VisionStage 待补」（① 舷侧炮焰 / 水花手绘序列帧；② 大裱框泥金角花；③ 海战定格底用宋绢海图残片替换程序椭圆）。
> **现状**：三项在 lane v2 `6f51544` 已有程序版上屏（`tools/art/vision_fill_gen.gd` 固定种子生成 → `scenes/vision/fill/` 四张，`scripts/ui/VisionStage.gd` 挂载；缺图回落旧粒子点 / 程序椭圆）。todo 那行没跟着改。
> **本单只收必须出图的**：①「手绘」和 ③「宋绢」这两个词，程序版都做不到（见下「判定」）。② 已由程序做完，不进工单。
> **本机没有生图模型、没有 GPU，也没有绢本扫描件**：图要由人手绘或用 Grok / 出图台出，本单只给规格、提示词和依赖。

## 判定

| 项 | 判定 | 依据 |
|---|---|---|
| ② 大裱框泥金角花 | **可程序化，已落地（v2 `6f51544`）** | 角花是对称线描纹样（外框双线 + 如意云头 + 卷草），矢量笔画栅格化就能画（`vision_fill_gen.gd` `_corner_gilt`，96×96，泥金颗粒 + 金屑高光 + 墨影）。`VisionStage._add_gilt_corners` 用一张左上角纹样 flip 出四角，节点 `PortraitPane/GiltCorners/Corner{TL,TR,BL,BR}`，每角 58 px（`CORNER_PX`），内缩 3 px 压在外框金线上。`vision_fill_shots` 契约断言四角都在。《美术规范》把泥金定为「描线、角花、分隔线」，程序线描正对口，不需要出图 |
| ① 舷侧炮焰 / 水花序列帧 | **必须出图**（程序占位已在用） | 现在两条序列帧是噪声 + 解析形状算出来的（`_muzzle_strip` / `_splash_strip`），形体和节奏对，但是没有笔触。「手绘」要的是墨笔干湿、飞白和逐帧手感，程序噪声出不来。本机能做的只是保证规格不变，图画好了覆盖同名文件就能用，不改代码 |
| ③ 海战定格底：宋绢海图残片 | **必须出图 / 须有实物源**（程序仿绘已在用，不是绢本） | 现在的 `vs_chart_fragment.png` 是**程序仿绘**：绢地经纬纹、水渍、焦边、虫蛀、计里画方、鱼鳞水纹、岸线、山形符都是算出来的，**不是宋绢实物，也不是扫描件**。查过仓库：`assets/` 下没有绢本海图或绢本扫描；`assets/fx/silk_weave.png` 是 `build_fx_textures.py` 程序生成的织纹噪声；`assets/cutscene/cs_world_map_gold.jpg` 是过场用的生成画（右上一枚西式罗盘、四边洋式浪花框），不是绢本；标题底图的「宋绢本候选」`~/tmp/nk1-art-work/title_bg/cand2_a_qinglv.jpg` 也是程序绘，而且不在仓库里。所以「换成宋绢」目前做不到，程序椭圆只是被换成了程序仿绘 |

## 工单

通用：提示词末尾追加 `docs/资产生成提示词_2026-09-14.md` §0 风格基座；画里不要写字；透明底的必须是 RGBA PNG。出图后覆盖同名文件 → `godot --headless --import --path .` → 截图门禁看效果（见每行「依赖」）。**换上手绘 / 绢本以后别再整跑 `vision_fill_gen.gd`**：它会把四张一起重写回程序版（文件头已注明）。

| # | 资产名 | 规格 | 提示词（中文；负面进 Avoid） | 用在哪里 | 依赖 |
|---|---|---|---|---|---|
| 1 | `scenes/vision/fill/vs_muzzle_strip.png`（舷侧炮焰，手绘替换程序版） | 1024×64 RGBA 透明底，横排 8 帧，每帧 128×64；每帧炮口都在帧内 (6,32)，焰朝 +x；帧 0 炮口一团亮芯 → 帧 1–2 焰舌最长（约 90 px） → 帧 3–4 焰收、暖墨烟团涌出 → 帧 5–7 烟团外推、上飘、变淡。12 fps、不循环。帧左缘 4 px 内不能有不透明像素，否则会被帧边切出硬线 | 宋画墨笔风格的火炮出膛序列帧，侧视，从左向右喷：芯是米白泛金，外焰赭金、朱砂收边，焰舌是毛笔一笔扫出来的尖叶形，带飞白；随后涌出**暖墨**烟团，淡墨晕染、干笔起毛边，逐帧向前推、向上飘、越散越淡。单色透明底，8 帧等宽横排，每帧炮口位置固定。负面：photoreal explosion, lens flare, glow bloom, sparks shower, cartoon outline, blue smoke, black background, text | `VisionStage` `CombatFreeze/Muzzle0..2`（AnimatedSprite2D，缩放 0.95 / 0.87 / 0.79，按门错开 0.12 s，沿炮位指向海鹘）；帧切法见 `VisionStage.gd` `MUZZLE_CELL` / `MUZZLE_ORIGIN` | **须人手绘或出图台出**（本机无生图）。生图模型逐帧一致性差：建议先出单帧定稿，再由人拆 8 帧、对齐炮口。尺寸、帧数、原点不变就不用改代码；要改的话同步 `MUZZLE_*` 常量和 `vision_fill_shots.gd` 的 `MUZZLE_PEAK`。验：`vision_fill_shots` 02 / 04 张、`vision_stage_probe` |
| 2 | `scenes/vision/fill/vs_splash_strip.png`（落弹水花，手绘替换程序版） | 768×128 RGBA 透明底，横排 8 帧，每帧 96×128；水线点在帧内 (48,112)；帧 0 起柱 → 帧 3 柱顶最高（约 100 px，冠开） → 帧 4–6 塌落散成水点 → 帧 7 只剩外扩水圈。12 fps、不循环 | 宋画白描风格的落弹水柱序列帧：绢白水柱，靛影只在背光一侧，柱边淡墨一线勾（不是卡通描边），柱顶开成浪花冠；基脚是随帧外扩的扁椭圆水圈；后几帧水柱断成团块、飞沫点四溅。参照马远《水图》那种勾线浪法。单色透明底，8 帧等宽横排，每帧水线位置固定。负面：photoreal water, cyan / neon blue, glossy highlight, cartoon splash, heavy black outline, background, text | `VisionStage` `CombatFreeze/Splash0..1`（缩放 0.9 / 0.7，齐射后 0.42 s 起、两柱相隔 0.16 s，落在海鹘近旁）；底下是 #3 那张绢色海图，水花要压得住浅赭底（现版柱顶在浅底上看得清，见 lane vs1 Verify 截图） | 同 #1：须人出图；原点 / 帧数不变就不用改代码。`vision_fill_shots` 按第 3 帧拍「柱顶」、第 6 帧拍「塌落」，如果节奏改了，同步 `SPLASH_PEAK` / `SPLASH_FALL`。验：`vision_fill_shots` 03 / 04 张 |
| 3 | `scenes/vision/fill/vs_chart_fragment.png`（海战定格底，绢本替换程序仿绘） | 768×400 RGBA；主体不透明，四边残破成毛边透明，右下缺一角，靠边留几个虫蛀洞（形状自由）；绢色偏暖（旧绢 `#cdb88f` 一带，上屏还会乘 modulate (0.70,0.66,0.60) 压暗）；左上约 1/3 是陆（淡赭）、其余是海（鱼鳞水纹或勾线浪），右下一个小岛；画幅中部（船位 x≈300–560）要留空，别放山形符、题字 | 路线 A（实物源）：拿**公有领域**宋代绢本水纹画的高清扫描（首选马远《水图》卷局部）当海面底，再叠计里画方淡墨方格与岸线、山形符，做残边焦黄与虫蛀。路线 B（人绘）：「南宋绢本淡设色残卷，局部是一幅沿海舆图：淡墨计里画方方格，左上陆地赭石淡染，焦墨岸线双勾，三峰山形符，海面鱼鳞状勾线浪纹，右下一座小岛；绢面有经纬细纹、水渍、边缘焦黄碎裂、虫蛀小洞，右下缺一角」。负面：compass rose, sea monster, European portolan, rhumb lines, latitude grid, printed map labels, parchment, text | `VisionStage` `CombatFreeze/ChartFragment`（Sprite2D，位置 (120,30)，缩放 0.94，旋转 −0.025，modulate (0.70,0.66,0.60)）；缺图回落程序椭圆 | **史实口径待策划定**：宋代没有存世的绢本海图；「计里画方」出自南宋《禹迹图》（1136，石刻拓本，不是绢本），鱼鳞水纹是画法借用。现在的「宋绢海图残片」是一个美术设定，不是在复刻实物，要改口径就改这一行的名义，不影响代码。路线 A 要先核扫描件的来源和授权，以及分辨率够不够（≥1536 px 宽再缩）。尺寸不变就不用改代码。验：`vision_fill_shots` 01 张、`vision_stage_probe`、`vision_letterbox_probe` |
