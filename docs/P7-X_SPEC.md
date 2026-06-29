# P7-X 接口级 Spec ｜ CutscenePlayer 过场层

> 颁布者：架构主审。执行模型领单即照此实现，无歧义。
> TDD 强制：563 断言基线不可回退；本流新增 ≥8 断言。
> 铁律：架构只加不重构 / ponytail 极简 / 禁造动画系统 / 向后兼容。
> 单一职责：CutscenePlayer **只播过场**（CG+字幕+淡入淡出）；不操作 GameState，通过信号通信。

---

## 0. 锁定的集成事实（已读真实代码，非臆测）

### 0.1 港口抵达钩子 —— `scripts/Main.gd:279-287`
```gdscript
func _show_port_intro_if_needed(scene_data: Dictionary, scene_id: String) -> void:
	var intro: String = scene_data.get("intro", "")
	if intro == "":
		return
	var flag := "intro_shown:" + scene_id
	if GameState.has_story_flag(flag):
		return
	GameState.set_story_flag(flag)
	_prepend_event_log("【抵达】%s\n\n" % intro)   # ← 当前：日志行
```
**改动**：保留日志行（向后兼容），在 `_prepend_event_log` 调用**之后**追加：若该 port 有对应 cutscene，调 `cutscene_player.play(cutscene_id)`。cutscene_id 由 `data/cutscenes.json` 的 `hook:"port_arrival"` + `port_id` 匹配。**不删日志行**——它是 fallback，过场缺失时仍可见抵达信息。

### 0.2 章节切换信号 —— `scripts/state/StoryState.gd:16,57`
```gdscript
signal chapter_unlocked(chapter_id: String)   # :16
chapter_unlocked.emit(chapter_id)             # :57
```
**改动**：CutscenePlayer 在 `_ready` 连接 `GameState.story.chapter_unlocked` → 查 `cutscenes.json` 的 `hook:"chapter_change"` + `chapter_id` 匹配 → play。**不改 StoryState**。

### 0.3 升秩信号 —— `scripts/state/CareerState.gd`（P7-C 未建，预留）
P7-C 将定义 `signal rank_changed(new_rank: int)`。CutscenePlayer 在 `_ready` 连接 `GameState.career.rank_changed` → 查 `cutscenes.json` 的 `hook:"rank_up"` + `rank` 匹配 → play。**P7-C 未就绪时此连接留空/try-connect，不阻塞 P7-X 独立验收。**

### 0.4 结局钩子 —— P7-E `EndingResolver`（未建，预留）
P7-E 将调 `cutscene_player.play(ending_id)`。P7-X 只需保证 `play()` 公开 API 稳定。**P7-E 未就绪时不阻塞 P7-X 独立验收。**

### 0.5 CG 加载 —— 复用 `AssetPlaceholder.load_texture(path)`（`scripts/AssetPlaceholder.gd:142-153`）
已带纹理缓存 + 缺失降级到 `BG_FALLBACK`。**CutscenePlayer 禁自造加载逻辑**，一律走 `AssetPlaceholder.load_texture(cg_path)`。CG 路径先经 `AssetPlaceholder.get_background_path(alias)` 解析别名（:98-100）。

### 0.6 ResourcePaths —— `scripts/ResourcePaths.gd`
场景常量在 :19-27。**追加**：`const SCENE_CUTSCENE_PLAYER := "res://scenes/CutscenePlayer.tscn"`。数据文件常量在 :58-61，**追加**：`const DATA_CUTSCENES := "res://data/cutscenes.json"`。

### 0.7 现有场景节点 —— `scripts/Main.tscn` / Main.gd
Main.gd 有 `game_shell`、`port_mode`、`investigation_mode`、`title_mode` 等 Mode 节点。CutscenePlayer 作为 Main 的子节点（CanvasLayer，layer=100，覆盖全屏），`@onready var cutscene_player` 引用。或作为独立 autoload——**选 CanvasLayer 挂 Main 下**（autoload 会跨场景常驻，过场只需游戏内，无需 autoload）。

---

## 1. 新建文件

### 1.1 `scripts/CutscenePlayer.gd` —— 完整签名

