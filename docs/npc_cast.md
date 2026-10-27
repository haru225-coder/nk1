# 城中各处 NPC 小传

五位港口常客，各自守着一处旧事。每条线分三到四次到访，前一次留下一枚 flag，后一次才开。不是一次办完的买卖。

## 马鲁丁

- 身份：波斯纲首后人，住泉州蕃坊，常在清净寺门楼。
- 旧事：父亲搭陈氏叔父的船，欠下九十钱脚钱，押一枚铜牌。货在占城外海沉了，账一直挂着。
- 线：清净寺门楼 `npc_maruding_meet` → 蕃坊石巷 `npc_maruding_ledger` → 聚宝街 `npc_maruding_settle`。
- 抉择：销账，得海商信用二、人脉一；收九十钱，铜牌归你。
- flags：`npc_maruding_met`、`npc_maruding_ledger`、`npc_maruding_forgiven` / `npc_maruding_paid`。

## 祝伯

- 身份：南海神庙庙祝。
- 旧事：手里有一封未封口的札，要托南回的船送去泉州顺济宫。
- 线：南海神庙 `npc_zhubo_ask` → 扶胥码头 `npc_zhubo_letter` → 海山楼 `npc_zhubo_wind` → 泉州顺济宫 `npc_zhubo_deliver`。
- 抉择：交顺济宫，得泉州人情二、名声一；转给蕃坊，得人脉二、六十钱。
- flags：`npc_zhubo_asked`、`npc_zhubo_letter`、`npc_zhubo_carry`、`npc_zhubo_temple` / `npc_zhubo_broker`。

## 蔡荣

- 身份：博多唐房宋商纲首。
- 旧事：同街沈二郎的船本月报的瓷比舱里少。纳屋的米包后压着一摞没上簿的瓷箱，箱底有沈家的押记。
- 线：唐房街 `npc_cairong_meet` → 纳屋 `npc_cairong_evidence` → 大宰府门 `npc_cairong_settle`。
- 抉择：报大宰府，得名声二、博多人情一；替他遮下，得人脉二、海商信用一。
- flags：`npc_cairong_met`、`npc_cairong_evidence`、`npc_cairong_exposed` / `npc_cairong_covered`。

## 周行

- 身份：永嘉书院穷书生。
- 旧事：在书院抄军报。鄂州的消息一天一个说法，他把两种都记在纸上。
- 线：永嘉书院 `npc_zhouxing_meet` → 茶坊 `npc_zhouxing_rumor` → 朔门码头 `npc_zhouxing_bet`（1259 年十月至十二月）。
- 抉择：押和议，付三十钱，得九十钱、海商信用一；押兵事未了，付三十钱，得学者二、名声一。
- flags：`npc_zhouxing_met`、`npc_zhouxing_heard`、`npc_zhouxing_peace` / `npc_zhouxing_war`。

## 梁阿水

- 身份：扶胥老舵工。
- 旧事：口外有一艘沉船，舱里还有几箱瓷。他晓得退潮的时辰，也晓得夜里的潮比白日急。
- 线：扶胥码头 `npc_liang_wreck` → 南海神庙 `npc_liang_tide` → 珠江蛋排 `npc_liang_dive`。
- 抉择：今夜就去，得九十钱、海商信用减一，梁阿水不再回来；等风平，得人脉二、海路一，人还在。
- flags：`npc_liang_met`、`npc_liang_tide`、`npc_liang_lost` / `npc_liang_saved`。

## 写实口径

- 五条线都不写石像、雕像、牌坊；不写客气话、空口承诺以后照应、攀交情那一类旧套语。
- 每次到访的提示、选项和结果各自成景，不复用同一句。
- 效果落在既有城区区间内：钱最多九十，名声、人脉、海商信用、人情、学者、海路最多二；梁阿水一线有一条海商信用减一，与涵江渡插队同量级。
- 五条线没有 invest；`require_flag` 全部由本线的 `effects.flag` 产出。
- 探针：`tools/qa_w57_npc_probe.gd` 核 flag 顺序、各段可达、两条分支收益不同、存档来回。
