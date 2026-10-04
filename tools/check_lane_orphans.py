#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""lane CAS 久不归宿检测（断链预防闸——lane w57-k2 立 · lane 档挂账；w60-k3 升 must 承接执行·形 B 批量化探史）。

立案链：COORDINATION w53-4 SETTLED 行（其行署「CAS fbc7580→e3a7d10 真 ff」）——
SETTLED 毕而其 lane branch 在 wave54→wave57 起派帧曾三波未入主、仍指旧合并基底
（wave57 起派实跑与 main 无映射可判 = 断链型 lane，史上首次 SETTLED 与 branch 未入主
并存超一波）。本闸唯「检测 + 红」，零殓动词——殓权归主控逐案拍。

判红四格全中才算（缺一不红——误红面最小化、历史事实判得准）：
  ① COORDINATION.md 有该 lane 的行首 SETTLED 行（^w 数字-[字母]数字 SETTLED——
     行首带 ISO 时间戳前缀的 2026-… 行不算（属他轨）、SETTLED-ADD / SETTLED-FINAL
     修订行不算、非行首的文内提及不算）；同一 lane 多行 SETTLED 取 **最新一行**
     （下晚的行判案效力最新）；
  ② 行 SHA 证据链自洽：全形（40 位）查主史集 / 短形（7-39 位）按主史 7 位前缀索引拼
     ——祖先=主史包含（形 B 批量化，w60-k3 承办；以下「形 B」）。ancestor=F SHA 若 SETTLED
     行署了未 CAS / 承接 / 收编 / 重链 / 未入主 / CAS 撞窗 / 悬空 / 归 … 轨道 /
     零动 / 殓 / 遗留 类判语 = lane 自报置笔未入主（史实）、闸照样采信不红；只有
     **ancestor=F SHA 且行零判语**（如 w53-10 署 CAS ff 而 main 史无其 SHA = 署名失实）
     才随步 ④ 一拼判红；
  ③ 有在册 branch refs/heads/lane/<lane>-*（SETTLED 但 branch 已殓 = 正常收官
     照桩不红；branch 在册但 SETTLED 行缺失 = 未报收官属他闸域，本闸照桩；
     branch 尖 ancestor=T = 已入主照绿）；
  ④ branch 尖 merge-base --is-ancestor <sha> main rc=1 且
     git rev-list --count main..<sha> > 0（= lane-committed 且 main 尖零含、
     尚无人承接）且 ② 有未释 ancestor=F SHA（行零判语）。

形 B 批量化（w60-k3 承办）：格②③祖先探由「每枚 SHA 一次 git merge-base」改为
一轮 `git rev-list <MAIN_REF>` 建主史集 + 主史 7 位前缀索引（短形一次 dict 拼
40 位全形查集）。缺对对象 = anc=F（**cat-file 补缺防线**：w30-k5 d09d20a 短形叛绿
实锤在案——「对象缺 / 对象在主史零命中」判 anc=F 而非叛绿；判`结果：红`与
merge-base 等价子集）；`git rev-list --count main..<sha>` 格④ ahead 计数照旧。

性能面：生产 6.1-8.7 s 来自 ~1450 次 git merge-base 与 git cat-file 子进程；形 B
走三轮（rev-list 载入一次 + 每行一次 cat-file --batch-check + per-lane for-each-ref +
anc=F branch rev-list --count）≈0.7 s。

读档坑（w60-k3 承办补）：COORDINATION.md 常客写丢（同窗 K3 潮截断）几字 UTF-8
末字节即崩——改 errors='replace'（U+FFFD 代字节）非崩溃绿照红（受损区的字面 SHA /
lane id 不再匹配即「未在册」等效 NULL 语义，其余行判红管道照常；宁缺骨不崩溃）。

