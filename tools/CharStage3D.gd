extends "res://scripts/chars/CharStage3D.gd"
## 人物展台 dev 入口（w26-k2 收束薄包装）：原先 tools/ 是 w20-a3 完成版真身、与 scripts/chars/ 双开；
## 真身已回灌运行线（scripts/chars/CharStage3D.gd 为 scripts/chars/CharsDemo.gd 预载之本体），
## 本件只剩一行 extends 继承、无任何方法覆盖——不含 GameManager / 取数面（不读人物数据，保持零命中、不须登记）。
## 键位 / 取景随基类（见基类头注）；本件供工具 / 门禁 load("res://tools/CharStage3D.gd") 时仍取同一展台。
## 本件不读人物数据（extends 基类亦然，零命中与 L1B_CHECK / 仓务清册断言一致），不须登记 L1B_READERS；
## 被工具 / 门禁 load 时与基类同一展台。
