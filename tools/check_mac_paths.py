#!/usr/bin/env python3
"""RefsMacPath（lane doc9）：仓库里不许再写 Mac / Homebrew 专属的绝对路径，防 lane doc7 / doc8 / gd13 清掉的又写回来。

  python3 tools/check_mac_paths.py          # 自检；有问题退 1
  python3 tools/check_mac_paths.py --json   # 机读（同 docs/GATES.md §二）

扫什么：git 已跟踪的全部文本文件（读工作树里的内容，已暂存的新文件也算；含 NUL 字节的二进制跳过）。
本脚本自身也扫（lane gd21）：只按行排除下面 `PATTERNS = [` 到 `]` 之间的条目行（它们本身就是命中），块外照常判；
块里每行须是一条 `("名字", r"正则", "理由")`、行数与条目数相等，夹进别的行（注释 / 字符串）即判红，免得拿它藏路径。
`SAMPLES = [` 块同样按行排除（lane auditfix2），块里每行须是一条 `r"样本行"`。
模式逐条写了为什么算 Mac 专属。
判红：
  · 零、模式自检（lane auditfix2，每次跑都先过）：SAMPLES 有一行没被认出（含独立审计原反例两行：家目录写成 $HOME 的资料库目录、
    Intel Homebrew 的 opt 目录，修前 rc=0），或 CLEAN 有一行被误认，即判红——模式表回退 / 改窄了在这里先红，不等真文件写进来；
  · 不在 ALLOW 里的文件有命中（修法：改成 env / PATH / 仓库相对路径，见 build_ui_textures 的 NK1_RSVG、tour.sh 的 GODOT）；
  · ALLOW 里的文件命中行数 ≠ 登记的 lines（多了 = 往留档里又加了；少了 = 清掉了几处，条目跟着改）；
  · ALLOW 条目的 keep 字样不在文件头 5 行里（「勿运行」横幅 / 历史回指注被删，留档就不再算已定级）；
  · ALLOW 条目的文件不在或不再跟踪（失效条目，删掉）。
工作树里未跟踪的文件（别的 lane 还没提交的）有命中只记 ⚠、不判红，与 check_docs_index 同口径；git 不可用时退回扫盘。
不算 Mac 路径、不在此列：`~/tmp/…` 草稿区（两机通用）、`snowchan27-NN` 走查署名、`brew install …` 安装提示、下载 URL 里的 `macos` 字样。
"""
import os, re, subprocess, sys

TOOLS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS)
if "--json" in sys.argv[1:]:  # 机读输出，见 docs/GATES.md；不带开关不进此支，原行为不变
    sys.path.insert(0, TOOLS)
    import gate_json; gate_json.maybe_json(__file__)

SELF = "tools/check_mac_paths.py"
HEAD_LINES = 5

# (名字, 正则, 为什么算 Mac 专属)
PATTERNS = [
    ("/Users/", r"/Users/", "Mac 用户家目录（Linux 是 /home/）"),
    ("/opt/homebrew", r"/opt/homebrew\b", "Apple Silicon 上 Homebrew 的前缀"),
    ("/usr/local/Cellar|Homebrew|Caskroom|opt", r"/usr/local/(?:Cellar|Homebrew|Caskroom|opt)\b", "Intel Mac 上 Homebrew 的前缀与装包目录（opt 是各包的稳定软链，lane auditfix2 补）"),
    ("Godot.app", r"Godot[\w.-]*\.app\b", "Mac 版 Godot 应用包"),
    ("*.app/Contents/", r"\.app/Contents/", "Mac 应用包内部路径"),
    ("/Applications/", r"/Applications/", "Mac 应用目录"),
    ("~ / $HOME / ${HOME}/Library", r"(?:~|\x22?\$(?:HOME\b|\{HOME(?::?[-=?+][^}]*)?\})\x22?)/Library\b|(?:home\(\)\s*/\s*|join\([^)]*)[\x22']Library\b|Library/Application Support", "Mac 用户资料目录，家目录写成 ~ / $HOME / ${HOME} / Path.home() 拼接都算（lane auditfix2 补后几种；Godot user:// 在 Linux 是 ~/.local/share/godot/）"),
    ("/Volumes/", r"/Volumes/", "Mac 外接卷挂载点"),
    ("/private/tmp|var", r"/private/(?:tmp|var)/|/var/folders/", "Mac 的临时目录"),
    ("~/Projects/", r"~/Projects/", "09-03 前 Mac 旧机的仓库位置（~/Projects/app/nk-1）"),
]
PAT = re.compile("|".join(f"(?:{p})" for _, p, _ in PATTERNS))

