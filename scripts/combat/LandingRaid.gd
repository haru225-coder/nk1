class_name LandingRaid
## 小规模登陆战（战斗系统方案 §十 第六期「小规模登陆战（复用陆战骰子）」，lane w53-p6-landing）。
##
## 为什么这样选：海战赢了、敌是海寇、船就停在宋土沿海——战后多一行「登岸剿寨」。海
## 寇寨不是城：不攻城、不占地方，就是把岸上那座寨烧了、把窝里的东西搬回舱里（方案 §七
## 「不做大规模攻城战术层」、附 c3「不采纳攻打占城」）。入口挂在 w53-p4-after 那张战后
## 收拾小卡上（SeaChart._on_battle_result 里挂卡前追加一行），不另起一摊。
##
## 骰子照抄守城那一路：SiegeMelee.clash —— 我方战力对一枚敌军骰，战力不低于敌军即胜。
## 数值与守城那一路同源不同参：簇 = 能下船的人（水手数封顶），乘将领系数（Fleet.captain_power）
## 与船上士气系数（Fleet.morale_factor），与守城劫粮道 SiegeMelee.raid_power 同一算法，
## 只是这里按登岸人数的上限另给一档敌军骰。改守城那一路的数不动本件（本件只调 clash）。
##
## 结果只落在现有账上：钱（GameState.add_money）、货（Fleet.add_cargo，寨里的粮盐搬进舱）、
## 名声（走 add_fame）、人手折损（Fleet.lose_crew_random）、士气（Fleet.morale）。不加新账本、
## 不加存档字段（一切都当作当场两讫，与 w53-p4-after 的赎金同一退路口径）。
##
## 开关键 landing_raid（CombatSwitches，默认开）：关 = 一行都不挂、什么都不动，逐字回旧。
## 探针 tools/qa_w53_p6_landing_probe.gd；纯静态，不碰 GameState、不建节点，增减由调用方
## （SeaChart）照 layout 出来的数落账。

# ── 寨里的人与骰 ──────────────────────────────────────

## 登岸人数上限：旗舰最大那种福船（大）满编 110 人也只放这么些人下船——船要看守，
## 剩下的守船（寨是海寇的窝，不是空场）。
const LAND_MAX := 30
## 寨中守军骰：下限 / 上限。均值 36.5 —— 与守城那一路同一种接战、同一个战力刻度（人 × 系
## 数），只是寨里的守军比囊山下的元军少得多。五档船的胜率由 qa_w53_p6_landing_probe 第四节量
## （固定种子 1..200，各档 200 次）：十来人的小艍一成上下，满编福船（大）五成多——小艍来剿寨是
## 送人，满编大船也没把握，两头都留了余地，剿寨不是稳赚的买卖。
const RAID_LO := 5.0
const RAID_HI := 68.0

# ── 胜的账 ────────────────────────────────────────────

## 胜：窝里的钱（两档之间掷一次）、名声、士气。均 150 钱。
const WIN_LOOT_LO := 80.0
const WIN_LOOT_HI := 220.0
const WIN_FAME := 3
const WIN_MORALE := 6
## 胜：寨里搬回舱的东西 {货, 件数}——粮（寨子备的）、盐、鹿皮，都是海寇抢来的老实货（不是违禁：
## 搬违禁货回港还要吃查扣，与「剿寨」这个由头不搭；且违禁货卖钱多变摇钱树）。三样面值合计
## 236 钱（米 12×8 + 盐 6×10 + 鹿皮 2×40，各按 base_value），加钱 150 上下，一胜实得约 386。
## 一次剿寨的期望净收益（胜率 × 386 − 败率 × 折人 × 船屋添人价 20）见 qa_w53_p6_landing_probe 第十节，
## 对照 simulate_run 开局一段「小艍半舱最佳前五笔生意净赚 1076～1191」：剿寨远谈不上摇钱树。
## 舱装不下就少装（件数按 Fleet.add_cargo 的自动挑船口径逐件试装，装下的记在 loaded）。
const WIN_CARGO := [
	{"good": "grain", "qty": 12},
	{"good": "sea_salt", "qty": 6},
	{"good": "deer_hide", "qty": 2},
]
## 搬回舱的货按这个价记账（均价成本）——剿来的东西不是买来的，记 0：卖出去全是赚
const WIN_CARGO_COST := 0.0

