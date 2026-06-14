# ScolV / 东亚海域立志传 — Godot/GDScript 反模式规则集

本文件是活的清单。每次审查中新发现的反模式类别，追加到这里，使规则集随项目演进。

---

## 1. 主题样式硬编码

**反模式**
```gdscript
xxx.add_theme_font_size_override("font_size", 22)
xxx.add_theme_color_override("font_color", ...)
xxx.add_theme_stylebox_override(...)
```

**正确做法**
在 `main_theme.tres` 中定义对应的 Label/Control 变体（如 FacilityTitle / FacilitySubtitle），代码中改为读取 `theme_type_variation`。

**扫描命令**
```bash
grep -rn "add_theme_.*_override" --include=*.gd
```

**豁免条件**
仅当override的值是运行时动态计算（非常量）、且无法在.tres中预先定义时，可保留——但代码中必须有注释说明原因，审查时需人工确认注释存在且合理。

---

## 2. 动态生成节点的资源泄漏

**反模式**
```gdscript
var sb = StyleBoxFlat.new()   # 每次调用都新建，未缓存
var th = Theme.new()
```

**扫描命令**
```bash
grep -rn "StyleBoxFlat.new\|Theme.new\|StyleBox.*\.new" --include=*.gd
```

**检查点**：是否在循环/频繁调用路径中；是否有对应的缓存/复用机制（如 static var / 字典缓存）。

---

## 3. "已数据驱动"声明 vs 实际硬编码残留

**反模式**：执行者声称某数据已迁移到 json（如 ports.json、events.json），但代码中仍存在该数据的硬编码字面量（数组/字典）。

**检查方法**
- 找到该数据结构涉及的所有字面量数组/字典定义。
- 与对应 json 文件的 key/结构做交叉比对，确认无遗留硬编码副本。

---

## 4. 路径 / 节点ID硬编码

**反模式**
```gdscript
get_node("../../UI/Panel/Label")
load("res://scenes/specific_scene.tscn")
```
当该路径/资源本应来自常量定义或配置表时。

**扫描命令**
```bash
grep -rn 'get_node("\|res://' --include=*.gd
```

**检查点**：结合上下文判断——是否该项目已有常量/配置层（如 Constants.gd），新增的硬编码是否绕过了它。

---

## 5. 信号连接残留 / 重构后死代码

**反模式**：重构后旧的 `.connect()` / `signal` 声明未清理，导致：
- 重复触发同一逻辑
- 引用已删除节点/方法，运行时报错

**扫描命令**
```bash
grep -rn "\.connect(\|disconnect(" --include=*.gd
```

**检查点**：对比diff前后的信号连接表，确认被删除的方法/节点没有遗留connect。

---

## 6. "全面切换"类声明的范围核查

**反模式**：执行者声称"X已全面切换到Y机制"，但实际只改了示例文件/入口文件，其余调用点仍是旧机制。

**检查方法**
- 用旧机制的特征模式（如旧API调用方式）全库grep。
- 确认命中数量为0，或剩余命中均在已知豁免清单内。

---

## 7. 动态拼接资源路径

**反模式**
```gdscript
var tex_path = "res://assets/sprite_" + npc_id.replace("pilot_", "") + ".png"
```
通过硬编码的字符串拼接动态生成资源路径（如图片、场景、音效等）。一旦美术资源命名规范发生变更、或资源目录结构重构，这些拼接会导致运行时载入失败，并且极难通过静态分析工具捕获。

**正确做法**
将具体的资源路径（如 `avatar_path` / `icon_path`）直接作为字段定义在对应的 JSON 配置数据中（例如 `npcs.json` 或 `goods.json`），在代码里读取该字段即可，从而实现完全的数据驱动。

---

## 8. 领域污染 (Domain Contamination) / 越权状态修改

**反模式**：任何感知层 (Sensor)、业务引擎层 (Engine/System) 越权直接修改玩家状态 (GameState)，尤其是对于 `GameState.money`、`GameState.cargo` 的直接加减操作。

```gdscript
# 在 EconomySystem.gd 或 EncounterSystem.gd 中
GameState.money -= cost
GameState.cargo.append(item)
```

**正确做法**：
- 状态修改权限必须被封锁在专属的**领域系统 (Domain System)**，例如 `LedgerSystem` (掌管资金) 或 `CargoSystem` (掌管货物)。
- 其他业务系统只负责提供环境数据、计算结果或抛出 `Intent`，最终必须由 `Handler` 来调用领域系统执行状态的实质性修改。
- `GameState` 应当逐渐收紧写入权限（使用私有变量或受控 Setter），拒绝领域系统之外的写入。

**扫描命令**：
```bash
grep -rn "GameState\." --include=*.gd | grep -E "(\+=|-=|=)"
```

**检查点**：只要上述修改发生在 `LedgerSystem`, `CargoSystem` 或专门的 `xxxDomainSystem` 之外，即构成严重的领域污染，必须立刻打回重构。

---

## 追加记录

| 日期 | 新增反模式 | 来源审查 |
|---|---|---|
| 2026-06-14 | 7. 动态拼接资源路径 | 主架构重构审查 (Refactor Audit) |
| 2026-06-14 | 8. Controller 越权修改状态 | 主架构稳定化阶段 (Stabilization Phase) |
| 2026-06-14 | 9. 路由入口 (Main.gd) 逆向膨胀 | 主架构稳定化阶段 (Stabilization Phase) |

---

## 8. Controller 越权修改状态

**反模式**
```gdscript
# 在 UI Controller 中直接修改状态
GameState.money -= 50
GameState.cargo["丝绸"] += 1
```

**正确做法**
所有状态的改变必须通过 `GameState.apply_effects({"money": -50})` 或专门的网关方法（如 `GameState.handle_special_action()`, `GameState.sell_all_cargo()`）处理。Controller 只能负责呈现和分发意图，绝对不能承担任何业务计算（包括加减乘除）。

**扫描命令**
```bash
grep -rnE "GameState\.[a-zA-Z_]+\s*(\+=|-=|=).*$" --include="*Controller.gd"
```

---

## 9. 路由入口 (Main.gd) 逆向膨胀

**反模式**
在 `Main.gd` 中重新添加大量的 `Button.new()`，或者重新在 `Main.gd` 中书写判断逻辑（如 `if scene_id.begins_with("quanzhou"):`）。

**正确做法**
`Main.gd` 必须保持纯粹的场景路由器属性。如果遇到特殊场景分支，必须优先考虑在 JSON 配置中解决（如 `special_action` 或 `npc_encounter`）。如果必须在代码中处理，必须放在对应模式的 Controller 中。`Main.gd` 不允许重新超过 200 行。

**检查点**：`Main.gd` 的体积和修改日志，如果发现增加了非路由代码，必须立刻剥离。
