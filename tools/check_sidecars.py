#!/usr/bin/env python3
"""Godot 侧车门禁（lane ag / ag2）：侧车必须跟源文件同进同出，且内容与源文件、引用、基线一致。
起因：lane un（7562e69）一次清出 71 项已跟踪源文件缺的 *.uid / *.import 积压——各 lane 提交源文件时
按旧口径「跳过 *.uid/*.import」，侧车就一直漂在工作树里；别处一 clone 会重新生成随机 uid，场景 uid:// 引用断链。

口径（全表与实测依据见 docs/侧车口径.md；旧口径「提交时跳过 *.uid/*.import」只指下表「不入库」三行）：
  侧车                                       入库？  谁提交
  本 lane 新增的 .gd/.gdshader → <文件>.uid    必须    同一 commit 带上（编辑器扫一遍生成，别手写）
  本 lane 新增的素材 → <素材>.import           必须    同一 commit 带上
  本 lane 有意改导入参数 / 换源图 → .import     必须    同一 commit 带上
  挪 / 删源文件 → 旧侧车                        删/挪   同一 commit（git mv 连侧车一起）
  编辑器顺手改写的、源文件没动的已跟踪侧车      不入库  git checkout -- 还原（本门禁「工作树漂移」判红）
  别的 lane 留在共享工作树里的未跟踪侧车        不入库  归源文件所属 lane / 补缺小片，别夹带
  .godot/ 下的导入产物、uid_cache、*.translation 不入库  .gitignore 已忽略
VRAM 纹理（compress/mode=2）的 [remap] 基线 = 桌面 s3tc_bptc 一种；project.godot 打开
rendering/textures/vram_compression/import_etc2_astc 后基线变为 s3tc_bptc + etc2_astc 两种。
4.5.2 / 4.6.2 / 4.6.3 / 4.7.2 x86_64 实测都不改写基线；ARM 主机导入会写出 etc2 分支——那是第二种形态，不许入库。

只看 git 索引（`git ls-files`，已暂存也算已跟踪），工作树里未跟踪的文件不查：
  1. 每个已跟踪的 *.gd / *.gdshader 必须有已跟踪的 `<文件>.uid`
  2. 每个已跟踪的可导入素材（图 / 音 / 字体 / 模型 / csv）必须有已跟踪的 `.import`
  3. 反向：已跟踪的 `.uid` / `.import` 必须有已跟踪的源文件（不许只提侧车）
  4. 多余侧车：源文件那一类 Godot 根本不生成该侧车（如 .tscn.uid、.json.import）
  5. 内容（读索引里的 blob）：.uid 须是一行 `uid://…`；.import 的 source_file 须指向自身源文件，
     .godot/imported/ 产物名须是 `<文件名>-<md5(res://路径)>.`（源文件挪过 / 拷过没重导会对不上）；
     VRAM 纹理的 imported_formats / path.* / dest_files 须互相一致且等于上面的基线
  6. uid 全仓唯一（.uid、.import、.tscn/.tres 头）；.tscn/.tres 的 ext_resource 写了 uid 的，须等于目标侧车里的 uid
另查工作树（`--index-only` 跳过）：
  7. 已跟踪侧车在工作树里被改写 / 删掉 = 工作树漂移
Godot 不扫的地方不查：带 `.gdignore` 的目录及其子目录、以 `.` 开头的目录/文件（与编辑器文件系统同口径）。
"""
import hashlib, os, re, subprocess, sys
if "--json" in sys.argv[1:]:  # 机读输出，见 docs/GATES.md；不带开关不进此支，原行为不变
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import gate_json; gate_json.maybe_json(__file__)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UID_SRC = (".gd", ".gdshader")
IMPORT_SRC = (
    ".png", ".jpg", ".jpeg", ".webp", ".svg", ".bmp", ".tga", ".exr", ".hdr", ".dds", ".ktx",
    ".wav", ".ogg", ".mp3",
    ".ttf", ".otf", ".woff", ".woff2", ".fnt", ".font",
    ".glb", ".gltf", ".obj", ".fbx", ".blend", ".dae",
    ".csv",
)
# imported_formats 名 → [remap] 里的 path.<后缀>
VRAM_KEY = {"s3tc_bptc": "s3tc", "etc2_astc": "etc2"}
INDEX_ONLY = "--index-only" in sys.argv[1:]
FAIL = []


def git(*args, inp=None):
    return subprocess.run(["git", "-C", ROOT, *args], check=True, capture_output=True, input=inp).stdout


