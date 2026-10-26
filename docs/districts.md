# 城中各处

港口页上的九处设施（牙行、市舶司、船屋等）仍是每港共用的门。城中各处是另一层：一港可以有十几处自己的地方，各有底图，各有能改钱、货、行情、名声、人情、公凭的事。本仓先落泉州、兴化两港，各十五处。别的港只加 `data/districts.json` 和 `assets/bg_dist_*.jpg`，不用改脚本。

视觉口径跟 [宋金元史实与名胜资料.md](宋金元史实与名胜资料.md)。底图是南宋墨色设色，灰瓦、红柱、鸱尾，没有禁城、辫子、青花。贡院只画石碑和榜墙，不画石像。

## 玩家从哪进

寻常港页、且这港在表里有城区时，岸上多一枚「城中各处」。守城页、终局页、表里没有的港不出这枚钮。名单标题就是「城中各处」。进去换这处的底图，离开回到名单并换回港图，再离开回到港页。不改 `current_scene_id`，存档仍记港口。

不另挂 autoload。账本是 `scripts/core/Districts.gd`，页是 `scripts/ui/DistrictPage.gd`，都由 `Main` 在文件尾预载。月初入账挂在 `Economy.on_month_changed` 末尾，运行时再 `load` 账本，避免和 `Economy` 循环解析。

## 数据

文件 `data/districts.json`。顶层只有一个数组，不要再加 meta：

```json
{ "districts": [ { "id": "qz_houzhu", "port": "quanzhou" } ] }
```

一处：

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| id | 是 | 全区唯一。建议港短名加下划线，如 `qz_`、`xh_`。这个 id 不要再写进别的字符串字段 |
| port | 是 | `data/ports.json` 里的港 id。兴化城是 `xinghua`，不是 `xinghua_harbor` |
| name | 是 | 上屏的地名 |
| kind | 是 | 码头、衙廊、坊巷、寺观、宫庙、山亭、桥、窑、牙巷、塌房、贡院、门楼、茶坊、陂塘、坊门、军学、荔枝、渡口、军衙、坊市、书坊、酒库、铁作、城隍、瓮城。账本有中文旁注，不认识的 kind 旁注就空着 |
| bg | 是 | 只要文件名，如 `bg_dist_qz_houzhu.jpg`。运行时自己加 `res://assets/`。必须用 `bg_dist_` 前缀，不要写成 `bg_<港id>_…`，否则会被当成港页战况变体 |
| description | 是 | 名单和事页上的正文。全角标点 |
| unlock | 否 | 跟下面交互的 unlock 同一套。关着时名单上盖章，不给「进去」 |
| lock_reason | 否 | 盖章用的句子。不写就用通用原因 |
| interactions | 是 | 至少一条 |

交互共有字段：`id`（全局唯一，不要和 district id 相同）、`type`、`label`、`text`。可选 `cost`、`once`、`once_per`（`year` 或 `month`）、`cooldown_days`、`unlock`。

`unlock` 的键：`year_min`、`year_max`、`years`、`months`、`chapter_min`、`war_in`、`war_not`、`require_flag`、`hide_if_flag`、`favour_min`、`needs_licence`、`needs_hire`、`siege`。关着的原因分别是：年份未到、时节已过、不是大比之年或今年不开、还不是这个月的事、这事还轮不到、眼下的战况不对、这时候去不得、还没到那一步、人情还不够、没有这张公凭、没有这位帮手、城防的账还没开。`hide_if_flag` 为真时整条不画。

大比之年写在交互上：`"exam": true`，再加 `years` 与 `months`。现用年是 1256、1259、1262、1265、1268、1271、1274，月是 8、9、10。1268 年士人线另写 `"scholar_1268": true`，身份是士人或已改名陈文龙时，看榜的句子里带出榜首。

## 八种事

钱数到账都走现有的 `GameState` / `Economy` / `Fleet`。买价卖价是牙行价乘 `price_mul`，再乘公凭和雇人的折扣，至少 1 钱。

- `buy` / `sell`：`good` 必须在 `data/goods.json`。`qty`、`price_mul`。`impact` 默认 true，会推高或压低该港这门货的行情。写成 false 则不动行情。货不在这港的市上、或行情表里还没有这个键，也不许新造键。卖出时委办还欠的件数留在舱里，不够卖就回「委办货不上秤」。禁货（铁器、宋钱）买入时，没写 `attention` 就给蒲家留意加 2。
- `invest`：`costs` 与 `monthly` 等长，花费都要大于 0。`monthly` 是这一级的月入，不是逐级相加。`shop` 是月初通告里的铺名。铺面入账和港口修埠不是一笔账。
- `hire`：`who`、`cost`、`wage`。人记在城区档，不进 `Crew.hired`。月初发不出月俸就辞退。`attention_ease` 是在身边时每月减的蒲家留意。`monthly_effects` 用和 effects 相同的键，俸发出去才生效。`hire_bonus` 指另一条雇人 id，雇着时这单乘 `hire_mul`（默认 0.9）。
- `rumor`：`port`、`good`、`mul`。那一港必须本来就做这门货，行情键也得先在。成功后记一笔传闻，并按 `mul` 改那一港的价。选不出货就不收钱。
- `favour`：花钱或白做一件事。效果见下。
- `licence`：`licence` 必须以 `lic_` 开头。只在城区交易里认，不改全局抽解。`needs_licence` 写在交互顶上时，没有这张凭就盖「未有公凭」，有了再乘 `licence_mul`（默认 0.9）。`licence_bonus` 加 `bonus_mul` 是另一条路：事仍看得见，有凭才打折。两套不要叠在同一条上。
- `choice`：`options` 里每条有自己的 `id`、`label`、`text`、`cost`、`effects`，也可以带 `rumor`。父级的 once、cooldown、unlock 照旧。选了一条就按父级 id 记已办。

