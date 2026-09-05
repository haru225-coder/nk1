# 东亚海域立志传（nk1）

> 南宋末年泉州海商题材的航海经营游戏。海图点选、按日推进、遭遇弹窗——以光荣《大航海时代 II》的经济与航海内核为骨架，套用《大航海时代 IV》的剧情舰队结构。

## 这是什么

你扮演南宋末年的泉州海商，驾驶舰队往返东亚海域（泉州、博多、耽罗、占城、广州……）低买高卖、走私违禁品、迎战海盗、招募职事、改装船只，在朝代更迭的乱世里经营一支海商舰队。

核心循环是**套利贸易**：货物在产地与消费地之间有真实的异地差价，去程南下、回程北上各有不同的盈利路线；季风决定航期（去日本要等夏季西南风、回泉州要赶冬季东北风），补给和船员是远洋的硬约束，砸盘、查扣、风暴、海战都是真实的经营风险。

**剧情为骨、沙盒为肉**：98 个历史考据扎实的剧情场景作章节闸门，解锁港口与船种；章节之间是完全自由的沙盒贸易。

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

代码改动后必须跑这三套静态校验（改数据尤其要重跑）：

```bash
python3 tools/check_symbols.py    # autoload 顺序与跨文件符号（GDScript 动态语言的必要保险）
python3 tools/verify_economy.py   # 数据完整性 / 套利 / 砸盘 / 季风 / 死港 / 海战数值边界
python3 tools/simulate_run.py     # 端到端跑一局，找死锁与账目溢出
python3 tools/verify_story_data.py # 剧情数据：scenes effects 键必须被 Main.apply_effects 接住；news.json / npcs.json 结构；GameState 存档字段对称
```

有 Godot 4.6.3 时再加第四道引擎内编译门禁（2026-09-03 起；建议先把项目 rsync 到临时目录再跑，编辑器扫描会生成 `.godot/` 与 `*.gd.uid`）：

```bash
godot --headless --editor --path . --quit                    # 编辑器扫描：期望 0 ERROR / 0 WARNING
godot --headless --path . -s tools/godot_compile_check.gd    # 带 autoload 逐脚本编译：期望 18/18
godot --headless --path . -s tools/godot_story_check.gd      # 剧情状态机：新闻按月投放、1268 殿试结算、存档 round-trip：期望 fails=0
```

不要用 `--check-only` 当门禁：它不实例化 autoload，会把 `GameManager`/`Fleet` 等引用误报为 Identifier not found，且有 SCRIPT ERROR 时退出码仍为 0。

六道全绿才算一次改动闭环。数值平衡很脆，参数依据见 `docs/复刻设计_大航海时代标准.md`。

## 目录结构

```
data/       港口、货物、船种、章节、职事等 JSON 数据
scripts/    游戏脚本（core/ 为 autoload 单例：Fleet/Economy/Voyage/…）
scenes/     场景与 UI
tools/      三套 Python 静态校验脚本 + Godot 引擎内编译门禁（godot_compile_check.gd）
docs/       复刻设计文档
assets/     美术资源
```

## 进度

- ✅ P0 地基 / P1 经济内核 / P3 航海层 / P5 职事与发现录 / P6 章节推进
- ✅ P2 舰队深化（海图、分船装载、分船船员、船体改装）
- ✅ P4 海战（炮击接入、接舷白刃夺船、弹数挂炮位 + 伤害乘甲）
- ✅ 2026-09-03 首次通过 Godot 4.6.3 headless 编译：`tools/godot_compile_check.gd` 18/18、编辑器扫描 0 ERROR / 0 WARNING、主场景 `--quit-after 3` 可启动（融合方案 P0.5，提交 1ee11f6）
- ⏳ 真机手感待点验：只在 headless 下编译与启动过，未在有窗口的引擎里实际玩过

## 许可

未定。如需公开复用请先联系作者。