```gdscript
class_name CutscenePlayer extends CanvasLayer

## 过场播放器（P7-X）
## 职责：播全屏 CG + 字幕 + 淡入淡出；可跳过；可多分镜。
## 不操作 GameState，通过信号 finished 通知调用方。
## CG 加载复用 AssetPlaceholder.load_texture（已带缓存+降级）。

signal finished(cutscene_id: String)

const FADE_DURATION := 0.4          ## 淡入淡出秒数
const PANEL_DURATION := 2.5         ## 单分镜默认停留秒数（无 panels 时主图停留）
const PANEL_FADE := 0.3             ## 分镜间淡出
const LAYER := 100

@onready var _bg: TextureRect = $Bg          ## 全屏 CG
@onready var _caption: RichTextLabel = $Caption  ## 字幕（底部，bbcode）
@onready var _skip_hint: Label = $SkipHint   ## "按 空格/点击 跳过" 提示

var _data: Dictionary = {}          ## cutscenes.json 缓存 {id: entry}
var _playing: bool = false
var _current_id: String = ""
var _tween: Tween = null
var _panels: Array = []             ## 当前过场的分镜序列
var _panel_index: int = 0

func _ready() -> void:
	layer = LAYER
	visible = false
	_load_data()
	_connect_signals()
	_skip_hint.text = "按 空格 或 点击 跳过"

## 公开 API：播放过场。cutscene_id 不存在则静默返回（降级，不崩）。
func play(cutscene_id: String) -> void:
	if _playing:
		return
	var entry: Dictionary = _data.get(cutscene_id, {})
	if entry.is_empty():
		return   # 降级：无此过场，静默
	_current_id = cutscene_id
	_panels = entry.get("panels", [])
	_panel_index = 0
	_playing = true
	visible = true
	_skip_hint.visible = true
	if _panels.is_empty():
		_play_single(entry)
	else:
		_play_panel(_panels[0])

## 跳过当前过场
func skip() -> void:
	if not _playing:
		return
	_end()

## 查询某 hook+id 是否有对应过场（供调用方决定是否播）
func has_cutscene(hook: String, id: String) -> bool:
	# 遍历 _data 找 hook==hook 且 (port_id/chapter_id/rank)==id
	...

## ── 内部 ────────────────────────────────────────────────

func _play_single(entry: Dictionary) -> void:
	var cg_path := AssetPlaceholder.get_background_path(entry.get("cg_alias", ""))
	var tex := AssetPlaceholder.load_texture(cg_path)
	_bg.texture = tex
	_caption.text = entry.get("caption", "")
	_fade_in_then_wait(FADE_DURATION, PANEL_DURATION)

func _play_panel(panel: Dictionary) -> void:
	var cg_path := AssetPlaceholder.get_background_path(panel.get("cg_alias", ""))
	var tex := AssetPlaceholder.load_texture(cg_path)
	_bg.texture = tex
	_caption.text = panel.get("caption", "")
	var dur := float(panel.get("duration", PANEL_DURATION))
	_fade_in_then_wait(FADE_DURATION, dur)

func _fade_in_then_wait(fade_in: float, wait: float) -> void:
	if _tween:
		_tween.kill()
	_bg.modulate.a = 0.0
	_caption.modulate.a = 0.0
	_tween = create_tween()
	_tween.tween_property(_bg, "modulate:a", 1.0, fade_in)
	_tween.parallel().tween_property(_caption, "modulate:a", 1.0, fade_in)
	_tween.tween_interval(wait)
	_tween.tween_callback(_on_panel_done)

func _on_panel_done() -> void:
	_panel_index += 1
	if _panel_index < _panels.size():
		# 分镜间淡出再淡入
		if _tween: _tween.kill()
		_tween = create_tween()
		_tween.tween_property(_bg, "modulate:a", 0.0, PANEL_FADE)
		_tween.tween_callback(func(): _play_panel(_panels[_panel_index]))
	else:
		# 淡出收尾
		if _tween: _tween.kill()
		_tween = create_tween()
		_tween.tween_property(_bg, "modulate:a", 0.0, FADE_DURATION)
		_tween.parallel().tween_property(_caption, "modulate:a", 0.0, FADE_DURATION)
		_tween.tween_callback(_end)

func _end() -> void:
	if _tween:
		_tween.kill()
	_playing = false
	visible = false
	_skip_hint.visible = false
	var id := _current_id
	_current_id = ""
	finished.emit(id)

func _load_data() -> void:
	# 读 ResourcePaths.DATA_CUTSCENES，JSON 解析，缓存到 _data {id: entry}
	# 文件缺失/解析失败 → _data = {}，play() 静默降级
	...

func _connect_signals() -> void:
	# 章节切换：GameState.story.chapter_unlocked → _on_chapter_unlocked
	if GameState and GameState.story:
		GameState.story.chapter_unlocked.connect(_on_chapter_unlocked)
	# 升秩：P7-C 就绪后连接（try，不阻塞）
	if GameState.get("career") != null:
		GameState.career.rank_changed.connect(_on_rank_changed)
	# 港口抵达：由 Main._show_port_intro_if_needed 直接调 play()，不走信号

func _on_chapter_unlocked(chapter_id: String) -> void:
	var cs_id := _find_by_hook("chapter_change", chapter_id)
	if cs_id != "":
		play(cs_id)

func _on_rank_changed(new_rank: int) -> void:
	var cs_id := _find_by_hook("rank_up", str(new_rank))
	if cs_id != "":
		play(cs_id)

func _find_by_hook(hook: String, id: String) -> String:
	for key in _data:
		var e: Dictionary = _data[key]
		if e.get("hook", "") == hook:
			var match_field := "chapter_id" if hook == "chapter_change" else "rank"
			if str(e.get(match_field, "")) == id:
				return key
	return ""

func _unhandled_input(event: InputEvent) -> void:
	if not _playing:
		return
	if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_SPACE and event.is_pressed():
		skip()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.is_pressed():
		skip()
		get_viewport().set_input_as_handled()
```

