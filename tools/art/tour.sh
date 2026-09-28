#!/bin/bash
# 巡检截帧：对给定站点逐个跑 res://tools/art/ShotTour.tscn（Movie Maker，10 fps，1280×720），
# 每站输出 <输出根>/<站点>/f00000000.png…、last.png（最后一帧原图）、sheet.jpg（带帧号小样）、log.txt。
# last.png / sheet.jpg 由 tools/art/tour_sheet.gd 用 Godot 拼（lane pg5；原 python3 + PIL，本机没装就出不了）——只要 Godot，不要 Python。
#
# 用法：tools/art/tour.sh [-n 每站帧数] [-r 运行副本] [-o 输出根] [站点…]
#   -n  默认 30（3 秒；站点一般第 8–12 帧就位，之后画面静止）
#   -r  运行副本目录，默认 ~/tmp/nk1-art-cloud-run-port（须先拷一份仓库——rsync / `git archive HEAD | tar -x -C <副本>` 皆可——
#       并在副本里 godot --headless --editor --quit 导入过一次）
#   -o  输出根，默认 ~/tmp/nk1-art-work/tour；设了环境变量 NK1_SHOT_DIR 则默认改为 <该目录>/tour（-o 仍优先；相对路径按 $PWD 展开，lane pg4）
#   GODOT 环境变量指定引擎；缺省取 PATH 里的 godot，都没有退 2（lane gd13 去掉 Mac 旧位置的 .app 兜底）
#   无窗口的机器要给 DISPLAY（Movie Maker 要真渲染，不能 --headless）
#   站点缺省 = 下面 ALL（基础站点全集）；另可给 cutscene_<id> / chapter_card_<n> / banner_<port> 等，见 ShotTour.gd 的 SITES。
#   过场接线站点（cinematics 线，走 Main 真实流程，时长长，按需给 -n）：cutscene_opening（开机开场）、chapter_card_<n>、
#   banner_<港>（海图回港横幅）、ending_cs_<结局>（结局过场 + 结算册页）、title_anim（标题演出；TOUR_ARGS="--rewatch" 看重看开场）。
#   额外参数：环境变量 TOUR_ARGS 原样追加在 -- 之后（如 TOUR_ARGS="--shot=3"）。
# 一次只开一个 Godot 进程（逐站串行）。本脚本只读运行副本，不改仓库。
# 输出契约（lane gd13；不算门禁，理由见 docs/GATES.md §一「不算门禁」，机读走 `python3 tools/gate_json.py -- tools/art/tour.sh …`）：
#   每站一行 `✓ <站点> rc= frames= errors= <TOUR_READY…>`（✗ 行尾另注红因），末行 `TOUR PASS n/n` / `TOUR FAIL k/n`；
#   一站红 = 引擎退出码非 0 / 未打 TOUR_READY / 报错计数非 0 / 一帧没出 / 小样（last.png、sheet.jpg）没出。
#   退出码：全绿 0、有站红 1、用法错 / 运行副本不在 / 找不到引擎 2。
set -u
GODOT=${GODOT:-$(command -v godot)}
HERE=$(cd "$(dirname "$0")" && pwd)
N=30
RUN=$HOME/tmp/nk1-art-cloud-run-port
OUT=$HOME/tmp/nk1-art-work/tour
if [ -n "${NK1_SHOT_DIR:-}" ]; then
  OUT=$NK1_SHOT_DIR/tour
  case $OUT in /*) ;; *) OUT=$PWD/$OUT ;; esac
fi
while getopts "n:r:o:" opt; do
  case $opt in
    n) N=$OPTARG ;;
    r) RUN=$OPTARG ;;
    o) OUT=$OPTARG ;;
    *) echo "用法：$0 [-n 帧数] [-r 运行副本] [-o 输出根] [站点…]"; exit 2 ;;
  esac
done
shift $((OPTIND - 1))
ALL=(title port_quanzhou tavern_quanzhou
     npc_merchant_lin npc_pilot_ana npc_customs_official npc_monk_jinghai
     chapter_dialog chapter_dialog_2 chapter_dialog_3
     ending_zhongsu ending_weigui ending_sea_ghost ending_pu_ship ending_gangshou ending_root
     ending_sea_letter ending_ledger_distance ending_history_wind ending_south_sea
     seachart)
[ $# -eq 0 ] && set -- "${ALL[@]}"
[ -f "$RUN/project.godot" ] || { echo "运行副本不在：$RUN"; exit 2; }
[ -n "$GODOT" ] || { echo "找不到 godot：PATH 里没有，设 GODOT=<引擎路径>"; exit 2; }
mkdir -p "$OUT"
fail=0
for site in "$@"; do
  why=()
  d="$OUT/$site"
  rm -rf "$d"; mkdir -p "$d"
  # shellcheck disable=SC2086
  perl -e 'alarm 240; exec @ARGV' "$GODOT" --path "$RUN" --write-movie "$d/f.png" --fixed-fps 10 \
    --quit-after "$N" --resolution 1280x720 res://tools/art/ShotTour.tscn -- --tour="$site" ${TOUR_ARGS:-} \
    > "$d/log.txt" 2>&1
  rc=$?
  ready=$(grep -m1 -o 'TOUR_READY.*' "$d/log.txt")
  # 引擎报错计数；Vulkan 不可用回落 OpenGL 的那几行（下一行 at: 在 drivers/vulkan/）是环境噪声，不算（同 GATES §三 patrol 口径）
  errs=$(awk '{ if (pend) { if ($0 !~ /drivers\/vulkan\//) n++; pend = 0 } if ($0 ~ /^ERROR|SCRIPT ERROR/) pend = 1 }
              END { if (pend) n++; print n + 0 }' "$d/log.txt")
  # 小样用 Godot 拼（tour_sheet.gd，lane pg5）：不依赖 Python / PIL；cwd 放进站点目录，免得拉起游戏工程。
  # 脚本运行时报错时 Godot 照样可能退 0，所以按产物在不在判（站点目录开头已清空，不会认到旧图）
  if [ -n "$(ls "$d"/f*.png 2>/dev/null)" ]; then
    sheet_out=$(cd "$d" && perl -e 'alarm 60; exec @ARGV' "$GODOT" --headless -s "$HERE/tour_sheet.gd" -- "$PWD" "$site" 2>&1)
    if [ $? -ne 0 ] || [ ! -s "$d/last.png" ] || [ ! -s "$d/sheet.jpg" ]; then
      echo "$sheet_out" | grep -E 'TOUR_SHEET|ERROR' >&2
      echo "$site: 小样没出（tour_sheet.gd 失败）" >&2
      why+=("小样没出")
    fi
  fi
  nf=$(ls "$d"/f*.png 2>/dev/null | wc -l | tr -d ' ')
  [ "$rc" -ne 0 ] && why+=("引擎退出码 $rc")
  [ -z "$ready" ] && why+=("未就位")
  [ "$errs" -ne 0 ] && why+=("报错 $errs 行")
  [ "$nf" -eq 0 ] && why+=("一帧没出")
  mark="✓"; [ ${#why[@]} -gt 0 ] && { mark="✗"; fail=$((fail + 1)); }
  printf "%s %-26s rc=%s frames=%s errors=%s %s%s\n" "$mark" "$site" "$rc" "$nf" "$errs" "${ready:-（未就位）}" \
    "$([ ${#why[@]} -gt 0 ] && printf '  ← %s' "$(IFS=/; echo "${why[*]}")")"
done
if [ "$fail" -eq 0 ]; then echo "TOUR PASS $#/$#"; else echo "TOUR FAIL $fail/$#"; fi
[ "$fail" -eq 0 ]
