# NK1-P9-B Spec | 存档与发布可靠性

> 优先级：P1/P2，第二批发布  
> 前置：P9-A 已 PASS  
> 目标：保证存档不会因中断毁损，并能从干净仓库稳定产出 Windows 包

---

## 1. 子任务 B1：原子存档

### 锁定写入协议

正式路径仍为 `user://nk1_save_%d.json`，新增同槽临时与备份路径：

- 临时：`user://nk1_save_%d.tmp`
- 备份：`user://nk1_save_%d.bak`

写入顺序：

1. 序列化到 `.tmp`。
2. `flush()`、关闭文件。
3. 重新读取 `.tmp`，验证 JSON 为 Dictionary、版本有效、核心块存在。
4. 若正式存档存在，将其轮换为 `.bak`；不得先删正式存档。
5. 使用同文件系统 rename 将 `.tmp` 提升为正式文件。
6. 任一步失败：保留最后可读正式存档，清理无效临时文件，`save_completed=false`。

读取顺序：正式文件有效则读取正式文件；正式文件无效且 `.bak` 有效则恢复备份并返回成功；二者均无效才失败。禁止把损坏文件静默解释为空白新档。

### 允许修改路径

- `scripts/autoloads/SaveManager.gd`
- `tools/SaveManagerSelfTest.gd`
- `scripts/systems/TestRunner.gd` 或对应拆分测试文件
- `scripts/TitleScreenController.gd`（仅用于显示“已从备份恢复”等非阻断反馈）

### B1 验收

- [ ] 正常保存/读取与现有行为兼容。
- [ ] 临时写入失败不改变正式存档。
- [ ] 正式 JSON 截断时自动读取 `.bak`。
- [ ] `.bak` 损坏但正式文件正常时不误回退。
- [ ] 旧 v1/v2 存档迁移仍通过。
- [ ] 删除槽位时同时处理正式、临时和备份文件；部分删除失败要明确返回 false。

## 2. 子任务 B2：发布构建

### 新建/修改路径

- 新建 `export_presets.cfg`
- 新建 `tools/verify_release.ps1`
- 新建 `.github/workflows/validate.yml`
- 修改 `.gitignore`：忽略 `build/`，保留源资源及项目约定需要的 `.import` sidecar
- 可修改 `project.godot`：仅发布元数据、图标或渲染兼容设置，不改玩法

### Windows 导出预设

- preset：Windows Desktop，Godot 4.6.3。
- 输出：`build/windows/NanhaiLizhiZhuan.exe`。
- release 构建不得包含 `.godot-tools/`、`.gstack/`、开发日志和本地 diff 文件。
- 导出后必须从 `build/windows/` 启动一次，而非只在编辑器内运行。

### `tools/verify_release.ps1`

脚本必须顺序执行并在任一步失败时返回非零：

1. `validate_project.py`
2. `audit_story_logic.py`
3. `audit_asset_refs.py`
4. Godot editor scan
5. 2019+ 核心断言
6. SaveManager、StoryEventChain、IntentResolver、TaikouSmoke 自测
7. Windows release export
8. 导出包短时启动检查

脚本不得修改剧情、自动提交、自动清理用户工作区或调用破坏性 Git 命令。

### CI

Pull request / push 至主开发分支时运行 1-6；手动 workflow 或 release tag 时追加 7-8 并上传构建产物。Godot 版本必须固定为 4.6.3，不使用浮动 latest。

## 3. 干净构建闸

发布候选提交必须满足：

- 所有运行所需的新 `.gd`、`.tscn`、JSON、图片及项目采用的 `.import` sidecar 已跟踪。
- `git status --short` 中不存在遗漏的运行资源。
- 从新 clone/干净 worktree 执行 `tools/verify_release.ps1` 成功。
- 不要求执行者丢弃或覆盖当前用户改动；应在独立提交或工作树中组织发布候选。

## 4. 非功能要求

- 本地单机存档，不引入加密、账号或云同步。
- 单槽保存耗时目标 `<100ms`（普通桌面 SSD）；不得在主线程做多次大型全盘扫描。
- 最多保留一个 `.bak`，不造存档历史系统。
- CI 失败必须给出具体阶段名和退出码。

## 5. PASS/FAIL

**PASS**：故障注入存档测试、干净构建、导出包启动、完整回归全部通过。  
**FAIL**：只增加 export preset、但无法从干净仓库复现；或保存仍先覆盖正式文件，均退回。

---

_P9-B 完成后，项目才可称“具备发布候选构建链”。_