### 1.2 `scenes/CutscenePlayer.tscn`
```
CutscenePlayer (CanvasLayer, layer=100)
├─ Bg (TextureRect, anchor=full, stretch=aspect_cover, modulate.a=0)
├─ Caption (RichTextLabel, anchor=bottom, bbcode_enabled, align=center, 位置底部 15% 高度带半透明黑底)
└─ SkipHint (Label, anchor=bottom-right, text="按 空格 或 点击 跳过", 透明度 0.5)
```
- Bg 用 `TextureRect` + `texture_repeat`，`expand_mode=ignore_size`，`stretch_mode=aspect_cover`
- Caption 字体走 `UITheme` 现有 theme_variation（不新造），颜色 `GameColors.TEXT_GOLD_BRIGHT`
- SkipHint 字号小，`GameColors.TEXT_DIM`（若无则半透明白）

### 1.3 `data/cutscenes.json`
```json
{
  "version": 1,
  "cutscenes": {
    "quanzhou_arrival": {
      "hook": "port_arrival",
      "port_id": "quanzhou",
      "cg_alias": "res://assets/bg_quanzhou_harbor_koei.png",
      "caption": "[b]刺桐港[/b]\n宋元第一大港，万国商舶云集之地。",
      "panels": []
    },
    "ch3_start": {
      "hook": "chapter_change",
      "chapter_id": "chapter3_pu_counter",
      "cg_alias": "res://assets/bg_quanzhou_arab_market.png",
      "caption": "[b]第三章 · 蒲氏反击[/b]",
      "panels": [
        {"cg_alias": "res://assets/bg_quanzhou_arab_market.png", "caption": "蒲寿庚召你入府...", "duration": 3.0},
        {"cg_alias": "res://assets/bg_customs_patrol.png", "caption": "市舶司的暗流涌动。", "duration": 2.5}
      ]
    },
    "rank_up_1": {
      "hook": "rank_up",
      "rank": 1,
      "cg_alias": "res://assets/bg_quanzhou_harbor_koei.png",
      "caption": "你升任 [b]副纲首[/b]。",
      "panels": []
    },
    "ending_loyalty": {
      "hook": "ending",
      "ending_id": "loyalty_ending",
      "cg_alias": "res://assets/bg_sea_route_koei.png",
      "caption": "[b]结局 · 忠义[/b]\n你选择了与陈文龙共存亡...",
      "panels": []
    }
  }
}
```
字段约定：
- `hook`: `port_arrival` | `chapter_change` | `rank_up` | `ending`
- `port_id` / `chapter_id` / `rank` / `ending_id`: 按 hook 选一，匹配用
- `cg_alias`: 走 `AssetPlaceholder.get_background_path()` 解析
- `caption`: RichTextLabel bbcode 字符串
- `panels`: 可选数组；空则单图；每 panel 同 `cg_alias`+`caption`+`duration`

---

## 2. 改动现有文件（精确行）