环境变量：NK1_COORD（缺省按 git common dir 推主仓同级的 nk1-agent-briefs/COORDINATION.md，
worktree 下不漂）、NK1_MAIN_REF（缺省 main）——自检 / 量具树变异时改指，生产零动。
"""
import os, re, subprocess, sys

MAIN_REF = os.environ.get("NK1_MAIN_REF", "main")

# 行首 lane id + 空白 + SETTLED 前缀行；行首带时间戳 / 修订尾缀的一律不收。
SETTLED_RE = re.compile(r"^(w\d+-[a-z]?\d+)\s+SETTLED")
# 7-40 位十六进 SHA 词——40 位全形优先 + 非十六进字符作界（CJK 字在 Unicode 模式下
# 算 \w、\b 词界断言靠不住）：批忌 = 「223ddd57…f3」40 位串在字母 g 处截 7 位「223ddd5」
# 短形、撞真实存在别名对象（同义 tag）→ anc=T 误判在史（M2 沉默绿实锤）。
ISSHA_RE = re.compile(r"(?<![0-9a-f])(?:[0-9a-f]{40}|[0-9a-f]{7,39})(?![0-9a-f])")
# lane id 形（w53-10）——SHA 似十六进位先过此滤再探史（w\d+-\d+ 如 975-1 撞 ISSHA 批忌）
LANEID_RE = re.compile(r"^w\d+-(?:k)?[a-z]?\d+$")
# lane 自报 ancestor=F 史实的判语关键词（行署其一即采信：置笔未入主是 lane 自己报的、不是断链）
OFFSHA_RE = re.compile(r"未 ?CAS|未入主|收编|重链|承接|CAS.{0,4}撞窗|悬空|归[^，。；）)]{0,14}轨道|零动|殓|遗留")
FAILS = []


def _repo_root():
    # root = 本副本所在 checkout（符号链接 realpath 先行——量具树 symlink 本闸进
    # 某 checkout 即从该 checkout 视帧；生产主树直接落主仓）。worktree 框架下
    # git 反推同落本 checkout、ref 经 commondir 全仓共享。
    real_root = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
    gd = subprocess.run(["git", "-C", real_root, "rev-parse", "--show-toplevel"],
                        capture_output=True, text=True)
    if gd.returncode == 0:
        return os.path.abspath(gd.stdout.strip())
    return real_root


ROOT = _repo_root()  # git 谓词与 COORD 缺省都按本副本 checkout 视帧
COORD = os.environ.get("NK1_COORD") or os.path.abspath(
    os.path.join(ROOT, "..", "nk1-agent-briefs", "COORDINATION.md"))
# 本 checkout 旁无 nk1-agent-briefs 仓（量具树座冷门）时回落主仓旁一帧。
if "NK1_COORD" not in os.environ and not os.path.isfile(COORD):
    _gd = subprocess.run(["git", "-C", ROOT, "rev-parse", "--git-common-dir"],
                         capture_output=True, text=True)
    if _gd.returncode == 0:
        _main_root = os.path.dirname(os.path.abspath(_gd.stdout.strip()))
        _alt = os.path.abspath(os.path.join(_main_root, "..", "nk1-agent-briefs", "COORDINATION.md"))
        if os.path.isfile(_alt):
            COORD = _alt


def _git(*args):
    return subprocess.run(["git", "-C", ROOT] + list(args),
                          capture_output=True, text=True)


# ---------- 形 B：一轮 rev-list 建主史集 + 主史 7 位前缀拼（短形 → 40 位成员一次 set 前继查成） ----------
_MAINSET_CACHE = {}


def _mainset():
    """返回 MAIN_REF 所能抵达全部 commit 的 40 位 SHA 主史集（按 MAIN_REF 置一次；NK1_MAIN_REF 量具变异即换镜重载）。"""
    cache = _MAINSET_CACHE.get("by_ref")
    if cache is not None and cache[0] == MAIN_REF:
        return cache[1]
    r = _git("rev-list", MAIN_REF)
    if r.returncode != 0:
        raise RuntimeError("git rev-list %s rc=%d：%s" % (MAIN_REF, r.returncode, r.stderr[:200]))
    s = set(l.strip() for l in r.stdout.splitlines() if l.strip())
    _MAINSET_CACHE["by_ref"] = (MAIN_REF, s)
    return s


def _is_ancestor(sha):
    """sha 在 MAIN_REF 史（ancestor=T）与否——形 B 语义与 merge-base --is-ancestor 等价：
    全形查主史集；短形按主史 7 位前缀索引拼——913 commit 全零冲突应拼得全形，
    未在索引 = 不在主史直接 anc=F；歧（≥2 拼）保守 anc=F；**对象在主史零命中 =
    anc=F** 与 merge-base 同判（cat-file 补缺防线：w30-k5 d09d20a 短形叛绿实锤——
    「对象缺 / 主史无」判 anc=F 而非叛绿）。"""
    by_long = _mainset()
    if len(sha) == 40:
        return sha in by_long
    return any(s.startswith(sha) for s in by_long)


def _ahead_count(sha):
    cnt = _git("rev-list", "--count", "%s..%s" % (MAIN_REF, sha))
    return int(cnt.stdout.strip() or 0)


def _settled_rows(path):
    """同 lane 多行取最新一行（保序——下晚的行判案效力最新）。

    现帧 w53-3/…r4-r5 同窗 K3 reboot 潮行内多区各丢 2-4 UTF-8 末字节、致生产 strict
    UTF-8 读档 UnicodeDecodeError；本闸判红属情报面事故、不因档案烂尾而崩。
    errors='replace'（U+FFFD）只换掉坏字节、判红管道照常——受损区的字面 SHA /
    lane id 不再匹配，于格②「cat-file 在而未释」类即成 anc=F 拿零协评→行署有判语
    被采信；生产字对字节对已稳定。"""
    seen = {}
    with open(path, encoding="utf-8", errors="replace") as f:
        for ln, line in enumerate(f, 1):
            m = SETTLED_RE.match(line)
            if m:
                seen[m.group(1)] = (ln, line.rstrip("\n"))
    return [(lane, seen[lane][0], seen[lane][1]) for lane in sorted(seen)]


def _obj_exists_batch(sha_list):
    """一轮 git cat-file --batch-check 判一批 SHA 词是否是 commit 对象。返 set(在洞 commit 的 40 位全形)。"""
    if not sha_list:
        return set()
    inputs = "\n".join(s + "^{commit}" for s in sha_list) + "\n"
    r = subprocess.run(["git", "-C", ROOT, "cat-file", "--batch-check"],
                       input=inputs, capture_output=True, text=True)
    if r.returncode != 0:
        # Git 版本老无 --batch-check：退化每件 -e；rev-parse 拼 40 位
        out = set()
        for s in sha_list:
            if _git("cat-file", "-e", s + "^{commit}").returncode == 0:
                v = _git("rev-parse", "--verify", s + "^{commit}").stdout.strip()
                if v:
                    out.add(v)
        return out
    in_main = set()
    for ln in r.stdout.splitlines():
        parts = ln.split()
        if len(parts) >= 3 and parts[1] == "commit":
            in_main.add(parts[0])
    return in_main


def _sha_verdict(text):
    """(offshas 未释清单, shas 全 ancestor=T)——一轮 cat-file --batch-check + 主史集 前缀拼查，ancestor=F 分行署判语二分。"""
    cands = [s for s in dict.fromkeys(ISSHA_RE.findall(text)) if not LANEID_RE.match(s)]
    if not cands:
        return [], True  # 零 SHA 行（纯只读零 commit 正形）照桩
    obj_full = _obj_exists_batch(cands)
    # 短形 s 在 obj_full 中以「前缀拼成员」方式匹配（生产 cat-file -e 的 <s>^{commit}
    # 走短路歧拼——拼得 40 位对象即「对象在」；--batch-check 同）。全形直接查集。
    shas = []
    for s in cands:
        if len(s) < 40:
            matched = any(f.startswith(s) for f in obj_full)
        else:
            matched = s in obj_full
        if matched:
            shas.append(s)
    if not shas:
        return [], True
    offshas = [s for s in shas if not _is_ancestor(s)]
    if not offshas:
        return [], True
    explained = bool(OFFSHA_RE.search(text))
    return ([] if explained else [x[:8] for x in offshas]), False


def main():
    if not os.path.isfile(COORD):
        print("   ✗ COORDINATION 档不存在：%s" % COORD)
        print("结果：1 项问题")
        return 1
    rows = _settled_rows(COORD)
    if not rows:
        FAILS.append("COORDINATION 零行首 SETTLED 行（%s）——档案被删空或格式大变" % COORD)
    for lane, ln, text in rows:
        unexplained, _all_anc = _sha_verdict(text)
        brs = _git("for-each-ref", "refs/heads/lane/%s-*" % lane,
                   "--format=%(refname:short) %(objectname)")
        for line in brs.stdout.splitlines():
            refname, sha = line.split(None, 1)
            if _is_ancestor(sha):
                continue  # 尖在 MAIN_REF 史（或 MAIN_REF 变异即尖自身）——照绿防自咬
            n = _ahead_count(sha)
            if n <= 0:
                continue
            if not unexplained:
                continue  # 行 SHA 链自洽（在史 / zero-SHA / lane 自报置笔未入主）——孤悬 branch 照桩不红
            FAILS.append("lane %s SETTLED（COORDINATION:%d）但行 SHA %s 未入主（ancestor=F）"
                         "且行零未 CAS/承接/收编/重链判语（署名实锤失实）+ branch %s sha %s "
                         "main..count=%d（承接窗断链）"
                         % (lane, ln, ",".join(unexplained), refname, sha[:8], n))
    if FAILS:
        print("结果：%d 项问题" % len(FAILS))
        for m in FAILS:
            print("   ✗ " + m)
        return 1
    print("结果：全部通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
