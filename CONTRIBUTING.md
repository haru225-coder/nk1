# 参与贡献 / Contributing

[中文](#中文) | [English](#english)

## 中文

### 运行

需要 Godot 4.6。用 Godot 打开 `project.godot` 按 F5，或在命令行执行 `godot --path .`。黑屏或贴图变灰叉时，删掉 `.godot/` 后执行 `godot --headless --import --path .`。

### 必须全绿的门禁

一键必跑的门禁共 36 道，完整清单与判据见 [docs/GATES.md](docs/GATES.md)，命令全表见 [docs/开发笔记.md](docs/开发笔记.md)。提交前至少跑：

```bash
python3 tools/check_symbols.py
python3 tools/verify_economy.py
python3 tools/simulate_run.py
python3 tools/verify_story_data.py
python3 tools/check_sidecars.py
python3 tools/gates_md.py
godot --headless --import --path .
godot --headless --path . -s res://tools/godot_smoke.gd
godot --headless --path . -s res://tools/godot_compile_check.gd
godot --headless --path . -s res://tools/godot_story_check.gd
```

只改了文档时，跑 `python3 tools/check_docs_index.py` 和 `python3 tools/gates_md.py`。

### 提交约定

- 提交信息沿用仓库现有格式：`类型(范围): 说明`，类型如 `feat` / `fix` / `docs` / `chore`，说明写清改了什么、为什么。例：`fix(lane-w54-seaevents): 「献上买路财」钮上写出要花多少钱`。
- 新增脚本或素材时，把 Godot 生成的 `.uid` / `.import` 一起提交；用明确的路径 `git add`，不要 `git add .`。
- 在 `docs/` 下新增文档时，在 [docs/README.md](docs/README.md) 补一行索引。
- 不要 force-push 到 `main`。

### Issue

欢迎报告 Bug、史实错误、文案问题和平衡性问题。请写明：Godot 版本、操作系统、复现步骤（第几章、哪个港口、做了什么）、预期与实际结果；有截图或存档（`user://saves/`）更好。

## English

### Running

You need Godot 4.6. Open `project.godot` in Godot and press F5, or run `godot --path .`. If you see a black screen or grey placeholder textures, delete `.godot/` and run `godot --headless --import --path .`.

### Gates that must be green

There are 36 required gates. [docs/GATES.md](docs/GATES.md) lists each one and what it checks, and [docs/开发笔记.md](docs/开发笔记.md) has the full command list (both in Chinese). Before submitting, run at least the commands in the block above.

For documentation-only changes, run `python3 tools/check_docs_index.py` and `python3 tools/gates_md.py`.

### Commit style

- Follow the existing format: `type(scope): description`, where type is `feat`, `fix`, `docs`, `chore` and so on, and the description says what changed and why.
- When you add scripts or assets, commit the `.uid` / `.import` files Godot generates with them. Stage explicit paths instead of `git add .`.
- When you add a document under `docs/`, add a line for it in [docs/README.md](docs/README.md).
- Never force-push to `main`.

### Issues

Bug reports, historical corrections, writing fixes and balance feedback are all welcome. Please include your Godot version, OS, steps to reproduce (chapter, port, what you did), and what you expected versus what happened. Screenshots or a save file (`user://saves/`) help a lot.

Licensing: code is MIT ([LICENSE](LICENSE)); assets are covered by [ASSETS.md](ASSETS.md). By contributing you agree your code contributions are released under the MIT License.
