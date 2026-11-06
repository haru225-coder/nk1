class_name PortBeats
extends RefCounted
## 港口节拍（拍板清单 E-10 / G1014，lane w20-c2）：把 data/port_beats.json 接回运行时。
## 同一港的拍按 order 排成链。due 找第一个没记名、requires 又都满足的拍，抵达时演它。
## Main._on_enter_port 负责演出并记名，写入 GameState.beats_seen 后入存档；一次抵达只演一拍。
## 玩家也可能从上一幕的选项或序章直接点进节拍幕。这种走法同样记名
## （is_beat_scene，lane w53-6），以后不重演。stop_before 给出链上的下一拍，
## 玩家可从上一幕接着点，requires.seen 用来接上前面那一拍。
## 有的开场拍不单独演，内容已经放在另一幕里。decompose_to 记下那一幕，记名时认它，不再演一遍。
## 目前有两个缺省对应：流求 ryukyu_bay（琉球巡礼也在那一幕）和博多 hakata_ledger（博多旧账）。
## nk1/port_beats_runtime 是 ProjectSettings 里的开关，默认开。关掉后不演也不记名，
## GameManager 不读 port_beats.json，这里拿到空表，老档仍按老办法走。
## 解析期不能在这里写 autoload 名，class_name 登记得更早。调用方在 init 时传入
## GameManager 的 port_beats_data.get("beats")，这里不再回头读取 GameManager。

## 关断开关的项目设置键（ProjectSettings.get_setting 读，缺省 true=接回）
const SETTING := "nk1/port_beats_runtime"
## 开场戏分解位缺省（数据可覆写 decompose_to）
const DECOMPOSE := {"ryukyu": "ryukyu_bay", "hakata": "hakata_ledger"}
## 入口拍的 requires 为空，玩家第一次到港就能演。它和 GameState.last_port 的开局港缺省配合，
## 保证任一港都有入口。目前是 quanzhou_monk（泉州开局第一拍）和 ryukyu_bay（流求开场戏代拍）。
## tools/data_family.json 的 families 根靠它检查可达性，改名要同步。序章书斋戏 start 开局已经演过，
## seed 里先记上；兴化链只有这一条，见 DEFAULT_SEED。
const START_ENTRIES := ["quanzhou_monk", "ryukyu_bay"]
## 抵达后接演的港：泉州主链，以及章二后的庆元、博多、占城三条委托线。
## 流求、兴化不接。首次到港仍要在港页记 visited_ports，不能因为演了剧情幕就算到港。
const QUEST_PORTS := ["quanzhou", "mingzhou", "hakata", "champa"]
## 三条委托线的尾拍：硫黄、博多短札、占城沉香。首拍可带章序、旧账旗、短札或记港数条件，
## 运行时据此接演。从尾拍沿 requires.seen 能回到链头，data_family 也靠它检查可达性。
const QUEST_TAIL_ENTRIES := ["quest_sulfur_return", "quest_hakata_return", "quest_champa_return"]
## 新档先记下序章沿途已经演过的戏。兴化链只记 start；开关关闭时不 seed，老档照旧。
const DEFAULT_SEED := ["start"]

var _beats: Array = []


## GameManager 传入 port_beats_data.get("beats")；传空表就不处理任何节拍。
func init(raw: Array) -> void:
	_beats = []
	for b in raw:
		if typeof(b) != TYPE_DICTIONARY:
			continue
		var entry := str(b.get("entry", ""))
		var port := str(b.get("port", ""))
		if entry == "" or port == "":
			continue
		var beat: Dictionary = b.duplicate(true)
		# 开场戏已经包含 requires 为空的开场拍。数据没写 decompose_to 时按 DECOMPOSE 补，
		# 写了就保留。目前用于流求 ryukyu_bay 和博多 hakata_ledger。
		var req0 = beat.get("requires", {})
		if not beat.has("decompose_to") and DECOMPOSE.has(port) and (typeof(req0) != TYPE_DICTIONARY or (req0 as Dictionary).is_empty()):
			beat["decompose_to"] = str(DECOMPOSE[port])
		_beats.append(beat)


## 开关（默认开）。项目设置里没有这个键就是开。
static func enabled() -> bool:
	return bool(ProjectSettings.get_setting(SETTING, true))

