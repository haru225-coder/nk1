extends SceneTree
## Lane w23-a8（P8 · V0928-1② 取证件）：「被围港被开成委办目的地」复现探针。
##   现态：_contract_destinations（scripts/GameState.gd :891）只排「未解锁 / depth<=0 / 非消费方 / 不收此货」，
##   不看战况——本探针在 5 张真战况表（兴化 1276-11 besieged、福州 1276-10、广州 1276-11、
##   博多唐房 1274-10 closed、萨摩 1274-10 closed）下把所有开单港 × 全货的目的地候选集与月正式单全打出来，
##   再用「探针侧 A+ 豁免镜像」（besieged / closed 不当目的地，与清单 A+ 案同口径；fallen 不动）重算对照。
##   不改任何游戏码；A+ 列只在探针里算，供策划看「动这一处会改掉哪些单」。
## 用法：godot --headless --path . -s res://tools/qa_contract_destinations_probe.gd
## 输出末行 A8_PROBE_DEST fate=<发生|不发生|条件不足未复现> conclusive=<yes|no>（本探针纯取证，恒 exit 0）。

const CASES: Array = [
	{"ym": [1276, 11], "port": "xinghua", "expect": "besieged", "label": "兴化 1276-11（清单点名围城月）"},
	{"ym": [1276, 10], "port": "fuzhou", "expect": "besieged", "label": "福州 1276-10"},
	{"ym": [1276, 11], "port": "guangzhou", "expect": "besieged", "label": "广州 1276-11"},
	{"ym": [1274, 10], "port": "hakata", "expect": "closed", "label": "博多唐房 1274-10（文永之役封港）"},
	{"ym": [1274, 10], "port": "kagoshima", "expect": "closed", "label": "萨摩 1274-10"},
]

var gs: Node
var gm: Node
var cal: Node
var eco: Node
var _rates0: Dictionary = {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var cine_src: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine_src != null:
		cine_src.set("auto_opening", false)
		cine_src.set("opening_seen", true)
	gs = root.get_node("/root/GameState")
	gm = root.get_node("/root/GameManager")
	cal = root.get_node("/root/Calendar")
	eco = root.get_node("/root/Economy")
	_rates0 = eco.rates.duplicate(true)

	print("A8_PROBE_BEGIN 基 main c0e27b6 · 只取证不改码")
	var seen := 0
	var hit_ports: Array = []
	for c in CASES:
		var r: Dictionary = _case(c)
		if bool(r.get("seen", false)):
			seen += 1
			if not (r.get("photo_ports", []) as Array).is_empty():
				for p in r["photo_ports"]:
					if not hit_ports.has(p):
						hit_ports.append(p)
				print("  ⊙ %s 被开成目的港（签发港：%s）" % [r["port"], ", ".join(r["photo_ports"])])
	print("── 当月正式单开去围 / 封港的（目的港 ← 签发港）= %d 处" % hit_ports.size())
	if hit_ports.is_empty():
		if seen == 0:
			print("A8_PROBE_DEST fate=条件不足未复现 conclusive=yes")
		else:
			print("A8_PROBE_DEST fate=不发生 conclusive=yes")
	else:
		print("A8_PROBE_DEST fate=发生 conclusive=yes")
	quit(0)


## 探针侧 A+ 豁免镜像：不动 fallen（照现态只加 besieged / closed 两档），与清单 A+ 案「被围的港不再开新委办」同口径。
func _destinations_aplus(port_id: String, good_id: String) -> Array:
	var dests: Array = []
	for p: Dictionary in gm.unlocked_ports():
		var pid: String = str(p.get("id", ""))
		if pid == port_id or int(p.get("depth", 0)) <= 0:
			continue
		if eco.war_status(pid) in ["besieged", "closed"]:
			continue
		if str(eco.get_role(pid, good_id)) != "consumer":
			continue
		if not eco.is_traded(pid, good_id):
			continue
		dests.append(pid)
	dests.sort()
	return dests


func _reset_state(ym: Array, from_port: String) -> void:
	gs.from_dict({})
	cal.from_dict({"year": int(ym[0]), "month": int(ym[1]), "day": 3})
	eco.rates = _rates0.duplicate(true)
	gs.chapter = 5
	gs.last_port = from_port
	gs.contract = {}
	gs.contract_ban = {}


func _case(c: Dictionary) -> Dictionary:
	var port := str(c["port"])
	var ym: Array = c["ym"]
	var ym_s := "%04d-%02d" % [int(ym[0]), int(ym[1])]
	print("== %s（%s，期望战况 %s）==" % [c["label"], ym_s, c["expect"]])
	_reset_state(ym, "quanzhou")
	var status := str(eco.war_status(port))
	print("  war_status(%s) = %s　is_market_open = %s" % [port, status, eco.is_market_open(port)])
	if status != str(c["expect"]):
		print("  !! 战况表与取证前提不符，此格跳过")
		return {"seen": false, "port": port}

	var candidates: Array = []
	var seen := false
	for sp: Dictionary in gm.unlocked_ports():
		var spid := str(sp.get("id", ""))
		if eco.war_status(spid) in ["besieged", "closed"]:
			continue  # 本港当月牙行闭门，不走到开单 UI（Main.gd:1219 MARKET_SIDE_DOOR 闸），跳过不算「条件不足」
		_reset_state(ym, spid)
		var goods: Array = eco.goods_at(spid)
		for g0 in goods:
			var gid := str(g0)
			var d0: Array = gs._contract_destinations(spid, gid)
			var d1: Array = _destinations_aplus(spid, gid)
			if d0.has(port):
				seen = true
				var d1_mark: Array = []
				for x in d1:
					d1_mark.append("※" + x if x == port else x)
				print("  [候选] %s ◇ %s" % [spid, gid])
				print("          现态 %s %s" % [_fmt_dests(d0, port), "※本格" if port == spid else ""])
				print("          A+免 %s" % _fmt_dests(d1_mark, port))
		var offer: Dictionary = gs.contract_offer(spid)
		if offer.is_empty():
			continue
		var od := str(offer.get("dest", ""))
		var og := str(offer.get("good_id", ""))
		var wstatus := str(eco.war_status(od))
		print("  [正式单] %s → %s ◇ %s （目的港战况 %s）" % [
			spid, od, og, wstatus if wstatus != "loyal" else "loyal・无事"])
		if od == port:
			var days := int(offer.get("voyage_days", 0))
			print("    ※※ 被开成正式目的地：%s ◇ %s ×%d 限 %d 日（voyage_days=%d）※※" % [
				port, og, int(offer.get("qty", 0)), int(offer.get("deadline_days", 0)), days])
			candidates.append(spid)  # contract_offer 已保证 0 < days <= 897 才算得出这单
		if not eco.war_status(od) in ["loyal", "fallen"]:
			print("    ※ 目的港战况非无事：%s = %s" % [od, eco.war_status(od)])
	return {"seen": seen, "port": port, "photo_ports": candidates}


func _fmt_dests(dests: Array, mark: String) -> String:
	if dests.is_empty():
		return "（空）"
	var parts: Array = []
	for d0 in dests:
		var d := str(d0)
		var w := str(eco.war_status(d))
		parts.append("%s[%s]" % [d, w] if d == mark else d)
	return ", ".join(parts)