# 模式自检（lane auditfix2）：每次跑都先过「零」——下面每行都须被 PATTERNS 认出，漏认即判红（模式表回退 / 改窄了）。
# 头两行是独立审计「未做实清单 #3」的原反例（往 tools/art/tour.sh 追加这两行，修前 rc=0）。
# 本块同 PATTERNS 块按行排除自扫：块里每行须是一条 r"样本行"，且每行都得命中，所以塞不进漏网的路径。
SAMPLES = [
    r"GODOT=$HOME/Library/Godot",
    r"export P=/usr/local/opt/foo",
    r"GODOT=${HOME}/Library/Godot",
    r"cp save.json ${HOME:-/tmp}/Library/Preferences/",
    r'cd "$HOME"/Library/Caches',
    r"ls ~/Library/Logs",
    r"USERDATA = Path.home() / 'Library' / 'Application Support'",
    r"os.path.join(os.environ['HOME'], 'Library', 'Fonts')",
    r"export PATH=/usr/local/Cellar/godot/4.6/bin:$PATH",
    r"/usr/local/opt/librsvg/bin/rsvg-convert in.svg",
    r"/usr/local/Homebrew/bin/brew",
    r"/opt/homebrew/bin/rsvg-convert",
    r"/Applications/Godot.app/Contents/MacOS/Godot --path .",
]
# 反向样本：须不命中（误报即判红）。docstring 末尾「不算 Mac 路径」那几类 + 本仓库里真有的相近写法。
CLEAN = [
    "RUN=$HOME/tmp/nk1-art-cloud-run-port",
    "codex = ${HOME}/tmp/nk1-codex/assets",
    "${HOME_RATE}/Library",
    "默认 ~/tmp/nk1-codex/assets/portraits",
    "GODOT_BIN=\"/usr/local/bin/godot\"",
    "/usr/local/optional/thing",
    "~/.local/share/godot/app_userdata/nk1/saves",
    "HOME_TMP = pathlib.Path.home() / \"tmp\"",
    "brew install librsvg",
    "const HOME_RATE := 5",
    "MyLibrary/notes.md",
]

# 已定级、允许留着的命中：file → lines（命中行数，须相等）、keep（须在文件头 HEAD_LINES 行里的字样）、why（理由）。
# 要加条目先想清楚能不能改掉；lane doc7 的口径：活跃脚本 / 文档一律改成本机口径，只有留档与带日期的历史稿可以进这里。
LEGACY_WHY = "tools/legacy 早期一次性补丁，lane doc7 定级加了「勿运行」横幅；路径原样留着是为了查来历（改掉反而像是能跑）"
ALLOW = {
    "tools/legacy/fix_baseloc.py": {"lines": 3, "keep": "【历史留档，勿运行】", "why": LEGACY_WHY},
    "tools/legacy/fix_font.py": {"lines": 3, "keep": "【历史留档，勿运行】", "why": LEGACY_WHY},
    "tools/legacy/migrate_data.py": {"lines": 3, "keep": "【历史留档，勿运行】", "why": LEGACY_WHY},
    "tools/legacy/patch_investigation.py": {"lines": 3, "keep": "【历史留档，勿运行】", "why": LEGACY_WHY},
    "tools/legacy/patch_shipyard.py": {"lines": 3, "keep": "【历史留档，勿运行】", "why": LEGACY_WHY},
    "docs/云端优先合并台账_2026-09-25.md": {
        "lines": 2, "keep": "历史台账，环境指 09-25 的 Mac 旧机",
        "why": "带日期的历史台账，正文不改（lane doc7）；头注本身点名旧机的用户数据目录并给出本机口径，§四「环境备忘」原文一处"},
    "docs/nk-1双线融合方案_2026-09-03.md": {
        "lines": 2, "keep": "历史稿，非当前 main",
        "why": "带日期的历史稿，正文不改；lane doc2 头注本身点名旧仓库位置并说明文中路径指 09-03 的旧树，第 8 行「两棵树」原文一处"},
}

