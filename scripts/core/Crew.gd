extends Node
## 船上职事。每种职事至多雇一人，加成不叠加——避免堆人堆到数值失控。
## 各加成的实际接入点：
##   火长 → Fleet.fleet_speed()
##   舵工 → Voyage.wind_factor() 的逆风下限
##   总管 → Fleet._apply_perishable() 与 Voyage._storm_event() 的货损
##   杂事 → Economy 的抽解与牙人佣金
##   通事 → Economy 在异国港口的价差
##   医人 → Fleet.on_day_passed() 的减员与士气

## {role_id: candidate_dict}
var hired: Dictionary = {}

## 连续欠饷的月数。久之则求去。
var unpaid_months: int = 0

## 非宋土港口。通事在此处才真正派上用场。
const FOREIGN_PORTS := ["hakata", "kagoshima", "jeju", "champa"]

## 入伙钱 = 月俸 × 此倍数
const SIGNING_MULTIPLIER := 2


# ── 名册 ──────────────────────────────────────────────

func role_def(role_id: String) -> Dictionary:
	for r in GameManager.crew_data.get("roles", []):
		if r.get("id") == role_id:
			return r
	return {}


func candidate_def(cand_id: String) -> Dictionary:
	for c in GameManager.crew_data.get("candidates", []):
		if c.get("id") == cand_id:
			return c
	return {}


## 某港此刻可雇之人：本港出身、章节已到、该职事尚缺、且不是已雇之人
func candidates_at(port_id: String) -> Array:
	var out := []
	for c in GameManager.crew_data.get("candidates", []):
		if c.get("port", "") != port_id:
			continue
		if not GameState.is_chapter_reached(c.get("unlock", "ch1")):
			continue
		if hired.has(c.get("role", "")):
			continue
		out.append(c)
	return out


func signing_fee(cand_id: String) -> int:
	return int(candidate_def(cand_id).get("wage", 0)) * SIGNING_MULTIPLIER


## 返回 {ok, msg}
func hire(cand_id: String) -> Dictionary:
	var c := candidate_def(cand_id)
	if c.is_empty():
		return {"ok": false, "msg": "查无此人。"}
	var role_id: String = c.get("role", "")
	if hired.has(role_id):
		return {"ok": false, "msg": "船上已有%s，一职不容二人。" % role_def(role_id).get("name", "此职")}
	var fee := signing_fee(cand_id)
	if not GameState.spend_money(fee):
		return {"ok": false, "msg": "入伙钱要 %d，你拿不出。" % fee}
	hired[role_id] = c
	return {"ok": true, "msg": "%s 入伙，付入伙钱 %d，月俸 %d。" % [
		c.get("name", "此人"), fee, c.get("wage", 0),
	]}


func dismiss(role_id: String) -> Dictionary:
	if not hired.has(role_id):
		return {"ok": false, "msg": ""}
	var name: String = hired[role_id].get("name", "此人")
	hired.erase(role_id)
	return {"ok": true, "msg": "%s 卷了铺盖上岸。" % name}


## 未雇为 0
func level_of(role_id: String) -> int:
	return int(hired.get(role_id, {}).get("level", 0))


func roster() -> Array:
	var out := []
	for r in hired.keys():
		out.append(hired[r])
	return out


# ── 加成 ──────────────────────────────────────────────

## 火长：日速倍率
func speed_factor() -> float:
	return 1.0 + 0.06 * level_of("huozhang")


## 舵工：逆风时的日速下限。无舵工为 0.40，三级可提到 0.55
func wind_floor() -> float:
	return 0.40 + 0.05 * level_of("duogong")


## 总管：货损倍率，越低越好
func cargo_loss_factor() -> float:
	return maxf(0.0, 1.0 - 0.17 * level_of("zongguan"))


## 杂事：抽解与佣金的倍率，越低越好
func trade_cost_factor() -> float:
	return maxf(0.0, 1.0 - 0.12 * level_of("zashi"))


## 通事：在异国港口的价差改善（买价降、卖价升的比例）
func interpreter_edge(port_id: String) -> float:
	if not (port_id in FOREIGN_PORTS):
		return 0.0
	return 0.07 * level_of("tongshi")


## 医人：断粮减员概率的倍率，越低越好
func crew_loss_factor() -> float:
	return maxf(0.0, 1.0 - 0.23 * level_of("yiren"))


## 医人：每日额外士气回复
func morale_bonus() -> int:
	return level_of("yiren")


# ── 月俸 ──────────────────────────────────────────────

func monthly_wage() -> int:
	var total := 0
	for r in hired.keys():
		total += int(hired[r].get("wage", 0))
	return total


## 每月结算。付不出则士气下降，连欠三月有人求去。返回描述文本（无事返回空串）
func pay_wages() -> String:
	var due := monthly_wage()
	if due <= 0:
		return ""
	if GameState.spend_money(due):
		unpaid_months = 0
		return ""

	unpaid_months += 1
	Fleet.morale = maxi(0, Fleet.morale - 8)

	if unpaid_months >= 3 and not hired.is_empty():
		# 欠饷三月，俸最高者先走
		var quitter := ""
		var top := -1
		for r in hired.keys():
			var w: int = int(hired[r].get("wage", 0))
			if w > top:
				top = w
				quitter = r
		var who: String = hired[quitter].get("name", "有人")
		hired.erase(quitter)
		unpaid_months = 0
		return "【欠饷】已拖欠三月工食，%s 不告而别。" % who

	return "【欠饷】这月的工食 %d 钱发不出，船上人心浮动。" % due


# ── 存档 ──────────────────────────────────────────────

func to_dict() -> Dictionary:
	return {"hired": hired, "unpaid_months": unpaid_months}


func from_dict(d: Dictionary) -> void:
	hired = d.get("hired", {})
	unpaid_months = d.get("unpaid_months", 0)
