class_name PortBeats
extends RefCounted
## 港口节拍（拍板清单 E-10 / G1014，lane w20-c2）：data/port_beats.json 接回运行时。
## 是一笔演出账：一港各拍按 order 排成链，链上第一针没记名且 requires 全够的拍 = 抵达时该演（due）；
## Main._on_enter_port 抵达时演那一幕、记名（GameState.beats_seen 入存档），一次抵达只演一拍，
## stop_before 是链上的下一拍，留给玩家照戏往下点（requires.seen 就是照着上一拍的戏点出那一幕）。
## decompose_to：开场拍没有条件、它的戏在别一幕里演过了的，记名按那一幕认、不重复演出。
## 现数据里的三处：流求 ryukyu_bay（琉球巡礼在那一幕里）与博多 hakata_ledger（博多旧账）。
## 关断开关 nk1/port_beats_runtime（ProjectSettings，默认开）：关掉即回旧行为——节拍一步不动、不记名，
## GameManager 也不读 port_beats.json（账口空表，老档老行为）。
## 本件在解析期不写 autoload 名（class_name 登记早于 autoload）：数据由调用方把 GameManager 的
## port_beats_data.get("beats") 喂进来（init），判定不回头读 GameManager。

## 关断开关的项目设置键（ProjectSettings.get_setting 读，缺省 true=接回）
const SETTING := "nk1/port_beats_runtime"
## 开场戏分解位缺省（数据可覆写 decompose_to）
const DECOMPOSE := {"ryukyu": "ryukyu_bay", "hakata": "hakata_ledger"}
## 节拍链的入口针（requires 全空、玩家头一回踏上这港就上演的那拍）：与 GameState.last_port 缺省（开局港）
## 互补任一港的入口针（现数据：quanzhou_monk 开局港泉州的第一针 / ryukyu_bay 流求开场戏那一幕代拍）。
## tools/data_family.json 的 families 根按这份常量锚可达性（改名须两处同步）。序章那场书斋戏（start）= 开
## 局就会演的旧戏，拍账上 seed 记着（杏化链只有它一针，见 DEFAULT_SEED）。
const START_ENTRIES := ["quanzhou_monk", "ryukyu_bay"]
## 拍账 seed：新档从这份起照（序章沿途已演的戏，Xinghua 链 start 一针记账；开关关掉不 seed = 留档老档老行为）
const DEFAULT_SEED := ["start"]

var _beats: Array = []


## 数据喂进来（GameManager 把 port_beats_data.get("beats") 整表交出）。空表 = 节奏全停。
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
		# 开场拍（requires 全空）在这港的开场戏里就有（数据里没有 decompose_to 时按港名缺省认；有就照数据）；
		# 现数据三处：流求 ryukyu_bay、博多 hakata_ledger
		var req0 = beat.get("requires", {})
		if not beat.has("decompose_to") and DECOMPOSE.has(port) and (typeof(req0) != TYPE_DICTIONARY or (req0 as Dictionary).is_empty()):
			beat["decompose_to"] = str(DECOMPOSE[port])
		_beats.append(beat)


## 开关（默认开）。项目设置里没有这个键就是开。
static func enabled() -> bool:
	return bool(ProjectSettings.get_setting(SETTING, true))


## 该港按 order 排好的链（同 order 保登记序）
func chain(port_id: String) -> Array:
	var out: Array = []
	for b in _beats:
		if str(b.get("port", "")) == port_id:
			out.append(b)
	out.sort_custom(func(a, b): return int(a.get("order", 0)) < int(b.get("order", 0)))
	return out


## 抵达时该演的拍：链上第一针没记名（entry / 分解位都不在 seen）且 requires 全够的；
## 第一针没记名但 requires 不够 = 链停在这针等条件（{}）；每一拍都记了名也 {}。seen / flags / visited
## 是字符串表，chapter 是当前章序。关断开关关掉恒 {}。
func due(port_id: String, seen: Array, flags: Array, visited: Array, chapter: int) -> Dictionary:
	if not enabled():
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
func arrive(port_id: String, seen: Array, flags: Array, visited: Array, chapter: int) -> Dictionary:
	var b := due(port_id, seen, flags, visited, chapter)
	if b.is_empty():
		return {}
	var decomp := str(b.get("decompose_to", ""))
	if decomp != "" and (decomp in seen):
		return {"beat": b, "play": false, "mark": decomp}
	return {"beat": b, "play": true, "mark": str(b.get("entry", ""))}




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
	if int((req as Dictionary).get("chapter_at_least", 0)) > chapter:
		return false
	return true