fails = []


# 自扫按行排除的块：块名 → (块里每行须全匹配的形状, 形状的人话, 条目数)
SELF_BLOCKS = {
    "PATTERNS": (r'    \("[^"]*", r"[^"]*", "[^"]*"\),', '("名字", r"正则", "理由")', len(PATTERNS)),
    "SAMPLES": (r"""    r(?:"[^"]*"|'[^']*'),""", 'r"样本行"', len(SAMPLES)),
}


def self_block(name):
    """本脚本 name 块（PATTERNS / SAMPLES）里条目行的行号集合（按行排除用）；块找不到 / 形状不对 → (None, 原因)。"""
    shape, human, count = SELF_BLOCKS[name]
    with open(os.path.join(ROOT, SELF), encoding="utf-8", errors="replace") as f:
        lines = f.read().splitlines()
    starts = [i for i, ln in enumerate(lines) if ln == f"{name} = ["]
    if len(starts) != 1:
        return None, f"`{name} = [` 行有 {len(starts)} 处（须恰 1 处）"
    a = starts[0]
    b = next((i for i in range(a + 1, len(lines)) if lines[i] == "]"), None)
    if b is None:
        return None, f"`{name} = [` 之后找不到收尾的 `]` 行"
    inner = range(a + 1, b)
    odd = [i + 1 for i in inner if not re.fullmatch(shape, lines[i])]
    if odd:
        return None, f"块里第 {'、'.join(map(str, odd))} 行不是一条 {human}"
    if len(inner) != count:
        return None, f"块里 {len(inner)} 行，{name} {count} 条（须一条一行）"
    return {i + 1 for i in inner}, None


def pattern_selftest():
    """「零」：SAMPLES 每行须命中、CLEAN 每行须不命中；原反例两行整段过一遍 hits_text（与扫文件同一条路）。"""
    def who(ln):
        return "、".join(n for n, p, _ in PATTERNS if re.search(p, ln)) or "无"
    missed = [ln for ln in SAMPLES if not PAT.search(ln)]
    check(not missed, f"正向样本 {len(SAMPLES)} 行都被认出（{len(PATTERNS)} 条模式）"
          + ("" if not missed else "；漏认：" + " | ".join(missed)))
    false = [ln for ln in CLEAN if PAT.search(ln)]
    check(not false, f"反向样本 {len(CLEAN)} 行都不命中（~/tmp 草稿区、/usr/local/bin、HOME_RATE 等）"
          + ("" if not false else "；误报：" + " | ".join(f"{ln} ← {who(ln)}" for ln in false)))
    audit = "\n".join(SAMPLES[:2]) + "\n"
    got = [n for n, _ in hits_text(audit)]
    check(got == [1, 2], f"独立审计原反例（追加到 tools/art/tour.sh 的两行）整段扫出 {len(got)}/2 行"
          + "（" + "；".join(f"{ln} ← {who(ln)}" for ln in SAMPLES[:2]) + "）")


def check(cond, msg):
    print(("  ✓ " if cond else "  ✗ ") + msg)
    if not cond:
        fails.append(msg)
    return cond


def repo_files():
    """(已跟踪, 未跟踪未忽略) 的文件，路径相对仓库根。"""
    def git(*args):
        p = subprocess.run(["git", *args, "-z"], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=True)
        return [f for f in p.stdout.decode("utf-8").split("\0") if f]
    try:
        return git("ls-files"), git("ls-files", "--others", "--exclude-standard")
    except (OSError, subprocess.CalledProcessError):
        skip = {".git", ".godot", "__pycache__"}
        out = []
        for d, ds, fs in os.walk(ROOT):
            ds[:] = [x for x in ds if x not in skip]
            out += [os.path.relpath(os.path.join(d, f), ROOT).replace(os.sep, "/") for f in fs]
        return sorted(out), []