try:
    out = git("ls-files", "-s", "-z")
except (OSError, subprocess.CalledProcessError) as e:
    print("FAIL: git ls-files 跑不起来，无法判定已跟踪文件：", e)
    print("结果：1 项失败")
    sys.exit(1)
sha = {}
for rec in out.decode("utf-8").split("\0"):
    if rec:
        meta, p = rec.split("\t", 1)
        sha[p] = meta.split()[1]
tracked = set(sha)

ignored_dirs = {os.path.dirname(p) for p in tracked if os.path.basename(p) == ".gdignore"}


def godot_sees(p):
    parts = p.split("/")
    if any(s.startswith(".") for s in parts):
        return False
    d = os.path.dirname(p)
    while d:
        if d in ignored_dirs:
            return False
        d = os.path.dirname(d)
    return "" not in ignored_dirs


def blobs(paths):
    """一次 cat-file --batch 读出索引里这些路径的内容。"""
    paths = list(paths)
    raw = git("cat-file", "--batch", inp="".join(sha[p] + "\n" for p in paths).encode())
    res, i = {}, 0
    for p in paths:
        j = raw.index(b"\n", i)
        size = int(raw[i:j].split()[2])
        res[p] = raw[j + 1:j + 1 + size].decode("utf-8", "replace")
        i = j + 1 + size + 1
    return res


def parse_import(text):
    """.import 是 ConfigFile：只取顶层 key=value（值可能跨行，如 metadata={…}）。"""
    sec, cur, d = None, None, {}
    for line in text.splitlines():
        if re.match(r"^\[[^\]]+\]$", line):
            sec, cur = line[1:-1], None
            continue
        m = re.match(r"^([A-Za-z0-9_/.]+)=(.*)$", line)
        if m and sec:
            cur = (sec, m.group(1))
            d[cur] = m.group(2)
        elif cur:
            d[cur] += "\n" + line
    return d


def etc2_enabled():
    if "project.godot" not in tracked:
        return False
    txt = blobs(["project.godot"])["project.godot"]
    sec = None
    for line in txt.splitlines():
        if line.startswith("["):
            sec = line.strip()
        elif sec == "[rendering]" and line.replace(" ", "").startswith("textures/vram_compression/import_etc2_astc="):
            return line.split("=", 1)[1].strip() == "true"
    return False


# ── 1–4：成对与多余 ──
n_uid = n_imp = n_side = 0
sidecars = []
for p in sorted(tracked):
    if not godot_sees(p):
        continue
    low = p.lower()
    if low.endswith(UID_SRC):
        n_uid += 1
        if p + ".uid" not in tracked:
            FAIL.append(f"{p} 已跟踪，缺已跟踪的 {os.path.basename(p)}.uid")
    elif low.endswith(IMPORT_SRC):
        n_imp += 1
        if p + ".import" not in tracked:
            FAIL.append(f"{p} 已跟踪，缺已跟踪的 {os.path.basename(p)}.import")
    elif low.endswith((".uid", ".import")):
        n_side += 1
        src = p[: p.rfind(".")]
        kinds = UID_SRC if low.endswith(".uid") else IMPORT_SRC
        if not src.lower().endswith(kinds):
            FAIL.append(f"{p} 是多余侧车：{os.path.splitext(src)[1] or '无扩展名'} 文件 Godot 不生成 {p[p.rfind('.'):]}")
        elif src not in tracked:
            FAIL.append(f"{p} 已跟踪，但源文件 {src} 未跟踪（只提侧车不提源）")
        else:
            sidecars.append(p)

# ── 5–6：内容 ──
scenes = [p for p in tracked if godot_sees(p) and p.endswith((".tscn", ".tres"))]
content = blobs(sidecars + scenes)
want_vram = {"s3tc_bptc"} | ({"etc2_astc"} if etc2_enabled() else set())
uid_of, uid_owner, n_vram = {}, {}, 0


def own_uid(p, uid):
    if uid in uid_owner:
        FAIL.append(f"{p} 的 {uid} 与 {uid_owner[uid]} 重复（拷文件连侧车一起拷了？删掉拷来的侧车让编辑器重生成）")
    else:
        uid_owner[uid] = p