# ── 败的账 ────────────────────────────────────────────

## 败：下船的人折一成半（船上看守的那部分不动）、士气、名声（去打了一场，总归记一笔）
const LOSE_LOSS_RATE := 0.15
const LOSE_MORALE := -8
const LOSE_FAME := 1

# ── 关态 ──────────────────────────────────────────────

const _Switches := preload("res://scripts/combat/CombatSwitches.gd")
const _Siege := preload("res://scripts/combat/SiegeMelee.gd")

## 宋土沿海的九港（ports.json 里宋境的港，澎湖属泉州晋江县）：船停在这几港外才挂剿寨。
## 异国港（博多唐房 / 萨摩 / 耽罗 / 占城）不算；南岛海道北口（ryukyu）在流求海面北缘，不是宋土，也不算——
## 它不在 Crew.FOREIGN_PORTS 里（通事那一套不当它是异国），所以这里不拿 FOREIGN_PORTS 反推，逐港列明。
const SONG_SHORE := ["xinghua", "xinghua_harbor", "quanzhou", "fuzhou", "zhangzhou", "wenzhou",
	"penghu", "mingzhou", "guangzhou"]


# ── 入口判定 ──────────────────────────────────────────

## 这一仗打的是不是海寇（不是元军哨船、不是拦港的哨船）：pending_battle.source.event == "pirate"。
## 元军哨船（yuan_patrol）与拦港（blockade）都不挂剿寨——那是官军的地盘，打完就走。
static func from_pirate(source: Dictionary) -> bool:
	return str(source.get("event", "")) == "pirate"


## 船现在是不是停在宋土沿海：port 取 SeaChart._sea_here()（船标所在里程处离得最近的港）。
static func on_song_shore(port: String) -> bool:
	return port != "" and port in SONG_SHORE


## 这一仗打完之后挂不挂「登岸剿寨」那一行：开关开 + 胜 + 海寇 + 宋土沿海，四样都要。
static func offerable(outcome: String, source: Dictionary, port: String) -> bool:
	if not _Switches.on("landing_raid"):
		return false
	if outcome != "win":
		return false
	if not from_pirate(source):
		return false
	return on_song_shore(port)


## 能下船的人：水手数封顶 LAND_MAX（船要看守，剩下的人不下船）
static func landing_party(crew: int) -> int:
	return mini(maxi(0, crew), LAND_MAX)


## 下船这队人的战力：人数 × 将领系数 × 船上士气系数（与 SiegeMelee.raid_power 同一算法）
static func raid_power(landing: int, captain: float, morale_factor: float) -> float:
	return float(maxi(0, landing)) * captain * morale_factor


## 敌军骰上下限（探针 / 说明用）
static func raid_range() -> Array:
	return [RAID_LO, RAID_HI]


## 掷一次：返回 SiegeMelee.clash 的账 {enemy, won}。
## 与守城那一路同源——本件不重写掷法，直接借 SiegeMelee.clash（方案 §七「陆战的骰子单独成文件」：
## 囊山设伏和以后的劫粮道、截击用同一种结算）。
static func roll(power: float) -> Dictionary:
	return _Siege.clash(power, RAID_LO, RAID_HI, 1.0)


# ── 战后单子那一行 ────────────────────────────────────

## 挂出来的那一行（形同 AfterAction.choices_for 的各行）：两择——登岸剿寨 / 收队回船。默认收队。
static func choices_for(outcome: String, source: Dictionary, port: String) -> Array:
	if not offerable(outcome, source, port):
		return []
	return [{
		"key": "landing",
		"label": "登岸剿寨（岸上那座海寇窝，放人下船去烧）",
		"options": [
			{"id": "raid", "label": "登岸剿寨", "default": false},
			{"id": "hold", "label": "收队回船", "default": true},
		],
	}]


# ── 落账 ──────────────────────────────────────────────

