# NK1 UI · 给人和 AI 的接法

## 0. 怎么用这份文件

- 写 UI 前先读完本文件和 `docs/美术规范.md`。本文件管索引、命名和接法；色值、字阶、type variation、贴图细节以美术规范为准。
- 颜色只许用第 1 节的 token 名。脚本不得新增 `Color(...)` 或 hex 色值；本地 `const` 只许保存 token 名，确需缓存颜色时也只能从 `UiTheme` 读取。
- 新控件先列状态表，再写脚本。至少覆盖 normal、hover、focus、pressed、disabled；有持久状态的控件另列 visited、selected。
- 改视觉先改主题。色板变动先更新美术规范，再改 `build_theme.gd` 并生成 `assets/theme/nk1_theme.tres`，最后调整脚本。不得逐控件补色。
- 字、图标和描边优先走 theme color；底色和边框走主题 StyleBox。单控件差异才用 theme override。`UiTheme` 是运行期皮肤桥，不是第二份色板。

## 1. Token 表

统一优先级：主题 theme color / type variation 引用的 StyleBox优先；单实例 theme color override 次之；`UiTheme` 读表用于尚未收编的控件。脚本常量不得保存色值。

| token 名 | 色值 hex | 对应美术规范里的名字 | Godot 接法 | 禁止用法 |
|---|---|---|---|---|
| `ink_black` | `#0d0b09` | 焦墨 | 墨底、弹层和遮罩走 StyleBox；需要作字色时走 theme color | 禁止另写近黑色或复制浮点色值 |
| `ink` | `#1a1612` | 墨 | hover、pressed 等墨底状态走 StyleBox；字色走 theme color | 禁止与焦墨按控件随意互换 |
| `paper` | `#e9dcc0` | 宣纸 | 面板底走 StyleBox；墨底主文字走 theme color | 禁止用纯白或另造浅色纸底 |
| `silk` | `#cdb88f` | 旧绢 | 绢面板和次级底走 StyleBox；必要时作墨底次级文字 | 禁止与宣纸按脚本各自选择 |
| `gold` | `#c9a14a` | 泥金 | 描边、注记和普通选中态优先走 theme color，StyleBox 引用同一 token | 禁止另写近似黄色 |
| `gold_light` | `#ecd08a` | 亮泥金 | hover、focus、selected 的边或字走 theme color | 禁止作宣纸底的小号正文 |
| `cinnabar` | `#b0302a` | 朱砂 | 主按钮和印面走 StyleBox；对应字色单独指定 | 禁止当普通正文色或通用报错色 |
| `cinnabar_dark` | `#8e2420` | 朱砂深 | 朱砂按钮 pressed 底及既有深色印边走 StyleBox | 禁止用任意黑色透明层代替 |
| `indigo` | `#1f3a4d` | 靛青 | 仅用于美术规范已有的靛青区域，按对应 theme color 或 StyleBox 接入 | 禁止新增蓝色状态含义 |
| `stone_blue` | `#3b6e7a` | 石青 | 可用于规范内辅助描边和墨点 visited 标记 | 禁止替代 hover、focus 或 disabled |
| `ink_note` | `#3d3124` | 说明墨（说明墨字） | 宣纸、旧绢上的说明文字走 theme color | 禁止在焦墨底上作小号正文 |
| `disabled` | `#9a9080` | 不可用 | disabled 字、边走 theme color，StyleBox 引用同一 token | 禁止为了省事兼作普通次级正文 |
| `seal_text` | `#f6eedb` | 印面字 | 朱砂底文字走 theme color | 禁止在宣纸、旧绢底上作正文 |

### 透明度约定

| 固定档 | 用途 |
|---|---|
| `1.00` | 文字、图标、描边、印面和不透明贴图。默认档。 |
| `0.97` | 宣纸面板底。对应需要轻微透底的纸面，不用于文字。 |
| `0.96` | 首页墨点的 hover、focus、pressed 墨底。 |
| `0.90` | 面板或弹层后的焦墨遮罩。 |
| `0.88` | 首页墨点 normal 墨底。 |

同一用途只用同一档。不得随手写 `0.90`、`0.92`、`0.95` 等新档。disabled 使用 `disabled` token，不再给整个控件叠一层透明度。新增档位须先改美术规范、主题和本节。

## 2. 组件状态约定

