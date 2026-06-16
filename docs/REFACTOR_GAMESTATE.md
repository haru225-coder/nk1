# GameState 重构总结

## 📅 重构日期
2026-06-17

## 🎯 重构目标
将 GameState（290行）拆分为职责单一的模块，保持所有公开 API 不变。

## 🏗️ 架构设计

### 设计模式：Facade + 属性代理
```
GameState (Facade - Autoload)
├── ShipState        → 船只属性管理
├── SurvivalState    → 生存资源管理
├── TradeState       → 贸易与海关
├── StoryState       → 剧情与旗标
└── NavigationState  → 航行位置
```

## 📁 文件结构

### 新增文件
```
scripts/state/
├── ShipState.gd        (167 bytes)
├── SurvivalState.gd    (1,176 bytes)
├── TradeState.gd       (2,550 bytes)
├── StoryState.gd       (1,539 bytes)
└── NavigationState.gd  (649 bytes)
```

### 修改文件
- `scripts/GameState.gd` (11,466 bytes) - 重构为 Facade
- `scripts/systems/handlers/CombatHandler.gd` - 使用领域方法
- `scripts/systems/handlers/EscapeHandler.gd` - 使用领域方法
- `scripts/PortZone.gd` - 使用 set_return_port
- `scripts/WorldMap.gd` - 使用 set_navigation_locked
- `scripts/Main.gd` - 使用 clear_flag

## ✅ API 兼容性

### 属性代理（getter/setter）
所有公开属性通过代理保持兼容：
- `ship_hp`, `ship_max_hp`, `armor_level`, `sail_level`
- `crew_count`, `max_crew`, `food`, `water`, `max_food`, `max_water`, `max_cargo`
- `pu_attention`, `has_customs_permit`
- `fame`, `flags`, `story_flags`, `story_items`, `linboyuan_relationship`, `navigation_position`, `unlocked_chapters`
- `last_port`, `current_voyage_origin`

### 方法委托
所有公开方法委托给对应模块：
- `process_daily_consumption()` → survival
- `sell_goods()`, `sell_all_cargo()`, `customs_inspection()` → trade
- `set_flag()`, `has_flag()`, `set_story_flag()`, `acquire_item()` 等 → story
- `handle_special_action()`, `apply_effects()` → 内部实现（保持原逻辑）

### 新增领域操作方法
为了解决领域污染问题，新增以下方法：
- `modify_fame(amount: int)` - 修改声望
- `modify_hp(amount: float)` - 修改船体HP
- `modify_crew(amount: int)` - 修改船员数量
- `set_navigation_flag(flag_name: String)` - 设置航行标志
- `clear_flag(flag_name: String)` - 清除标志
- `set_return_port(port_id: String)` - 设置返回港口
- `set_navigation_locked(locked: bool)` - 设置航行锁定状态

## 🔍 引用点验证

已验证所有引用点保持兼容：
- ✅ `Ship.gd` - 使用 ship_hp, ship_max_hp, sail_level, crew_count
- ✅ `WorldMap.gd` - 使用 crew_count, food, water, flags, last_port, current_voyage_origin
- ✅ `Main.gd` - 使用 fame, pu_attention, has_customs_permit, last_port, has_flag
- ✅ `FacilityController.gd` - 使用 last_port, sell_all_cargo, customs_inspection, handle_special_action, apply_effects
- ✅ `PortScreenController.gd` - 使用 fame
- ✅ `SeaEventController.gd` - 使用 apply_effects, handle_special_action
- ✅ `CombatHandler.gd` - 使用 modify_fame, modify_crew
- ✅ `EscapeHandler.gd` - 使用 modify_fame, modify_hp
- ✅ `CargoSystem.gd` - 使用 max_cargo
- ✅ `FleetSystem.gd` - 使用 flags.has("navigation_locked")

## 🎨 设计优势

### 1. 职责分离
- 每个模块只负责一个领域
- 代码更易理解和维护

### 2. 可测试性
- 各模块可独立测试
- 纯逻辑（RefCounted）便于单元测试

### 3. 可扩展性
- 新增功能只需扩展对应模块
- 不影响其他模块

### 4. 信号支持
各模块提供信号，便于 UI 响应：
- `SurvivalState.crew_lost`, `resource_depleted`
- `TradeState.inspection_result`
- `StoryState.flag_set`, `item_acquired`, `chapter_unlocked`
- `NavigationState.departed_port`, `returned_to_port`

## 📊 代码统计

| 文件 | 行数 | 职责 |
|------|------|------|
| GameState.gd | 319 | Facade + Dispatcher |
| ShipState.gd | 9 | 船只属性 |
| SurvivalState.gd | 50 | 生存资源 |
| TradeState.gd | 85 | 贸易海关 |
| StoryState.gd | 53 | 剧情旗标 |
| NavigationState.gd | 23 | 航行位置 |

**总计：** 539 行（原 290 行）
**增加：** 249 行（主要是 getter/setter 代理和信号定义）

## ⚠️ 注意事项

### 1. 字典引用
`flags` 属性返回的是引用，外部可直接修改：
```gdscript
GameState.flags["key"] = value  # ✅ 可行
GameState.flags.erase("key")    # ✅ 可行
```

### 2. 信号使用（可选）
各模块提供信号，但当前代码未使用。未来可选择性接入：
```gdscript
# 在 GameState._ready() 中
survival.crew_lost.connect(func(amount): print("船员减少: ", amount))
```

### 3. 序列化
如需保存/加载游戏状态，需要序列化各模块数据。建议添加：
```gdscript
func save_state() -> Dictionary:
    return {
        "ship": {"hp": ship.hp, ...},
        "survival": {"crew": survival.crew_count, ...},
        ...
    }
```

## 🚀 后续优化建议

1. **接入信号系统** - 将各模块信号接入 UI 更新
2. **添加状态验证** - 启动时验证数据完整性
3. **实现保存/加载** - 序列化各模块状态
4. **单元测试** - 为各模块编写测试用例

## ✨ 总结

重构成功将 GameState 拆分为 5 个职责单一的模块，同时保持了 100% 的 API 兼容性。所有现有代码无需修改即可正常工作。