## 落这一行的账。choice = choices_for 那一行原样 + choice["chosen"]；crew / captain / morale_factor
## 是下船那一刻的实数（调用方现读 Fleet）。
## 返回账 + 注记句：
##   {ok, note, won, enemy, landing, crew_lost, money, fame_gained, morale_delta, cargo:{货:件数}}
## 调用方照 money / fame_gained / morale_delta / crew_lost / cargo 真动全局（Fleet / GameState 在这不动——
## 这里只把数算清，谁调谁落账，探针与 SeaChart 走同一条算路）。
##
## 只掷一次骰（roll），胜负都落同一个 battle 账：harness（SeaChart / 探针）拿 battle.won 分两路落账，
## battle 里 enemy / landing / 三样增减都算好了——不另掷。
static func layout(choice: Dictionary, crew: int, captain: float, morale_factor: float) -> Dictionary:
	var out := {"ok": false, "note": "", "won": false, "enemy": 0.0, "landing": 0,
		"crew_lost": 0, "money": 0, "fame_gained": 0, "morale_delta": 0, "cargo": {}}
	var chosen := str(choice.get("chosen", ""))
	if chosen != "raid":
		out["ok"] = true
		out["note"] = "寨子留在岸上，收队回船。"
		return out
	var landing := landing_party(crew)
	if landing <= 0:
		out["ok"] = true
		out["note"] = "船上没富余的人下船，寨子留在岸上。"
		return out
	out["landing"] = landing
	var roll_res := roll(raid_power(landing, captain, morale_factor))
	out["enemy"] = float(roll_res["enemy"])
	out["won"] = bool(roll_res["won"])
	if out["won"]:
		out["money"] = int(round(randf_range(WIN_LOOT_LO, WIN_LOOT_HI)))
		out["fame_gained"] = WIN_FAME
		out["morale_delta"] = WIN_MORALE
		out["cargo"] = _loot_units()
	else:
		out["crew_lost"] = int(round(float(landing) * LOSE_LOSS_RATE))
		out["fame_gained"] = LOSE_FAME
		out["morale_delta"] = LOSE_MORALE
	out["note"] = note_of(out)
	out["ok"] = true
	return out


## 寨里的东西 {货: 件数}：按 WIN_CARGO 各样的上限原样给（装不下是调用方 add_cargo 的事——
## 舱位不够装不进去的件数就留在岸上，不掉钱不报错，与牙行装不下同一口径）。
static func _loot_units() -> Dictionary:
	var out := {}
	for entry in WIN_CARGO:
		if not entry is Dictionary:
			continue
		var gid := str(entry.get("good", ""))
		var qty := maxi(0, int(entry.get("qty", 0)))
		if gid != "" and qty > 0:
			out[gid] = qty
	return out


## 注记句的头一截（胜 / 败两路；收队、没人下船时就是 layout 写的那一句）。钱数、货、折人、名声由
## 调用方照真落的账接在后面（见 SeaChart._landing_settle）——这里不写数，免得与真落的数两说。
static func note_of(res: Dictionary) -> String:
	if not bool(res.get("ok", false)):
		return ""
	var landing := int(res.get("landing", 0))
	if landing <= 0:
		return str(res.get("note", ""))
	if bool(res.get("won", false)):
		return "寨里的人没撑住，寨子烧了。"
	return "寨门没打开，下船的人退回船上。"


## 胜局真装进舱的货：「米粮 12 件、海盐 6 件、鹿皮 2 件」（调用方接「搬回舱里」；本件不认货名，name_of 给）。
## cargo 形同 layout 的 out.cargo；一件都没装下返回 ""。
static func cargo_note(cargo: Dictionary, name_of: Callable) -> String:
	var parts: PackedStringArray = []
	for gid in cargo.keys():
		var qty := int(cargo[gid])
		if qty <= 0:
			continue
		parts.append("%s %d 件" % [str(name_of.call(str(gid))), qty])
	return "、".join(parts)


## 胜局搬回的货总件数（探针印数 / 期望收益用）
static func cargo_units(cargo: Dictionary) -> int:
	var n := 0
	for gid in cargo.keys():
		n += maxi(0, int(cargo[gid]))
	return n