以下只使用现有绢本墨笔色板。hover 不代替 focus。disabled 不响应输入。状态样式由主题提供，脚本只切状态。

### 墨底按钮（主）

| 状态 | 底色 token | 边 / 字色 token | 备注 |
|---|---|---|---|
| normal | `ink_black` | 边 `gold`；字 `paper` | 默认主按钮，不额外加阴影 |
| hover | `ink` | 边 `gold_light`；字 `paper` | 不改尺寸和位置 |
| focus | `ink_black` | 边 `gold_light`；字 `paper` | 使用主题 focus StyleBox；移开指针后仍保留 |
| pressed | `ink` | 边 `gold`；字 `gold_light` | 不改布局，不用朱砂代替 |
| disabled | `ink_black` | 边、字均用 `disabled` | 不再叠透明度 |

### 朱砂主按钮

| 状态 | 底色 token | 边 / 字色 token | 备注 |
|---|---|---|---|
| normal | `cinnabar` | 边 `cinnabar_dark`；字 `seal_text` | 一个操作区只保留必要的朱砂主按钮 |
| hover | `cinnabar` | 边 `gold_light`；字 `seal_text` | 只改现有边色，不新增发光 |
| focus | `cinnabar` | 边 `gold_light`；字 `seal_text` | focus 由独立 StyleBox 保持，不能依赖 hover |
| pressed | `cinnabar_dark` | 边 `cinnabar_dark`；字 `seal_text` | 不改变按钮尺寸 |
| disabled | `ink_black` | 边、字均用 `disabled` | 去除朱砂强调，不响应输入 |

### 绢面板上的文字按钮

| 状态 | 底色 token | 边 / 字色 token | 备注 |
|---|---|---|---|
| normal | 无，保留绢面 | 字 `ink_note`；无边 | 不另加按钮框 |
| hover | `paper` × 0.88 | 字 `ink_black`；无边 | 只铺现有宣纸色，不加新贴图 |
| focus | 无，保留绢面 | 边 `ink`；字 `ink_black` | 焦点边须在实际绢底上可见 |
| pressed | `silk` | 边 `gold`；字 `ink_black` | 松开后再按 hover 或 focus 恢复 |
| disabled | 无，保留绢面 | 字 `disabled`；无边 | 不响应输入 |

### 首页墨点

| 状态 | 底色 token | 边 / 字色 token | 备注 |
|---|---|---|---|
| normal | `ink_black` × 0.88 | 边 `gold`；字 `paper` | 可点注记默认态 |
| hover | `ink` × 0.96 | 边 `gold_light`；字 `gold_light` | 不移动墨点，不改地图布局 |
| focus | `ink_black` × 0.96 | 边 `gold_light`；字 `paper` | 键盘焦点移出 hover 后仍可辨认 |
| pressed | `ink` × 0.96 | 边 `gold`；字 `gold_light` | 只表示按下，不代替 selected |
| disabled | `ink_black` × 0.88 | 边、字均用 `disabled` | 不可点，不显示 hover |
| visited | `ink_black` × 0.88 | 边 `stone_blue`；字 `silk` | 表示看过，不表示不可用 |
| selected | `ink` × 0.96 | 边 `gold_light`；字 `gold_light` | 指针离开后仍保留 |

visited、selected 是持久标记。hover、focus、pressed 是瞬时状态。瞬时状态结束后恢复持久标记。disabled 优先级最高。

### 面板 / 弹层

| 状态 | 底色 token | 边 / 字色 token | 备注 |
|---|---|---|---|
| normal | 绢面板用 `silk` × 0.97；弹层用 `paper` × 0.97 | 边 `gold`；正文 `ink_note` | 弹层后遮罩用 `ink_black` × 0.90 |
| hover | 同 normal | 同 normal | 非交互面板不做 hover |
| focus | 同 normal | 同 normal | 焦点样式落在面板内的具体控件上 |
| pressed | 同 normal | 同 normal | 不造面板按压效果 |
| disabled | 同 normal | 不可用内容用 `disabled` | 只禁用相应控件，不整面板降 alpha |

### 输入框

