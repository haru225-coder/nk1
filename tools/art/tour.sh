#!/bin/bash
# 巡检截帧：对给定站点逐个跑 res://tools/art/ShotTour.tscn（Movie Maker，10 fps，1280×720），
# 每站输出 <输出根>/<站点>/f00000000.png…、last.png（最后一帧原图）、sheet.jpg（带帧号小样）、log.txt。
#
# 用法：tools/art/tour.sh [-n 每站帧数] [-r 运行副本] [-o 输出根] [站点…]
#   -n  默认 30（3 秒；站点一般第 8–12 帧就位，之后画面静止）
#   -r  运行副本目录，默认 ~/tmp/nk1-art-cloud-run-port（须先 rsync 并 --headless --editor --quit 导入过一次）
#   -o  输出根，默认 ~/tmp/nk1-art-work/tour
#   站点缺省 = 下面 ALL（基础站点全集）；另可给 cutscene_<id> / chapter_card_<n> / banner_<port> 等，见 ShotTour.gd 的 SITES。
#   额外参数：环境变量 TOUR_ARGS 原样追加在 -- 之后（如 TOUR_ARGS="--shot=3"）。
# 一次只开一个 Godot 进程（逐站串行）。本脚本只读运行副本，不改仓库。
set -u
GODOT=${GODOT:-$HOME/tmp/godot-4.6.3/Godot.app/Contents/MacOS/Godot}
N=30
RUN=$HOME/tmp/nk1-art-cloud-run-port
OUT=$HOME/tmp/nk1-art-work/tour
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
mkdir -p "$OUT"
fail=0
for site in "$@"; do
  d="$OUT/$site"
  rm -rf "$d"; mkdir -p "$d"
  # shellcheck disable=SC2086
  perl -e 'alarm 240; exec @ARGV' "$GODOT" --path "$RUN" --write-movie "$d/f.png" --fixed-fps 10 \
    --quit-after "$N" --resolution 1280x720 res://tools/art/ShotTour.tscn -- --tour="$site" ${TOUR_ARGS:-} \
    > "$d/log.txt" 2>&1
  rc=$?
  ready=$(grep -m1 -o 'TOUR_READY.*' "$d/log.txt")
  errs=$(grep -cE '^ERROR|SCRIPT ERROR' "$d/log.txt")
  python3 - "$d" "$site" <<'PY'
import glob, os, sys
from PIL import Image, ImageDraw
d, site = sys.argv[1], sys.argv[2]
fs = sorted(glob.glob(os.path.join(d, "f*.png")))
if not fs:
    sys.exit(0)
Image.open(fs[-1]).save(os.path.join(d, "last.png"))
k = 12
pick = sorted({fs[round(i * (len(fs) - 1) / (k - 1))] for i in range(k)}) if len(fs) > k else fs
w, h, cols = 320, 180, 4
rows = (len(pick) + cols - 1) // cols
sheet = Image.new("RGB", (cols * w, rows * h + 24), (16, 14, 12))
dr = ImageDraw.Draw(sheet)
dr.text((6, 5), "%s  (%d frames)" % (site, len(fs)), fill=(233, 220, 192))
for i, f in enumerate(pick):
    im = Image.open(f).convert("RGB").resize((w, h))
    x, y = (i % cols) * w, (i // cols) * h + 24
    sheet.paste(im, (x, y))
    dr.rectangle([x, y, x + 58, y + 14], fill=(0, 0, 0))
    dr.text((x + 3, y + 2), os.path.basename(f)[1:-4].lstrip("0") or "0", fill=(255, 210, 90))
sheet.save(os.path.join(d, "sheet.jpg"), quality=86)
PY
  nf=$(ls "$d"/f*.png 2>/dev/null | wc -l | tr -d ' ')
  printf "%-26s rc=%s frames=%s errors=%s %s\n" "$site" "$rc" "$nf" "$errs" "${ready:-（未就位）}"
  { [ "$rc" -ne 0 ] || [ -z "$ready" ] || [ "$errs" -ne 0 ]; } && fail=1
done
exit $fail
