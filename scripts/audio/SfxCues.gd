## 音效挂点表（lane w54-audio）：游戏里每一处发声都在这张表里登记一行——挂点叫什么、挂在哪、放哪一样声、多响。
## 各处只写一句 `SfxCues.play(节点, &"挂点")`，声样与音量都在表里改，不散在各个文件里。
##
## 声样只用 SfxSynth 现成的八样（transition 一声轻磬带风 / combat_start 两记战鼓 / combat_fire 炮声 / combat_hit 船板碎裂 /
## combat_board 钩索闷撞带两下金铁 / combat_win 三记磬音上行 / combat_lose 两记下行 / combat_flee 掠过的风声），
## 不另做声音（qa_w54_audio_cues_probe 逐行查）。播放、静音、节流、声部上限都在 AudioHooks：
## 总静音 AudioHooks.enabled（或启动时 NK1_SFX=0）、总音量 AudioHooks.volume_db 加在每一行的 dB 上。
## headless 不出声也不报错（AudioHooks 不建播放器，只在发声账 journal 里记一笔）。
##
## 本件不直读 autoload（Fleet / GameState …）：Ship / PirateShip / Cannonball 都 preload 它，-s 工具 preload 那几件时照样编得过。
extends RefCounted

const _AUDIO := preload("res://scripts/audio/AudioHooks.gd")

## 挂点 → {layers: 声层, where: 挂在哪, gap_key: 节流认哪把锁（可缺）, group: 收声组（可缺）}。声层一行 [声样, dB]（dB 在 AudioHooks.volume_db
## 之上再加；全表都在 0 以下）。同一样声多快能再响按 AudioHooks._MIN_GAP_MS（开炮 90 毫秒、命中 60 毫秒），锁缺省按声样——
## 旗舰齐射另起一把锁（gap_key），敌船 / 护航刚放过一排也吞不掉玩家自己按下去的那一排。
## 收声组（group）：同组的新声一响，还在响的旧声当场收掉——墨幕被新墨幕顶掉时（晋升翻页全黑时排守城 / 终局岸带头一回，
## 又起一幕题签），旧幕那声磬跟着收，不叠成两声。
## 原先就有的七处（lane-s 起的 AudioHooks 具名口）搬进表里，声样、音量一字不差。
const HOOKS := {
	&"transition": {"layers": [[&"transition", -5.0]], "group": &"bell", "where": "Main.play_transition（墨幕过渡）"},
	&"sea_start": {"layers": [[&"combat_start", -4.0]], "where": "WorldMap._setup_combat（入战）"},
	&"sea_fire": {"layers": [[&"combat_fire", -7.0]], "where": "PirateShip._process_firing（敌船 / 护航开炮）"},
	&"sea_fire_own": {"layers": [[&"combat_fire", -7.0]], "gap_key": &"combat_fire_own", "where": "Ship 齐射两路（旗舰开炮）"},
	&"sea_hit": {"layers": [[&"combat_hit", -8.0]], "where": "Cannonball 命中"},
	&"sea_board": {"layers": [[&"combat_board", -4.0]], "where": "WorldMap._board_enemy（接舷）"},
	&"sea_win": {"layers": [[&"combat_win", -4.0]], "where": "WorldMap._battle_exit（胜）"},
	&"sea_lose": {"layers": [[&"combat_lose", -4.0]], "where": "WorldMap._battle_exit（败）"},
	&"sea_flee": {"layers": [[&"combat_flee", -4.0]], "where": "WorldMap._battle_exit（两散 / 撤离）"},
}


## 放一个挂点的声（表里没有这个挂点就不响）。host 是发声那一处的节点，AudioHooks 拿它找场景树根。
static func play(host: Node, hook: StringName) -> void:
	var row: Dictionary = HOOKS.get(hook, {})
	var opts := {"hook": hook}
	for k in ["gap_key", "group"]:
		if row.has(k):
			opts[k] = row[k]
	for layer in row.get("layers", []):
		_AUDIO.play_cue(host, layer[0], float(layer[1]), opts)


## 收战那一声认哪个挂点：胜 / 败各一样，两散、甩脱放风声。data 是 battle_finished 的那份。
## 逃没逃掉（flee 而 flee_ok 不真：B 键弃战掷输、我方溃逃没跑掉）海图照败局记——船挨一顿、舱货被夺，札记写「未能甩脱」，
## 放败局那一声；判法与 SeaChart._on_battle_result 同一口径（data.get("flee_ok", false)）。原先这一支照放撤离的风声。
static func result_hook(outcome: String, data := {}) -> StringName:
	if outcome == "win":
		return &"sea_win"
	if outcome == "lose" or (outcome == "flee" and not bool(data.get("flee_ok", false))):
		return &"sea_lose"
	return &"sea_flee"


## 收战：WorldMap._battle_exit 调
static func battle_result(host: Node, outcome: String, data := {}) -> void:
	play(host, result_hook(outcome, data))
