# NK1-P9-A Spec | 首小时体验阻断修复

> 优先级：P1，第一批发布  
> 目标：修复玩家启动后第一分钟可见的边框拉伸和标题导航冲突  
> 非目标：不重做整体 UI，不改剧情内容，不改 CommandBar 在港口/调查模式的设计

---

## 1. 已确认问题

### A1. 共用边框不是有效 NinePatch

`assets/ui_frame_koei.png` 为 300x300 的完整装饰构图，当前被多个 `NinePatchRect` 以 `72/56/72/72` margin 拉伸。实机序章中，装饰纹理横向铺满底部并遮占对话区域。

主要消费者：

- `scenes/DialogueBox.tscn`
- `scenes/TownMapView.tscn`
- `scenes/WorldMap.tscn`
- `scenes/StrategicMapOverlay.tscn`
- `scripts/TitleScreenController.gd`
- `scripts/CombatSessionController.gd`
- `scripts/SeaEventController.gd`
- `scripts/EndingSettlementController.gd`

### A2. 标题页存在双导航与假“继续”

- `TitleScreenController` 已生成存档槽、开始旅程、跳过序章。
- `GameShell` 又为 `type=title` 构建 `ui_commands.json/templates/title`。
- 该模板的“开始”和“继续”都指向 `port_quanzhou`；“继续”没有调用 `SaveManager.load_game()`。

## 2. 锁定方案

### A1. 源资源修复

1. **替换原路径** `assets/ui_frame_koei.png`，产出真正可九宫格拉伸的边框：
   - 四角完整且互不越过 patch margin。
   - 四条边只含可重复/可拉伸纹理。
   - 中心区域为低细节、可安全拉伸的透明或深色底。
   - 不保留当前“完整装饰画塞进 300x300”的构图。
2. 优先保持现有资源路径，避免为每个消费者改引用。
3. 根据新资源实际像素重新确定 patch margin；所有消费者使用同一组数值。
4. 不允许通过隐藏 DialogueBox、裁掉大部分纹理或降低透明度掩盖问题。

### A2. 标题导航单一所有者

1. `TitleScreenController` 是标题页唯一动作所有者。
2. `GameShell._resolve_command_spec()` 遇到 `type=title` 时不构建 CommandBar，`CommandBarHost` 必须隐藏或折叠，不占 104px 底部空间。
3. 删除 `data/ui_commands.json` 中不再使用的 `templates.title`，防止未来再次接回假入口。
4. “继续游戏”只通过存在的存档槽按钮触发 `SaveManager.load_game(slot)`。
5. 保留中央“开始旅程”和“跳过序章：直接进入泉州港”。

## 3. 允许修改路径

### 必改

- `assets/ui_frame_koei.png`
- `scripts/GameShell.gd`
- `data/ui_commands.json`
- `scripts/systems/TestRunnerUi.gd` 或 `scripts/systems/TestRunner.gd`

### 仅在 margin/布局需要同步时可改

- `scenes/DialogueBox.tscn`
- `scenes/TownMapView.tscn`
- `scenes/WorldMap.tscn`
- `scenes/StrategicMapOverlay.tscn`
- `scripts/TitleScreenController.gd`
- `scripts/CombatSessionController.gd`
- `scripts/SeaEventController.gd`
- `scripts/EndingSettlementController.gd`
- `scripts/ResourcePaths.gd`

### 禁止修改

- `data/scenes.json` 与 `data/scenes/` 剧情内容
- `scripts/systems/` 下经济、Intent、战斗规则模块（测试文件除外）
- `scripts/state/` 状态结构

## 4. 自动化验收

新增至少以下断言：

1. `type=title` 时 CommandBar 不可见，且 Host 不保留底部交互空间。
2. `ui_commands.json/templates` 不含 `title` 假入口。
3. 标题场景仍存在两个剧情选择：开始序章、跳过序章。
4. 有存档时，槽位按钮调用真实 load 路径；无存档时不显示“继续”。
5. 所有 KOEI frame 消费者可加载/实例化，patch margin 小于纹理宽高的一半。
6. `DialogueBox` 在 1280x720 与 1920x1080 下，Frame 高度保持在设计范围，不覆盖顶部状态栏。

结构断言不能替代实机视觉验收。

## 5. 实机验收矩阵

| 画面 | 1280x720 | 1920x1080 | 验收点 |
|---|---|---|---|
| 标题页 | 必测 | 必测 | 单一导航、无底部重复按钮、存档槽可读 |
| 序章第一段对话 | 必测 | 必测 | 边框四角正常，文本/头像无遮挡 |
| 泉州港主界面 | 必测 | 必测 | CommandBar 只在游戏模式出现 |
| TownMapView | 必测 | 抽测 | 地图外框无拉伸，热点仍可点 |
| 战略地图/世界地图 HUD | 抽测 | 必测 | 共用边框无畸变 |
| 战斗、海上事件、结局框 | 抽测 | 抽测 | 动态创建消费者无畸变 |

验收截图保存到本地 `.godot-tools/p9-a/`，不提交仓库；Walkthrough 中列出截图文件名和分辨率。

## 6. 回归命令

运行 `docs/P9_TASKBOOK.md` 的共同验证基线，并额外短时启动主场景。测试输出不得含新的 `SCRIPT ERROR`、资源加载错误或 Control anchor 警告。

## 7. PASS/FAIL

**PASS**：两个 P1 问题均在实机消失，完整测试全绿，无新视觉消费者残留旧 margin。  
**FAIL**：只修 DialogueBox、标题仍有双入口、或测试只验证资源可加载而未做实机截图，均退回。

---

_P9-A 完成后才允许对外称“首小时体验已收口”。_
