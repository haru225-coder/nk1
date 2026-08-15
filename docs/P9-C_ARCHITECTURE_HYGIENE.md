# NK1-P9-C Spec | 主题与 GameState 架构卫生

> 优先级：P2，第三批发布  
> 前置：P9-B 已 PASS  
> 目标：在不重写玩法的前提下，阻止主题漂移和 GameState 继续膨胀

---

## 1. C1：固定主题样式回归主题资源

### 处理范围

优先处理当前发布路径中的固定样式：

- `scripts/EndingSettlementController.gd`
- `scripts/TitleScreenController.gd`
- `scripts/TownMapHotspot.gd`
- `scripts/TownMapView.gd`
- `scripts/PortScreenController.gd`
- `scripts/MapUiTheme.gd`
- `assets/main_theme.tres`
- `scripts/UITheme.gd`
- `scripts/GameColors.gd`

### 规则

1. 固定字体大小、固定文字色、固定 Panel StyleBox 进入 `main_theme.tres` 的 theme variation。
2. GDScript 只设置 `theme_type_variation`，不重复硬编码常量视觉值。
3. 运行时状态色、动态尺寸或按任务状态变化的边框可保留 override，但必须有 `[豁免]` 注释说明为什么无法静态定义。
4. `StyleBoxFlat.new()` 不得出现在 hover、刷新、列表重建等高频路径；可使用缓存或主题 variation。
5. 不追求一次清零全库 115 个命中；本批必须清理上述发布路径，并保证全库命中数不增加。

### C1 验收

- [ ] EndingSettlement 固定颜色/字号不再散落于 `_build_ui()`。
- [ ] TownMapHotspot 常驻牌匾样式来自主题；任务/完成状态只保留必要动态差异。
- [ ] 主题 variation 在 `UITheme.all_variations()` 等现有测试中登记。
- [ ] `rg -n add_theme_.*_override` 的新增命中均有合理豁免。

## 2. C2：抽离 GameState 越界职责

### 锁定边界

`GameState` 继续作为兼容门面和状态聚合器，不全面重写。仅抽离审计确认的两个越界职责：

1. **过场请求**：`GameState` 不得自行动态加载 ModeStack、查找 CutscenePlayer 或遍历场景树。新增/复用信号，把 `cutscene_id` 交给 `AppRoot`/`Main` 处理。
2. **经济月报文案**：`_compose_economy_pulse_message()` 移入现有 `EconomyFeel.gd` 或最接近的经济表现层；`GameState` 只触发并记录结果。

### 允许修改路径

- `scripts/GameState.gd`
- `scripts/AppRoot.gd`
- `scripts/Main.gd`
- `scripts/EconomyFeel.gd`
- `scripts/ModeStack.gd`（仅接口适配，不重写模式栈）
- 对应 TestRunner 文件

### 禁止范围

- 不改 Intent/Handler/Ledger 交易语义。
- 不重写 `GameState.apply_effects` 映射机制。
- 不把所有 special action 一次迁走；其余债务登记到后续任务。
- 不改剧情 JSON 的 effect schema。

### C2 验收

- [ ] `GameState.gd` 不再查找 `ShellCutscenePlayer` / `CutscenePlayer`，也不动态加载 ModeStack 播放过场。
- [ ] 章三收束、升秩、结局的过场顺序与队列行为不回归。
- [ ] 经济月报在有事件、套利机会、普通港口三种路径下文案保持兼容。
- [ ] 新信号重复绑定有 `is_connected` 防护。
- [ ] GameState 保持旧公开 API，现有调用方无需批量修改。

## 3. 扫描命令

```powershell
rg -n add_theme_.*_override scripts -g '*.gd'
rg -n StyleBox(Flat|Texture)?\.new|Theme\.new scripts -g '*.gd'
rg -n ShellCutscenePlayer|CutscenePlayer|SCRIPT_MODE_STACK scripts\GameState.gd
rg -n change_scene_to_file|change_scene_to_packed scripts -g '*.gd'
```

允许保留的 scene-change 命中必须是无 AppRoot 宿主时的兼容回退，并有测试覆盖。

## 4. 非功能要求

- 不新增逐帧分配或全树扫描。
- 不改变存档 schema。
- 不新增 autoload。
- 不引入新依赖或插件。
- 单次提交修改面应保持可审计；C1 与 C2 建议分两个提交。

## 5. PASS/FAIL

**PASS**：发布路径主题样式收敛、GameState 两项越界职责已抽离、所有回归与模式切换测试通过。  
**FAIL**：以“统一”为名全面重写 GameState、引入新框架、或只移动代码却保留场景树查找，均退回。

---

_P9-C 的目标是冻结良好边界，而不是追求文件行数漂亮。_