`effects` 的键：`fame`、`merchant_credit`、`network`、`scholar_tendency`、`sea_tendency`、`hometown_tendency`、`pu_attention`、`martial`、`money`（正数入账，负数另算花费）、`flag`、`note`（札记）、`favour`（加在这一处所属的港上）、`siege`（`{键: 增量}`，城防没开就跳过）、`cargo_add`、`cargo_take`（`{good, qty}`，委办货留着）。`unlock.siege` 为真时，城防没开整件事办不成，也不会先扣货。

正文用宋人口气。钱在界面上写「钱」。会子、关子可以出现在叙述里。不要写「点击」「解锁」「系统」。标点用全角。名声增减写成「名声加 2」「名声减 1」，不要写成半角减号。

## 存档

`GameState.districts` 固定八个桶，空桶也留着。`from_dict` 会归一成整数和 `true`，缺档、坏档都落成空桶。不要改这八个键的名字，`Districts.gd` 的 `BUCKETS` 和 `GameState._districts_normalize` 是同一份。

| 桶 | 内容 |
| --- | --- |
| once | 交互 id → 办过的绝对日 |
| year | 交互 id → 办过的年 |
| month | 交互 id → 年乘 12 加月 |
| cool | 交互 id → 可以再办的绝对日 |
| invest | 交互 id → 已入股的级 |
| hire | 交互 id → true |
| licence | 凭 id → true |
| favour | 港 id → 整数 |

schema 仍是 4。旧档没有 `districts` 时读出来是八个空桶。

月初一句通告形如「【城中】茶坊入账 14 钱。通事月俸 22 钱。」发不出俸是「铁匠月俸未发，人走了。」没有任何铺和人要结算时不发这句话。

## 给别的港补城区

1. 在 `districts` 数组里加这个港的处。每处至少一条真正改得到状态的事，不要只写风景。
2. 买卖和传闻用的货，必须是那一港 `ports.json` 市场里有的，而且行情表会有键。不在市上的货可以买，但 `impact` 要写 false，也不要拿它做传闻。
3. 底图用 Imagine 生成，再裁成 1280×720 的 jpg，质量约 82，单张不超过 350KB。文件名 `bg_dist_<短名>.jpg`，放在 `assets/` 根上。看过再留：不要字、不要石像、不要青花、不要明清牌坊。
4. 跑一次 `$GODOT --headless --path . --import`，把 `.import` 和脚本 `.uid` 一起提交。同一时间只开一个 Godot。
5. `python3 tools/check_assets.py`、`python3 tools/check_sidecars.py`、`python3 tools/check_w53_copy.py`。城区探针是 `tools/qa_w55_districts_probe.gd`，它会扫整张表，新港的缺图和坏交互也会红。

不要把 district id 写进别的字段当字符串。港 id、货 id、凭 id（`lic_`）、雇人 id 可以互相引用。这样这张表不会被数据族门禁当成「id 互相指认」的一族。若仍被标出来，到 `tools/data_family.json` 显式登记，不要为了过门禁去加无意义的互指。

## 待画城区（pending）

底图还没画好的城区，不进 `data/districts.json`，先放在 `data/districts_pending/<port_id>.json`，schema 与 `districts.json` 完全相同（顶层 `{"districts":[...]}`），每条额外写 `"pending_art": true`，`"bg"` 写计划文件名 `bg_dist_<短名>_<slug>.jpg`（文件尚不存在，不要创建）。游戏的 `Districts.gd` 只读 `data/districts.json`，所以这些条目玩家永远看不到，直到美术波把它们移过去。

美术波移入的步骤：
1. 生成并裁好底图 jpg，放进 `assets/`，文件名与 pending 条目的 `bg` 一致。
2. 从 `data/districts_pending/<port_id>.json` 把条目移入 `data/districts.json` 的 `districts` 数组，去掉 `"pending_art"` 字段（或保留无妨，账本不读它）。
3. 该港条目移空后，删除对应的 pending 文件。
4. 跑 `$GODOT --headless --path . --import`，再跑 `tools/qa_w55_districts_probe.gd` 与 `tools/qa_w56_pending_districts_probe.gd`，全部绿才算移入完成。

探针 `tools/qa_w56_pending_districts_probe.gd` 扫全部 pending 文件，校验 id 全局唯一、字段、货在港市、传闻与入股、公凭、大比之年、GB2312 文案，确认底图不存在、`pending_art` 为真，并确认账本不暴露任何 pending id。