| 状态 | 底色 token | 边 / 字色 token | 备注 |
|---|---|---|---|
| normal | `paper` | 边 `ink_note`；字 `ink_note` | 使用既有边框和字阶 |
| hover | `paper` | 边 `gold`；字 `ink_note` | 不改变输入框尺寸 |
| focus | `paper` | 边 `ink_black`；字 `ink_black` | 焦点边持续显示，不能与 hover 混淆 |
| pressed | `silk` | 边 `gold`；字 `ink_black` | 编辑中的持续状态仍以 focus 为准 |
| disabled | `silk` | 边、字均用 `disabled` | 禁止输入，不接收焦点 |

## 3. 硬编码清册（首批）

本表只处理 `TitleMapExplorer.gd` 摘录。统一以第 1 节 hex 为准，不保留浮点色值作为第二套色板。

| 现名 | 应映射的 token | 建议改法 |
|---|---|---|
| `INK` | `ink_black`，alpha `0.88` | 收进首页墨点 normal 的 StyleBox；过渡期间由 `UiTheme` 读表，不保留本地色值。 |
| `INK_HOVER` | `ink`，alpha `0.96` | 收进墨点 hover / pressed 的 StyleBox，脚本只切换状态。 |
| `PAPER` | `paper`，alpha `0.97` | 作为宣纸面板底接入 StyleBox；单实例差异用 theme override，不另建近色。 |
| `MUTED` | `disabled`，alpha `1.00` | 原调用点确为不可用或既有弱化标记时改走 `UiTheme` 或 font color override；普通说明字不得套用。 |
| `GOLD` | `gold`，alpha `1.00` | 描边、注记统一改走 theme color 或 `UiTheme` 的泥金读取项。 |
| `PALE_GOLD` | `gold_light`，alpha `1.00` | hover、selected 等亮金文字和描边改走 theme color override 或 `UiTheme` 读取项。 |
| `VEILED_INK` | `ink_black`，alpha `0.90` | 收进面板遮罩 StyleBox，不再单独保存遮罩色。 |
| `PALE_PAPER` | `paper`，alpha `1.00` | 墨底主文字改走 theme color；与 `PAPER` 只按透明度和用途区分。 |
| `MUTED_PAPER` | `disabled`，alpha `1.00` | 仅在原用途确为弱化或不可用时替换为 `UiTheme` / theme color；不得把普通正文改成不可用色。 |

`MUTED` 与 `MUTED_PAPER` 色值接近，但不能只为减少常量而合并。若原用途是普通次级文字，需先按美术规范确认角色，再决定是否补 token；本批不自行新增色值。

## 4. 新界面检查清单

- [ ] 已读 `docs/UI_AGENTS.md` 和 `docs/美术规范.md`，没有另立局部 UI 约定。
- [ ] 脚本中无新增 `Color(...)` 或 hex 色值，所有颜色均能追到 token。
- [ ] 使用已登记的 type variation；新名称先登记规范，并由 `build_theme.gd` 生成主题。
- [ ] 已列 normal、hover、focus、pressed、disabled；墨点类控件已列 visited、selected。
- [ ] focus 不依赖 hover，键盘操作能看到焦点，disabled 不接收输入。
- [ ] 正文与背景对比度达到 4.5:1；大字和焦点边达到 3:1，并在实际底图上检查。
- [ ] StyleBox 和字体颜色均来自主题，单控件 override 没有绕过 token。
- [ ] 透明度只使用 `1.00 / 0.97 / 0.96 / 0.90 / 0.88`，未新增随意档位。
- [ ] 贴图来自规范清单，已备 2× 资源，并检查九宫格、拉伸和导入设置。
- [ ] 字体、字阶、行距沿用主题，长文本、换行和裁剪已检查。
- [ ] 文案使用短句和现有中文专有名，已删掉宣传腔、空泛形容词及「愿景／赋能／沉浸式体验」等措辞。
- [ ] 新 token、新状态或新 variation 已同步更新主题和文档，没有只留在脚本里的约定。

## 5. 不做清单

- 不引入 React、CSS、StyleX 运行时或 DOM 结构。Astryx 只作为 token、状态和文档索引的组织参考。
- 不重画整套主题贴图，不更换绢本墨笔色板，不新增一套视觉风格。
- 本任务只落文档。不改 GDScript，不改 `build_theme.gd`，不重新生成 `.tres`，不提供 diff。
- 不把本清册扩成全仓硬编码审计。其他脚本另列批次。
- 官网 `as-sin.com` 若要使用 Astryx，另开任务，不与 NK1 的 Godot 主题整理混在一起。