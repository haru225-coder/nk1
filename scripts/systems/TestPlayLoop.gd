class_name TestPlayLoop extends RefCounted

# C-4.1: 玩家行为脚本测试 (Play Loop Script)
# 用于模拟真实玩家的“低吸高抛”套利循环

static func simulate_player_trade_loop() -> void:
	print("=== [C-4.1] 玩家真实游玩模拟开始 ===")
	
	# 1. 玩家进入泉州，查看物价
	print("\n[第1天] 玩家到达泉州港，查看市场行情...")
	var snapshot1 = EconomySystem.get_market_snapshot("quanzhou")
	var price_day1 = EconomySystem.get_price("quanzhou", "fujian_porcelain")
	print("-> 福建瓷当前单价: ", price_day1)
	
	# 2. 觉得便宜，重仓买入 10 份
	print("\n[第1天] 玩家觉得有利可图，买入 10 份福建瓷...")
	var buy_intent = Intent.new("market_buy", "player", "market", {"good_id": "fujian_porcelain", "amount": 10}, {"port_id": "quanzhou"})
	TradeHandler.execute(buy_intent)
	print("-> 玩家离开市场，出海游荡。")
	
	# 3. 时间流逝，突然爆发海盗事件
	print("\n[第5天] 世界局势突变！海盗封锁了泉州...")
	var pirate_event = PirateAttackEvent.new("quanzhou", 7)
	WorldEventTracker.add_event(pirate_event)
	
	# 4. 玩家敏锐地嗅到商机，掉头回港查看物价
	print("\n[第6天] 玩家听闻海盗封锁，带着存货杀回泉州...")
	var price_day6 = EconomySystem.get_price("quanzhou", "fujian_porcelain")
	print("-> 福建瓷当前暴涨至单价: ", price_day6)
	
	# 5. 趁火打劫，高位抛售
	print("\n[第6天] 玩家在黑市高价抛售 10 份福建瓷...")
	var sell_intent = Intent.new("market_sell", "player", "market", {"good_id": "fujian_porcelain", "amount": 10}, {"port_id": "quanzhou"})
	TradeHandler.execute(sell_intent)
	
	# 6. 核算利润
	var profit = (price_day6 - price_day1) * 10
	print("\n[结算] 玩家这波倒买倒卖净赚: ", profit, " 钱！")
	print("=== [C-4.1] 游玩模拟结束 ===")
