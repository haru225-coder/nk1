extends Node
## 船上职事。每种职事至多雇一人，加成不叠加——避免堆人堆到数值失控。
## 各加成的实际接入点：
##   火长 → Fleet.fleet_speed()
##   舵工 → Voyage.wind_factor() 的逆风下限
##   总管 → Fleet._apply_perishable() 与 Voyage._storm_event() 的货损
##   杂事 → Economy 的抽解与牙人佣金
##   通事 → Economy 在异国港口的价差
##   医人 → Fleet.on_day_passed() 的减员与士气

## {role_id: 候选 id}——只记名册 id；名字、月俸、品级一律按 id 回查 crew.json（candidate_def）。
## 名册是唯一的数，存档不再另存一份快照（否则改名册后旧档同一人两套数，DESIGN1-8②）。
## 查不到 id 的按未雇对待，不回读任何档内快照（v4 起档里也没有快照可回读）。
## v3 及更早的档这一格还是整条快照，由 SaveLoad 迁移链收成 id（docs/存档迁移矩阵.md v3→v4）。
var hired: Dictionary = {}

## 连续欠饷的月数。久之则求去。名册空了归零（hire / pay_wages），不留给下一拨人。
var unpaid_months: int = 0

## 史实辞船下船的人：{候选 id: {role, name, when「景炎元年十月」}}。入存档；旧档没有这一格按空读。
var departed: Dictionary = {}

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
		if not GameState.flag_requirement_met(c) or not hireable_by_history(c):
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
		return {"ok": false, "msg": "名册上查无此人。"}
	var role_id: String = c.get("role", "")
	if hired.has(role_id):
		return {"ok": false, "msg": "船上已有%s。一职只容一人。" % role_def(role_id).get("name", "此职")}
	var fee := signing_fee(cand_id)
	if not GameState.spend_money(fee):
		return {"ok": false, "msg": "入伙钱 %d，囊中不足。" % fee}
	# 船上原先一个职事也没有：新来的人不背前一拨人的欠饷月数（欠两月辞光、当月重雇，头一回欠饷他就「欠满三月」走人）
	if hired.is_empty():
		unpaid_months = 0
	hired[role_id] = str(c.get("id", ""))
	GameState.record_crew(cand_id)
	return {"ok": true, "msg": "%s 入伙。付入伙钱 %d，月俸 %d。" % [
		c.get("name", "此人"), fee, c.get("wage", 0),
	]}


func dismiss(role_id: String) -> Dictionary:
	if not hired.has(role_id):
		return {"ok": false, "msg": ""}
	var name: String = str(candidate_def(str(hired[role_id])).get("name", "此人"))
	hired.erase(role_id)
	return {"ok": true, "msg": "%s 辞退，背铺盖上岸。" % name}


## 未雇（或名册里查无此人）为 0
func level_of(role_id: String) -> int:
	var cand_id := str(hired.get(role_id, ""))
	if cand_id == "":
		return 0
	return int(candidate_def(cand_id).get("level", 0))


## 职事品级。数据里只有 1、2、3。酒馆账条和海图旁注共用这三字。
func rank_word(n: int) -> String:
	if n >= 3:
		return "老练"
	if n == 2:
		return "谙熟"
	return "初习"


## 在船者的名册条目（回查 crew.json）；名册查不到的 id 不进册
func roster() -> Array:
	var out := []
	for r in hired.keys():
		var c := candidate_def(str(hired[r]))
		if not c.is_empty():
			out.append(c)
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
		total += int(candidate_def(str(hired[r])).get("wage", 0))
	return total


## 每月结算。付不出则士气下降，连欠三月有人求去。返回描述文本（无事返回空串）
## 连欠的月数记的是船上这拨人的：名册空了（辞光、史实辞船走光、跳年散尽）就无从欠起，月结时归零。
func pay_wages() -> String:
	var due := monthly_wage()
	if due <= 0:
		unpaid_months = 0
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
			var w: int = int(candidate_def(str(hired[r])).get("wage", 0))
			if w > top:
				top = w
				quitter = r
		var who: String = str(candidate_def(str(hired[quitter])).get("name", "有人"))
		hired.erase(quitter)
		unpaid_months = 0
		return "【欠饷】工食欠满三月，%s 不告而去。" % who

	return "【欠饷】本月工食 %d 未发。船上人心浮动。" % due


# ── 史实辞船 ──────────────────────────────────────────

## crew.json 候选可带 leave_from（"YYYY-MM"，与 news.json 的 date 同口径；verify_economy 守格式）和 leave_note：
## 离辞船月不足 HISTORY_HIRE_LEAD 个月就不再候雇；到了 leave_from 那个月，已在船的月初下船，crew_history 照留（守城认人靠它）。
## 现在只有林华：景炎元年十月去兴化投军，腊月守城时就是那位部将。不让他下船，他就同时是你的舵工和城头的部将。

