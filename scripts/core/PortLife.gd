class_name PortLife
extends RefCounted
## 岸上见闻（lane w54-port，开关 port_life）：寻常港页行首注「今日只开三处。」下面那一行纪实短句。
## 按港所在的一带（宋地、日本、高丽、南洋、海岛）与季风写：东北风（十月至次年二月）南下的船候潮，西南风（五至八月）
## 南边的船进港，其余月份风信未定、多在修船候风。港上战况不太平时（对峙、降元、被围、封港）写战况那一句，压过季风。
## 只写看得见的码头光景，不报数、不劝人买卖。Main._shore_life 取句上屏；本脚本不在解析期写 autoload 名，季风、战况由调用方给。

## 港 id → 一带
const REGION := {
	"quanzhou": "song", "xinghua": "song", "xinghua_harbor": "song", "fuzhou": "song",
	"zhangzhou": "song", "wenzhou": "song", "mingzhou": "song", "guangzhou": "song",
	"hakata": "japan", "kagoshima": "japan",
	"jeju": "korea",
	"champa": "south",
	"ryukyu": "isle", "penghu": "isle",
}

## 一带 → 季风（ne 东北风 / sw 西南风 / calm 风信未定）→ 一句
const LINES := {
	"song": {
		"ne": "北风起了，往南洋去的船在候潮装货。",
		"sw": "南风季，南边来的蕃舶陆续进港。",
		"calm": "风信未定，坞里多是修船补帆的。",
	},
	"japan": {
		"ne": "北风起了，回宋的船在装硫黄与木料。",
		"sw": "南风季，宋船陆续进港，岸上忙着点货。",
		"calm": "风信未定，泊着的宋船都在候风。",
	},
	"korea": {
		"ne": "北风紧，小船都拖上了岸。",
		"sw": "南风季，往来的船多了些。",
		"calm": "风信未定，港里泊着候风的船。",
	},
	"south": {
		"ne": "北风送来宋船，码头上在卸瓷器。",
		"sw": "南风起了，回宋的船在装香药。",
		"calm": "风信未定，港里的船都在候风。",
	},
	"isle": {
		"ne": "北风大，渔船都拉上了岸。",
		"sw": "南风季，过往的船常在这里取水。",
		"calm": "风信未定，岸上在晒网。",
	},
}

## 战况（Economy.war_status）→ 一句；太平（loyal）不在表里，照季风写
const WAR_LINES := {
	"contested": "码头上兵船多了，商船泊得靠外。",
	"fallen": "港里换了旗号。",
	"besieged": "城门闭着，码头上冷清。",
	"closed": "港口封着，泊着的船都不许出。",
}


## port_id 这一港此刻的那一句；season 为 ne / sw / calm，war 为该港战况。表里没有这一港给 ""（调用方不添这一行）。
static func line(port_id: String, season: String, war: String) -> String:
	if not REGION.has(port_id):
		return ""
	if WAR_LINES.has(war):
		return str(WAR_LINES[war])
	var by_season: Dictionary = LINES.get(str(REGION[port_id]), {})
	return str(by_season.get(season, ""))