## 取一港的拍，按 order 排序；order 相同时保持登记顺序。
func chain(port_id: String) -> Array:
	var out: Array = []
	for b in _beats:
		if str(b.get("port", "")) != port_id:
			continue
		var at := out.size()
		for i in range(out.size()):
			if int(b.get("order", 0)) < int(out[i].get("order", 0)):
				at = i
				break
		out.insert(at, b)
	return out

## 返回抵达时该演的一拍。已记名的跳过；遇到第一个没记名的，requires 满足就返回它，
## 不满足就返回 {}，不能越过它找后面的拍。全部记名时也返回 {}。
## seen、flags、visited 是字符串表，chapter 是当前章序。调用方先记本港再传 visited，
## 所以 visited_at_least 包含本港：第一次记港算 1，再记一港才算 2。开关关闭时恒返回 {}。
## is_ended 为真也恒返回 {}，依据是 wave22 待定项② 已准的「终局后港口节拍一律不再演」，
## 见 lane w26-k7。原先由 Main._on_enter_port 检查（w25-j2），现在放在这里，免得别的调用路径漏掉。
## 调用方传当前会话的 GameState.is_ended()；探针可直接传 true / false，覆盖四种情况。
func due(port_id: String, seen: Array, flags: Array, visited: Array, chapter: int, is_ended: bool) -> Dictionary:
	if is_ended or not enabled():
		return {}
	for b in chain(port_id):
		if _done(b, seen):
			continue
		if _requirements_met(b, seen, flags, visited, chapter):
			return b
		return {}
	return {}


## 抵达结算：返回 {beat, play, mark}。play=true 由调用方就地演出那一幕，mark=拍 entry；
## play=false 是分解位已代演（seen 已有 decompose_to）——只补一记（mark=分解位），不重复演。
## is_ended: 同 due 的终局守卫（本口薄转 due，改了 due 的守卫行为这里自动跟着收）。
func arrive(port_id: String, seen: Array, flags: Array, visited: Array, chapter: int, is_ended: bool) -> Dictionary:
	var b := due(port_id, seen, flags, visited, chapter, is_ended)
	if b.is_empty():
		return {}
	var decomp := str(b.get("decompose_to", ""))
	if decomp != "" and (decomp in seen):
		return {"beat": b, "play": false, "mark": decomp}
	return {"beat": b, "play": true, "mark": str(b.get("entry", ""))}




## 这一幕是不是某一拍的戏（entry 或分解位）。拍账记的是「这幕演过没有」，不只是抵港演的那一拍：
## Main._load_scene_inner 演到节拍幕就记名（lane w53-6）——序章一路点下来，start 三项同指 monk，各幕选项
## 一路链到章二信再回泉州港；只记抵港那一拍时，首抵泉州又从 monk 起把整段第一章重演一遍。
func is_beat_scene(scene_id: String) -> bool:
	if scene_id == "":
		return false
	for b in _beats:
		if str(b.get("entry", "")) == scene_id or str(b.get("decompose_to", "")) == scene_id:
			return true
	return false


## 各拍 entry（登记序、去重）：Main 给没有拍账的老档补账时逐针问「那一幕点过没有」
func entries() -> PackedStringArray:
	var out := PackedStringArray()
	for b in _beats:
		var e := str(b.get("entry", ""))
		if e != "" and not out.has(e):
			out.append(e)
	return out


## 这拍记过名（entry 或分解位在 seen 里）
func _done(b: Dictionary, seen: Array) -> bool:
	var entry := str(b.get("entry", ""))
	if entry in seen:
		return true
	var decomp := str(b.get("decompose_to", ""))
	return decomp != "" and decomp in seen


func _requirements_met(b: Dictionary, seen: Array, flags: Array, visited: Array, chapter: int) -> bool:
	var req = b.get("requires", {})
	if typeof(req) != TYPE_DICTIONARY:
		return true
	for e in (req as Dictionary).get("seen", []):
		if not (str(e) in seen):
			return false
	for f in (req as Dictionary).get("has_flag", []):
		if not (str(f) in flags):
			return false
	for p in (req as Dictionary).get("visited", []):
		if not (str(p) in visited):
			return false
	# 记港数下限（visited 含本港）：新局首记泉州为 1，委托头针须候次回再记一港，不抢首次入港的港页
	if int((req as Dictionary).get("visited_at_least", 0)) > visited.size():
		return false
	if int((req as Dictionary).get("chapter_at_least", 0)) > chapter:
		return false
	var at_most := int((req as Dictionary).get("chapter_at_most", 0))
	if at_most > 0 and chapter > at_most:
		return false
	return true
