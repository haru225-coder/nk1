# 城中各处 NPC 小传

七位城中常客，各自守着一处旧事。每条线分三到四次到访，前一次留下一枚 flag，后一次才开。不是一次办完的买卖。前五位在泉州、广州、温州、博多；后两位在兴化。

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

## 郑堰

- 身份：木兰陂陂司书手，常在陂上校水则、记水租。
- 旧事：陂成于元丰六年（1083），李宏与僧冯智日拦溪；钱四娘的事，乡人至今还说。簿上修陂派工按田亩摊，三户水租拖着，堰脚又松。
- 线：木兰陂 `npc_zhengyan_meet` → 木兰陂 `npc_zhengyan_ledger` → 木兰陂 `npc_zhengyan_invest`（认修陂工，两级本钱，按月分水租） → 木兰陂 `npc_zhengyan_split`。
- 抉择：留作堰工，得乡土二、兴化人情二；按契分，得八十钱、海商信用一。
- flags：`npc_zhengyan_met`、`npc_zhengyan_ledger`、`npc_zhengyan_invested`、`npc_zhengyan_weir` / `npc_zhengyan_share`。

## 许岱

- 身份：涵江盐商，在涵江渡收盐包、押盐引。
- 旧事：今年卤重，盐色白，引价一日一变。景炎以后，盐价一日三变；旧价和关子，他只肯认一样。
- 线：涵江渡 `npc_xudai_meet` → 涵江渡 `npc_xudai_contract` → 涵江渡 `npc_xudai_bargain`（景炎以后，兴化围城或陷落时）。
- 抉择：认旧价，得乡土二、兴化人情二；折关子，得一百钱、海商信用一。
- flags：`npc_xudai_met`、`npc_xudai_contract`、`npc_xudai_oldprice` / `npc_xudai_guanzi`。

## 写实口径

- 七条线都不写石像、雕像、牌坊；不写客气话、空口承诺以后照应、攀交情那一类旧套语。
- 每次到访的提示、选项和结果各自成景，不复用同一句。
- 效果落在既有城区区间内：钱最多一百，名声、人脉、海商信用、人情、学者、海路最多二；梁阿水一线有一条海商信用减一，与涵江渡插队同量级。
- 前五条线没有 invest；郑堰一线有修陂工入股，两级本钱，月初入账。许岱一线的议价只在 1276 年以后、兴化围城或陷落时开。
- `require_flag` 全部由本线的 `effects.flag` 产出。
- 探针：`tools/qa_w57_npc_probe.gd` 核七条线 flag 顺序、各段可达、两条分支收益不同、修陂工月账、战时议价、存档来回。
