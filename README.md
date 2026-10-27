# 东亚海域立志传（nk1）

**简体中文** | [English](README.en.md) | [日本語](README.ja.md)

一款以南宋末年东亚海域为舞台的历史航海经营游戏，用 Godot 4.6 制作。

宋宝祐三年（1255），兴化海口。你扮演莆田玉湖出身的士子陈子龙，从一条小艍船起家，往返泉州、明州、博多、耽罗、占城等港口做买卖、接委办、应付海盗与查扣。二十多年后，蒙元南下，海商的账本与王朝的存亡缠在了一起。

> 游戏内文字目前只有中文。项目仍在积极开发中，尚未发布正式版本。

<p>
  <img src="docs/screenshots/title.png" width="49%" alt="标题画面">
  <img src="docs/screenshots/sea-chart.png" width="49%" alt="海图：选航向">
  <img src="docs/screenshots/port-fuzhou.png" width="49%" alt="港口：福州">
  <img src="docs/screenshots/naval-battle.png" width="49%" alt="海战">
</p>

<sub>截图由 `tools/patrol_shell.gd` 与 `tools/qa_chart_hud_screenshots.gd` 在 1280×720 窗口下实机渲染。</sub>

## 游戏内容

- **时代与人物**：故事自宝祐三年（1255）起，到祥兴二年（1279）崖山止。`data/characters.json` 收录 75 个人物，其中 41 位是史实人物，如文天祥、张世杰、陆秀夫、蒲寿庚、贾似道、伯颜、忽必烈、北条时赖等；生卒年与史料核对记录在 `docs/` 中。
- **史实尺度**：全作起于 1255 年，止于 1279 年。中国只写宋、金、元三代；日本取镰仓，耽罗属高丽，占城按印度教的占婆王朝，南岛海道北口按琉球城郭时代。明州即庆元府，纸币用会子、关子，城郭、衣冠、舟式不取明清形制；金中都自 1215 年焚毁后只是蒙古治下的残城。
- **港口与海图**：14 处港口，从兴化、泉州、福州、温州、澎湖，到明州、耽罗、博多唐房、广州、萨摩、占城，随章节逐步开放。海图依真实经纬度与 Natural Earth 岸线绘制，航程沿航线折线计算，季风决定航期。
- **城中各处**：泉州、兴化、广州、温州、博多唐房五港的港页多一枚「城中各处」，进去是这港的城区，共 71 处、281 条经营事：买卖、放本、雇人、打听行情、领公凭、应时节，各有底图。
- **经济**：29 种货物（米粮、生丝、青白瓷、香药、倭铜、日本刀……）分产地与消费地，异地差价、市场深度、砸盘、违禁品、市舶司抽解、牙行委办、战时物价都会影响收益。另有 8 种船、船员与补给、修埠投资、五档市舶职衔。
- **节令与赊销**：米粮、茶叶、生丝、绢帛、海盐、貂皮、鹿皮、倭扇、经卷九样货随月令起落（米粮四月最贵、秋收后最贱）；舱货可赊与本港牙行，言明锁价，两月后结账，倒账看海商信用与战况。
- **船坞与改装**：船坞一次只搁一艘，帆、甲、捻缝各分三等，可逐级升；帆增日速，甲减船体伤，捻缝减风涛、触浅的船体伤与易碎货水损。
- **酒馆与港内**：酒馆里听传闻、招募船员、遇见人物；港内还有市舶司、牙行、船坞、旅店、行会、贡院、寺观等去处。
- **新手小笺**：新开一局，头一回进港、进牙行、开海图、遇盗、进市舶司、跑完一程，页边各出一张，六张看过便不再出。
- **战斗**：海战为实时操船（风向、舷炮、弹药、浸水失火、接舷白刃、士气），此外还有登陆袭扰、守城与围城战，以及崖山一役。设计见 [docs/combat_realism_design.md](docs/combat_realism_design.md)。
- **剧情**：四章主线（海口 / 旧账 / 纲首 / 南海），105 个剧情场景作为章节闸门，章与章之间是自由经营；终局有四条结局。
- **存档与过场**：3 个存档栏位（坏档会退回 `.bak` 备份）；开场、章节与结局都有带字幕的电影式过场。
- **美术**：人物志 75 人各有立绘（74 幅油画、1 幅剪影待绘），另有 29 张货图、8 张船谱方图、71 幅城区底图；界面为绢本水墨。

## 当前状态