## 人要走了不再找新东家，也免得雇进来一个月就走、白付入伙钱。
## 取 2：林华候雇到 1276-08 为止（离 1276-10 还有两个月），与草案的候雇窗口同止。
const HISTORY_HIRE_LEAD := 2


## "YYYY-MM" → 月序（年×12＋月−1）；没写或写得不对返回 -1，当作没有史实辞船
func _month_seq(ym: String) -> int:
	var p := ym.split("-")
	if p.size() != 2 or not p[0].is_valid_int() or not p[1].is_valid_int():
		return -1
	return int(p[0]) * 12 + int(p[1]) - 1


## 已到辞船那个月
func left_by_history(c: Dictionary) -> bool:
	var at := _month_seq(str(c.get("leave_from", "")))
	return at >= 0 and Calendar.year * 12 + Calendar.month - 1 >= at


## 还能候雇：没有 leave_from，或离辞船月至少还有 HISTORY_HIRE_LEAD 个月
func hireable_by_history(c: Dictionary) -> bool:
	var at := _month_seq(str(c.get("leave_from", "")))
	return at < 0 or Calendar.year * 12 + Calendar.month - 1 <= at - HISTORY_HIRE_LEAD


## 酒馆候选卡品级后那一截「只跟到九月」：带 leave_from 的人离辞船月不到一年、又还在候雇窗里时，写明他在船的末一月——
## 林华候雇到 1276-08，八月底雇来只跟九月一个整月，十月初一就下船；卡上不写，玩家照常付了入伙钱才发现人要走。
## 月名借 Calendar 自己的写法（临时拨到那一月、算完拨回，同 Main._siege_fall_point），跨年写「明年」；不该写时返回空串。
func leave_hint(c: Dictionary) -> String:
	var at := _month_seq(str(c.get("leave_from", "")))
	var now := Calendar.year * 12 + Calendar.month - 1
	if at < 0 or at - now > 12 or not hireable_by_history(c):
		return ""
	var last := at - 1
	var keep: Dictionary = Calendar.to_dict()
	Calendar.from_dict({"year": floori(last / 12.0), "month": last % 12 + 1, "day": 1})
	var month_name := Calendar.get_month_name()
	Calendar.from_dict(keep)
	return "只跟到%s%s" % ["明年" if floori(last / 12.0) > Calendar.year else "", month_name]


## 月初由 GameManager.advance_days 调用，排在发饷之前，到月下船的人不再扣当月俸。
## 返回下船的候选（crew.json 条目）；通告由 GameManager._settle_history 排在新闻之后发，跳年时另进摘要。
## 按候选 id 回查 crew.json 判日子，不看存档里的快照，旧档里已雇的人也照样下船。
## （hired 本就只存 id 后，这里只是把回查挪进 candidate_def，口径不变。）
## 下船的人记进 departed（船籍簿职事栏留一行淡字「舵工　林华已于景炎元年十月辞船」，辞船通告被别的行压住也看得到）。
func history_leave() -> Array:
	var out := []
	for r in hired.keys().duplicate():
		var c := candidate_def(str(hired[r]))
		if left_by_history(c):
			hired.erase(r)
			out.append(c)
			departed[str(c.get("id", ""))] = {
				"role": str(c.get("role", r)),
				"name": str(c.get("name", "")),
				"when": Calendar.get_era_year_string() + Calendar.get_month_name(),
			}
	return out


## 船籍簿职事栏的辞船淡字：「舵工　林华已于景炎元年十月辞船」，按辞船先后
func departed_lines() -> PackedStringArray:
	var out := PackedStringArray()
	for cid in departed.keys():
		var e = departed[cid]
		if typeof(e) != TYPE_DICTIONARY:
			continue
		out.append("%s　%s已于%s辞船" % [
			role_def(str(e.get("role", ""))).get("name", "职事"), str(e.get("name", "")), str(e.get("when", "")),
		])
	return out


## 辞船那一句（不带【辞船】）：月初通告和跳年摘要共用
func leave_note(c: Dictionary) -> String:
	return str(c.get("leave_note", "%s辞了船。" % c.get("name", "有人")))


# ── 存档 ──────────────────────────────────────────────

func to_dict() -> Dictionary:
	return {"hired": hired, "unpaid_months": unpaid_months, "departed": departed}


func from_dict(d: Dictionary) -> void:
	hired = d.get("hired", {})
	unpaid_months = d.get("unpaid_months", 0)
	var dp = d.get("departed", {})
	departed = dp if typeof(dp) == TYPE_DICTIONARY else {}