for p in sidecars:
    src, text = p[: p.rfind(".")], content[p]
    if p.endswith(".uid"):
        m = re.fullmatch(r"(uid://[0-9a-z]+)\n?", text)
        if not m:
            FAIL.append(f"{p} 内容坏：须是一行 uid://…，实为 {text[:40]!r}（删掉让编辑器重生成，别手写）")
            continue
        uid_of[src] = m.group(1)
        own_uid(p, m.group(1))
        continue
    d = parse_import(text)
    uid = d.get(("remap", "uid"), "").strip('"')
    if uid:
        uid_of[src] = uid
        own_uid(p, uid)
    sf = d.get(("deps", "source_file"), "").strip('"')
    if sf != "res://" + src:
        FAIL.append(f"{p} 内容漂移：source_file={sf or '缺'}，应为 res://{src}（源文件挪过没重导）")
    stem = f"{os.path.basename(src)}-{hashlib.md5(('res://' + src).encode()).hexdigest()}."
    paths = {k[1]: v.strip('"') for k, v in d.items() if k[0] == "remap" and k[1].split(".")[0] == "path"}
    dests = re.findall(r'"([^"]+)"', d.get(("deps", "dest_files"), ""))
    bad = sorted({q for q in list(paths.values()) + dests
                  if q.startswith("res://.godot/imported/") and not os.path.basename(q).startswith(stem)})
    if bad:
        FAIL.append(f"{p} 内容漂移：导入产物名不是 {stem}…（{bad[0]}；源文件挪过 / 拷过没重导）")
    if d.get(("params", "compress/mode")) == "2":
        n_vram += 1
        meta = d.get(("remap", "metadata"), "")
        fmts = set(re.findall(r'"([a-z0-9_]+)"', re.search(r'"imported_formats":\s*\[([^\]]*)\]', meta).group(1))) \
            if '"imported_formats"' in meta else set()
        keys = {k.split(".", 1)[1] for k in paths if "." in k}
        if '"vram_texture": true' not in meta or "path" in paths:
            FAIL.append(f"{p} 内容漂移：compress/mode=2（VRAM）但 [remap] 不是 VRAM 形态（vram_texture:false / 单一 path=）")
        elif keys != {VRAM_KEY.get(f, f) for f in fmts} or set(dests) != set(paths.values()):
            FAIL.append(f"{p} 内容漂移：imported_formats {sorted(fmts)} 与 path.* {sorted(keys)} / dest_files 对不上")
        elif fmts != want_vram:
            FAIL.append(f"{p} 不是基线形态：imported_formats {sorted(fmts)}，基线 {sorted(want_vram)}"
                        "（基线随 project.godot 的 import_etc2_astc 定；ARM / 移动端导入写出的 etc2 分支别提交；见 docs/侧车口径.md）")

for p in sorted(scenes):
    text = content[p]
    m = re.search(r'^\[gd_[a-z]+ [^\]]*\buid="(uid://[0-9a-z]+)"', text, re.M)
    if m:
        own_uid(p, m.group(1))
    for ext in re.findall(r"^\[ext_resource [^\]]*\]", text, re.M):
        u, t = re.search(r'\buid="([^"]+)"', ext), re.search(r'\bpath="res://([^"]+)"', ext)
        if u and t and t.group(1) in uid_of and uid_of[t.group(1)] != u.group(1):
            FAIL.append(f"{p} 引用 {t.group(1)} 写的 {u.group(1)}，侧车里是 {uid_of[t.group(1)]}（侧车漂了或引用手写）")

# ── 7：工作树漂移 ──
n_drift = 0
if not INDEX_ONLY:
    for p in git("diff", "--name-only", "-z").decode("utf-8").split("\0"):
        if p.endswith((".uid", ".import")) and godot_sees(p):
            n_drift += 1
            gone = not os.path.exists(os.path.join(ROOT, p))
            FAIL.append(f"{p} 工作树漂移：{'被删' if gone else '与已跟踪版本不同'}（本 lane 有意改动就一并提交，"
                        f"否则 git checkout -- {p}；换 Godot 版本 / 平台后成片出现 = 基线变了，见 docs/侧车口径.md）")

print("=" * 68)
if FAIL:
    for f in FAIL:
        print("FAIL:", f)
    print(f"结果：{len(FAIL)} 项失败")
    sys.exit(1)
print(f"脚本/着色器 {n_uid} 个都有 .uid · 素材 {n_imp} 个都有 .import · 侧车 {n_side} 个都有源文件")
print(f"内容：uid {len(uid_owner)} 个唯一 · 导入路径与源文件一致 · VRAM 纹理 {n_vram} 张为基线 {'+'.join(sorted(want_vram))}"
      + (" · 工作树未查（--index-only）" if INDEX_ONLY else " · 工作树侧车无漂移"))
print("结果：全部通过")