- 主线四章、经济、航海、海战、守城与结局都已可从头玩到尾；`tools/simulate_run.py` 会从开局自动跑到结局检查死锁。
- 城区页目前开放泉州、兴化、广州、温州、博多唐房五港；其余港口的城区还在绘制，尚未进游戏。
- 伙伴系统已有名册与立绘，尚未接进经营；设计仍在拍板中。
- 开发过程以设计文档与自动化门禁驱动，提交历史从 2026-06 开始，已有近 1700 笔提交。

## 运行

需要 [Godot 4.6](https://godotengine.org/)（标准版即可，项目只用 GDScript，无第三方插件）。

1. 克隆本仓库。
2. 用 Godot 4.6 打开 `project.godot`，按 F5 运行（主场景为 `scenes/Main.tscn`）。

或者在命令行里：

```bash
godot --path .
```

没有独立显卡的 Linux 机器可以用兼容渲染器：`godot --path . --rendering-method gl_compatibility`（`.cursor/run-game.sh` 是在无 GPU 虚拟机里启动的示例脚本）。如果画面黑屏或贴图变成灰叉，多半是 `.godot/` 导入缓存与当前 Godot 版本不匹配，删掉 `.godot/` 后执行 `godot --headless --import --path .` 重建。

海战按键：**W/S** 帆档、**A/D** 操舵、**J/K** 左右舷开火、**G** 接舷、**B/Esc** 弃战。

## 自动化检查

一次改动闭环 = 下面三十六道门禁全绿。每道门禁检查什么、失败时是什么样子，见 [docs/GATES.md](docs/GATES.md)；完整命令清单见 [docs/开发笔记.md](docs/开发笔记.md)。

Python 检查不需要 Godot（Python 3，标准库即可）：

```bash
python3 tools/check_symbols.py      # 跨文件符号、autoload 顺序、文案规范与各功能契约
python3 tools/verify_economy.py     # 数据完整性、套利、砸盘、季风、委办等经济规则
python3 tools/simulate_run.py       # 端到端自动跑一局，找死锁与账目溢出
python3 tools/verify_story_data.py  # 剧情效果键与存档字段
python3 tools/check_probe_registry.py  # 每支探针都已登记
```

Godot 检查（先导入一次资源）：

```bash
godot --headless --import --path .
godot --headless --path . -s res://tools/godot_smoke.gd          # 冒烟，末行 GODOT SMOKE PASS
godot --headless --path . -s res://tools/godot_compile_check.gd  # 所有脚本可编译
godot --headless --path . -s res://tools/godot_story_check.gd    # 剧情主线与存档往返
```

`tools/` 下还有 180 多支 `qa_*_probe.gd` 运行时探针，覆盖海图、经济面板、存档、过场、海战、无障碍焦点、音效等；单支运行方式相同：`godot --headless --path . -s res://tools/<探针>.gd`。

## 目录结构

```
data/      港口、货物、船种、人物、章节、剧情场景、过场、结局等 JSON 数据
scenes/    场景（主场景、海图、海战、过场、UI）
scripts/   GDScript；core/ 为 autoload 单例（Calendar、Economy、Fleet、Crew、Voyage、SaveLoad）
assets/    美术、字体、着色器、船体网格、海图底图
tools/     Python 静态检查、Godot 冒烟与运行时探针、美术与船图管线
docs/      设计文档、史料核对、审计台账与门禁说明（索引见 docs/README.md）
```

## 参与贡献

详细说明见 [CONTRIBUTING.md](CONTRIBUTING.md)。

欢迎提 Issue 和 Pull Request，尤其是史实考据、文案、平衡性和 Bug 报告。

- 提交前请跑上面的检查；改了哪一块，至少跑对应的门禁（对照 [docs/GATES.md](docs/GATES.md)）。
- 新增脚本或素材时，把 Godot 生成的 `.uid` / `.import` 文件一起提交（`tools/check_sidecars.py` 会检查）。
- 在 `docs/` 下新增文档时，在 [docs/README.md](docs/README.md) 补一行索引。
- 数值平衡比较敏感，参数依据见 [docs/复刻设计_大航海时代标准.md](docs/复刻设计_大航海时代标准.md)。

## 许可

源代码以 [MIT 许可](LICENSE) 发布（Copyright (c) 2026 haru225-coder）。`assets/` 下的美术、音乐等素材不在 MIT 许可范围内，除另有说明外保留所有权利，详见 [ASSETS.md](ASSETS.md)。