def hits(rel):
    """[(行号, 行)]；读不到 / 二进制 → None。"""
    try:
        with open(os.path.join(ROOT, rel), "rb") as f:
            raw = f.read()
    except OSError:
        return None
    if b"\0" in raw:
        return None
    return hits_text(raw.decode("utf-8", errors="replace"))


def hits_text(text):
    return [(n, ln) for n, ln in enumerate(text.splitlines(), 1) if PAT.search(ln)]


def show(rel, hs, limit=6):
    for n, ln in hs[:limit]:
        m = PAT.search(ln)
        print(f"      {rel}:{n}  {ln.strip()[:140]}" + (f"  ← {m.group(0)}" if m else ""))
    if len(hs) > limit:
        print(f"      …另 {len(hs) - limit} 行")


def main(argv):
    unknown = [a for a in argv if a not in ("--check",)]
    if unknown:
        print(__doc__)
        print(f"未知参数：{' '.join(unknown)}", file=sys.stderr)
        return 2
    tracked, untracked = repo_files()
    tset = set(tracked)

    print("零、模式自检（lane auditfix2：模式表回退 / 改窄了在这里先红）")
    pattern_selftest()

    print("一、白名单条目都有效")
    for rel, a in ALLOW.items():
        if not os.path.isfile(os.path.join(ROOT, rel)) or rel not in tset:
            check(False, f"{rel}：失效条目（文件挪走 / 删了 / 没跟踪），从 ALLOW 删掉")
            continue
        with open(os.path.join(ROOT, rel), encoding="utf-8", errors="replace") as f:
            head = "".join(f.readline() for _ in range(HEAD_LINES))
        check(a["keep"] in head, f"{rel}：已跟踪，头 {HEAD_LINES} 行有「{a['keep']}」"
              + ("" if a["keep"] in head else "——找不到（横幅 / 回指注被删，留档不再算已定级：补回去，或把路径改掉再删条目）"))

    print(f"二、git 已跟踪文件里的 Mac 路径（模式 {len(PATTERNS)} 条：{'、'.join(n for n, _, _ in PATTERNS)}）")
    scanned = 0
    stray = []
    for rel in tracked:
        hs = hits(rel)
        if hs is None:
            continue
        if rel == SELF:  # 自扫：按行排除 PATTERNS / SAMPLES 条目行，块外的照常算（lane gd21 / auditfix2）
            for name in SELF_BLOCKS:
                block, why = self_block(name)
                if check(block is not None, f"{SELF}：自扫按行排除 {name} 块 {len(block or ())} 行"
                         + ("" if block is not None else f"——{why}；整份照扫")):
                    hs = [h for h in hs if h[0] not in block]
        scanned += 1
        a = ALLOW.get(rel)
        if a is None:
            if hs:
                stray.append((rel, hs))
            continue
        if not check(len(hs) == a["lines"], f"{rel}：命中 {len(hs)} 行，登记 {a['lines']} 行（{a['why']}）"
                     + ("" if len(hs) == a["lines"] else "；多了 = 留档里又加了路径，少了 = 条目 lines 跟着改")):
            show(rel, hs)
    for rel, hs in stray:
        check(False, f"{rel}：{len(hs)} 行 Mac 专属路径，不在白名单（改成 env / PATH / 仓库相对路径）")
        show(rel, hs)
    check(not stray, f"白名单外 {sum(len(h) for _, h in stray)} 处命中（扫 {scanned} 个已跟踪文本文件，含本脚本、其 PATTERNS / SAMPLES 块除外）"
          + (f"：{len(stray)} 个文件" if stray else ""))

    for rel in untracked:
        hs = hits(rel) if rel != SELF else None
        if hs:
            print(f"  ⚠ 未跟踪：{rel} 有 {len(hs)} 行 Mac 专属路径（不判红；提交前改掉，否则跟踪后即红）")
            show(rel, hs, 3)
    return report()


def report():
    print()
    print("结果：全部通过" if not fails else f"结果：{len(fails)} 项问题")
    for m in fails:
        print("   ✗ " + m.splitlines()[0])
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