### 2.1 `scripts/ResourcePaths.gd`
- :27 后追加：`const SCENE_CUTSCENE_PLAYER := "res://scenes/CutscenePlayer.tscn"`
- :61 后追加：`const DATA_CUTSCENES := "res://data/cutscenes.json"`

### 2.2 `scripts/Main.gd`
- **节点声明区**（参照现有 `@onready var port_mode` 等）追加：`@onready var cutscene_player: CutscenePlayer = $CutscenePlayer`（节点名以 .tscn 实际为准）
- **`_show_port_intro_if_needed()`（:279-287）** 末尾，`_prepend_event_log` 调用**之后**追加：
  ```gdscript
  # P7-X: 港口抵达过场（可选，数据驱动，缺失则静默）
  var port_id := scene_data.get("location", scene_id.replace("port_", ""))
  var cs_id := cutscene_player._find_by_hook("port_arrival", port_id)
  if cs_id != "":
  	cutscene_player.play(cs_id)
  ```
  （`_find_by_hook` 设为公开或加公开包装 `get_cutscene_id_for(hook, id)`——执行模型自洽，优先加公开包装方法不暴露内部）

### 2.3 `scenes/Main.tscn`
- 追加 CutscenePlayer 子节点（instance `CutscenePlayer.tscn`），名 `CutscenePlayer`，layer=100

### 2.4 `scripts/GameState.gd`（**仅当需全局访问时**）
- 若 Main 持有 cutscene_player 已够（P7-E 在 Main 场景内调），则**不进 autoload**。
- 若 P7-E 需跨场景访问，则后续加 autoload——**P7-X 不预判，默认 Main 持有**。

---

## 3. 验收清单

- [ ] 抵达主港（如 quanzhou）触发抵达过场；无对应 cutscene 的港口静默不崩
- [ ] 章节解锁（`chapter_unlocked` 信号）触发对应过场（P7-A 章三接入后验证；P7-X 独立验收可用测试 fixture 触发信号）
- [ ] 升秩过场（P7-C 就绪后验证；P7-X 独立验收可 mock 信号）
- [ ] `play(不存在的id)` 静默返回，不崩
- [ ] 空格/点击可跳过；跳过后 `finished` 信号发出
- [ ] CG 缺失（cg_alias 指向不存在文件）→ AssetPlaceholder 降级到 BG_FALLBACK，不崩
- [ ] 不破坏现有场景流（抵达后仍能正常进入港口）
- [ ] **563 断言全绿**

## 4. 新增测试组 `[CutscenePlayer]`（≥8 断言）

1. `play("不存在")` 静默返回，`_playing` 保持 false
2. `play("quanzhou_arrival")` 后 `_playing=true`，`visible=true`
3. `skip()` 后 `_playing=false`，`visible=false`，`finished` 信号发出
4. `_find_by_hook("port_arrival","quanzhou")` 返回 "quanzhou_arrival"
5. `_find_by_hook("port_arrival","不存在的港")` 返回 ""
6. `_find_by_hook("chapter_change","chapter3_pu_counter")` 返回 "ch3_start"
7. `cutscenes.json` 缺失时 `_data={}`，`play` 任何 id 静默不崩
8. panels 多分镜：`_panel_index` 推进至 size 后触发 `_end`
9. CG 路径经 `AssetPlaceholder.get_background_path` 解析别名（验证调用，非实际加载）

测试参照 `scripts/systems/TestRunner.gd` 模式（执行模型先读此文件确认断言风格）。CG 实际加载/渲染在 GUT 单元测试里 mock 或跳过，只测逻辑。

---

## 5. 禁止事项

- 禁造动画系统（Tween 淡入淡出足矣，不引入 AnimationPlayer）
- 禁自造 CG 加载/缓存（复用 `AssetPlaceholder.load_texture`）
- 禁直接操作 GameState（flag/fame/career 都不碰）
- 禁进 autoload（除非 P7-E 证明必须跨场景，P7-X 默认 Main 持有）
- 禁新增 silent key
- 禁重构现有 .tscn 节点结构（只追加 CutscenePlayer 子节点）
- 禁删 `_show_port_intro_if_needed` 的日志行（向后兼容 fallback）

_主审钉死。4 钩子已对应真实代码行/信号；CG 加载复用已验证的 AssetPlaceholder；独立可验收（P7-C/E 未就绪不阻塞）。_
