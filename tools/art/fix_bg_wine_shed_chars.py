#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""背景画修瑕：兴化酒棚底图里的简体字「酿」「来」改回「釀」「來」，中部青幡三个 AI 伪字改写「新酒」（史实纠偏）。

来由：bg_xinghua_wine_shed.jpg（1024×1024，序章酒棚 / 港口酒肆底图，剧情 1255—1290 福建沿海）里三处招牌写的是
1956 年《汉字简化方案》以后的简化字：左侧幡旗「家酿」、右上木牌「家酿」、右侧立柱竖牌「雨夜客来」。
宋元刻本、碑版、市招都写「釀」「來」，简体「酿」「来」在这个年代一律穿帮。其余字（家、雨、夜、客）古今同形，不动。
另有画面中部偏左横杆上那面青色小幡（下缘带流苏，布面 x≈742–779、y≈257–367）写的三个字是 AI 生成的伪字（上像
简体「韦」、中不成字、下像「家」又不是），不是真字：抹掉重写「新酒」两字竖排——《清明上河图》正店酒旗即书「新酒」，北宋有据。

做法（每块牌单独开一个处理窗，互不牵连；四处都是 SIGNS 表里的一条）：
1. 判墨：牌面 mask（幡的黄布面 / 木牌内框里的板面 / 竖牌板面 / 青幡布面，按原图逐行实测的多边形）内，亮度低于局部亮底
   （13×13 邻域牌面像素 85 分位）的 RELATIVE_INK 倍算墨；只留够大、带墨芯、不沿牌边走的连通块——木纹暗线、
   布纹深斑、褶影、板边阴影都进不来。整块牌的笔画一起判；连通块过半落在旧字框里的才算旧字（「家」末笔连着布褶
   垂进下框的几个像素归「家」）。
   青幡布面左缘一条竖褶影、顶上垂坠褶影 rel 0.4–0.7，单阈值 0.78 会和字连成一片（实测 5 块 1130 像素，其中一块从
   幡左缘沿褶影一路连到第三字）：青幡走双阈值——rel < 0.35 的墨芯当种子，只许在 rel < 0.78 里往外长 2px，得 4 块
   717 像素，恰好是三个伪字。
2. 抹旧字补底：挖洞 = 旧字笔画外扩 2px（JPEG 振铃在笔画外起亮边，字口里的小空一并补）。已知像素 = 牌面里离
   任何一个字的笔画都 2px 以外的像素（别的字的振铃也不许渗进来）。
   青幡三个伪字挤满中轴、笔画间的已知像素都是一小条一小条，外扩 2px 时字口/夹缝里的已知小块带着振铃亮边，
   补出来一圈圈亮斑：青幡外扩 3px，另把被笔画围住、小于 40 像素的已知小块也并进洞里一起补。
   低频：mask 内归一化卷积由粗到细多尺度合成（细尺度邻域里已知像素够多才用细尺度）；幡布、青幡（竖褶）与竖牌（顺纹木板）
   用竖长横窄的核，木牌板面近乎平涂用各向同性核。青幡左侧暗褶、顶部垂坠褶、中间偏亮的受光都由此接上。
   高频：借同一块牌上顺着纹理方向错开一两个字位的真实肌理（像素减同尺度 mask 内平滑），幡与竖牌逐列上移
   （同一根布褶、同一道木纹），木牌沿板面倾斜的竖轴上移；源像素须离笔画、牌边若干 px（否则会把「家」的笔口残影、
   木牌内框线借进洞里成虚影），借不到的补合成噪声（幅度按洞外实测）；高频整体按「落盘后洞内/洞外」标定放大。
   青幡不借：三个字占满中轴，离笔画 3px、离布边 2px 以外的净布只剩两侧窄条，横移 ±13px 借过来能盖到洞的 10–15%，
   却把邻字笔画边的高频一并带进来，拉伸对比后可见一个「十」字虚影；上下移 30–60px 只盖 3–9%，还带进顶部垂坠褶的横纹。
   青幡全用合成噪声：竖长核 (0.5, 1.5) 顺布纹，tanh 软削峰到 1.6σ（高斯噪声的尖峰在细布上是一颗颗亮斑）。
   实测（只抹不写、落盘后）：四处旧字框里再判不出笔画（692/633/551/717 → 0 像素）。
3. 写新字：「釀」「來」用霞鹜文楷 Medium（LXGWWenKai-Medium，全量字库；马善政、志莽行、龙藏、刘建毛草都没有「釀」「來」）
   高分辨率渲染，按旧字笔画的外接框定位定大小，木牌再按内框暗线实测的 ≈6.8° 倾斜旋转；幡上原字瘦长（「家」31×46），
   「釀」按 33×41.5 横向收约两成，竖牌「來」36×42 与「夜客」36×41 同宽；
   笔画粗细用「高斯模糊 + 移阈值」在字形空间整体加粗/减细，4×4 超采样得覆盖率，再按原字笔口的柔度轻糊。
   只换「釀」「來」一个字、不整牌重写：原图的「家」「雨夜客」是端正楷书，笔形与文楷同路，按同牌字实测
   把笔宽、墨色、笔口柔度对齐以后看得出是一手写的；整牌重写要多抹多补三到五个字，得不偿失。
   「釀」二十四画，按「家」的笔宽写会糊成一块：只加粗 0.2px（笔宽略细于「家」，繁难字写细本是书家常法；
   扫参见自检），「來」与「雨夜客」笔画数相当，加粗 0.8px，笔画像素数、笔宽与三字持平。
   青幡「新酒」：五套字库都有这两个字；原伪字是偏行楷的墨笔（笔画粗壮、起收有顿），同尺寸试写后取马善政毛笔楷书
   （MaShanZheng）——文楷太像印刷体，志莽行「酒」草化难认，龙藏笔画偏细（同尺寸笔画像素少两成）。两字竖排、字形外接框
   各 26.5×30.5（原三个伪字 19–22 宽、24–28 高，两个字写满一幅就该放大），框心 x 760（布面中线；原伪字墨重心 760.2）、
   y 287.5 / 328.0。落盘后判出的墨迹（含笔口）实测：「新」746–774×272–302、「酒」745–774×311–344，墨重心 x 759.6 / 760.3；
   布面宽 35–37px，左右各留 3–5px；字间空 8 行（303–310）；上留白 15px（到上缘 257）、下留白 15px（到下缘两角 359.5），
   整组中心 308 = 原三字 308.5 ≈ 布面方形部分中线 308。笔宽不加粗（weight 0）：rel<0.5 的均宽 新 3.1 / 旧 2.8，加 0.2px
   就到 3.8；笔口柔度 σ0.2。幡面竖褶在字区内起伏不到 1px，字形不做形变，受光靠第 4 步墨色随补底走。
4. 墨色：同牌未改的字（幡与木牌取「家」，立柱取「雨夜客」）与被换掉的旧字本身，墨芯（笔画内缩 1px 且够深）RGB ÷
   墨下补底色（同第 2 步）取逐通道中位数，得墨/底比；新字墨色 = 补好的底色 × 该比例，自动随牌面受光（左亮右沉）走。
   墨芯里的深浅起伏按参照字实测（MAD）补一半——另一半是 JPEG 噪点，新字落盘时自己会带上。
   青幡没有同牌真字，参照 = 三个伪字本身（墨/底比 RGB ≈0.20/0.17/0.08，偏暖的浓墨）；马善政细笔多、覆盖率到不了 1，
   落盘后墨/底亮度比 0.197（旧 0.175）偏淡，墨色再乘 ink_scale 0.88 → 0.170，笔口/墨芯 0.61 与旧字相同。
5. 写出：改动像素只落在它们所在的 JPEG MCU 里（本图 4:2:0 抽样，MCU = 16×16）。按 MCU 行把相邻改动块并成矩形，
   每块用原图同一套量化表、同一抽样编码，再用 jpegtran -drop 逐块无损嵌回原图字节流：块外 DCT 系数原样照搬。
   fix_bg_customs_jar.write_jpeg 只走 4:4:4（sampling==0）单矩形，这张 4:2:0 的图进去会退回整图重编码，
   所以这里另写按 MCU 分块的版本；模糊、mask 内归一化、局部分位、Lab 等小工具从 fix_bg_customs_jar import。
   块外一致用 djpeg -nosmooth（色度按块复制放大，逐块独立解码）逐像素核对，不一致就不写；PIL 默认的 fancy
   upsampling 会把色度跨 MCU 边界插值，改动块外紧贴的一圈像素会差几个灰阶，自检里一并打印。
   青幡的改动块（MCU 列 46–48、行 16–22）和另三块牌的改动块互不相邻，各自成矩形。

幂等：脚本里存着原图四处旧字的笔画指纹（第 1 步判出的布尔笔画图，packbits+base64，--dump-templates 生成）。
运行时用同一套判墨量出当前图同一框内的笔画，与指纹求 IoU，低于该牌的 skip_iou（默认 SKIP_IOU 0.70）视为已改，跳过：
  幡 / 木牌 / 竖牌：原图 = 1（重存 q75 仍 ≥0.92、缩半再放大 ≥0.84），换过字后 0.49 / 0.60 / 0.52（重存、缩放后仍 ≤0.60）。
  青幡：原图 = 1（重存 q95/85/75 为 0.97/0.92/0.91，缩半再放大 0.71——伪字细小，缩放掉得多，贴着 0.70），
  写「新酒」后 0.19（重存、缩放后 ≤0.21）：青幡门槛取 0.45，两边都留足余量。
由此分得清三种状态（运行时打印「状态：」一行）：全新原图（四处都要改）/ 已改「釀」「來」、青幡未改（只改青幡——
即 HEAD c6be6b4 之后第一轮就地运行的结果）/ 四处全部已改（不写任何文件、rc=0）。判定不依赖字体文件。
每块牌的处理只读自己的处理窗，四块处理窗互不重叠，所以「对原图一次做完四处」与「对已改三处的文件只补青幡」
写出的 JPEG 逐字节相同（实测 md5 相同）。所以日后可以直接对仓库文件运行。渲染用固定随机种子，
同一输入两次运行输出逐字节相同。输出与输入同路径时必须加 --in-place 才写。

用法：
  python3 tools/art/fix_bg_wine_shed_chars.py --in-place           # 就地处理 assets/bg_xinghua_wine_shed.jpg（已处理则跳过）
  python3 tools/art/fix_bg_wine_shed_chars.py --out /tmp/cand.jpg  # 只出候选，不动仓库文件
  python3 tools/art/fix_bg_wine_shed_chars.py --src A.jpg --out B.jpg [--only banner,plaque,pillar,flag]
  字体目录默认 ~/tmp/nk1-art-work/fonts_src（要 LXGWWenKai-Medium.ttf 与 MaShanZheng-Regular.ttf），可用环境变量
  NK1_FONT_SRC 覆盖（仓库 assets/fonts/ 里的文楷是子集，没有「釀」「來」）。
自检数字（旧字独有笔画区残留、补底肌理洞内/洞外、新字/参照字的笔宽·墨/底比·笔口柔度、改动区外平均绝对差、
改动块外变动像素、边界 ΔE）每次运行都会打印。
"""
import argparse
import base64
import io
import os
import shutil
import subprocess
import sys
import tempfile
from statistics import NormalDist

import numpy as np
from PIL import Image, ImageDraw, ImageFont, JpegImagePlugin

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from fix_bg_customs_jar import blur, blur_xy, local_pct, luma, smoothstep, srgb_to_lab  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(HERE))
DEFAULT_SRC = os.path.join(ROOT, "assets", "bg_xinghua_wine_shed.jpg")
SIZE = (1024, 1024)
FONT_DIR = os.path.expanduser(os.environ.get("NK1_FONT_SRC", "~/tmp/nk1-art-work/fonts_src"))
FONT = os.path.join(FONT_DIR, "LXGWWenKai-Medium.ttf")

RELATIVE_INK = 0.78      # 亮度 < 局部亮底 × 此值 = 墨
BG_RADIUS, BG_Q = 6, 85  # 局部亮底：13×13 邻域牌面像素的 85 分位
CORE_REL = 0.45          # 墨芯：亮度 < 局部亮底 × 此值
MIN_STROKE_PX = 12       # 连通块小于此面积的暗点当木纹/布纹，不算笔画
EDGE_BAND = 2            # 牌面边内这么宽的一条带：大半落在带里的暗块是边上的影子，不算笔画
HOLE_GROW = 2            # 挖洞 = 笔画外扩这么多像素（8 邻域）
TEX_FAR = 4              # 借肌理源像素离笔画/牌边的默认最小距离（各牌可用 tex_far/tex_edge 改）；自检量洞外肌理也用它
INK_VAR_MIX = 0.5        # 墨芯起伏补参照字实测的几成
SKIP_IOU = 0.70          # 当前笔画与旧字指纹 IoU 低于此值 = 这块牌已换过字
GLYPH_PX = 640           # 字形渲染字号（高分辨率）
SS = 4                   # 覆盖率超采样
MARGIN = 16              # 处理窗 = 牌面外接框外扩

# 每块牌：face = 牌面多边形（原图像素坐标，逐行实测）；erase = 旧字框；refs = 同牌未改字的框；
# glyph = 新字外接框中心/宽高（原图像素，字自身坐标系）、倾角（度，正 = 牌下端偏右）、笔宽增量（原图像素，正加粗）、笔口柔度 σ；
# fill = 补底低频的多尺度核 (σx, σy) 由细到粗；tex_lp = 量高频用的平滑核；tex_from = 借肌理的错位 (dx, dy)（按先后取）；
# tex_far / tex_edge = 借肌理的源像素离笔画至少几 px、离牌边至少几 px（木牌板面平、边框线硬，取严；竖牌顺纹，放宽才借得到）；
# tex = 借不到时合成噪声的核 (σx, σy)；tex_gain = 补底高频放大（补好的底要再过一次同量化表编码，会磨掉一部分高频；
# 按「只抹不写、落盘后洞内（内缩 1px）/洞外（离笔画与牌边 4px 以外）一圈的相对高频比」标定：1.0 时实测 幡 0.62、
# 木牌 0.78、竖牌 0.99；取 1.2 / 1.3 / 1.0 → 0.74 / ≈0.97 / 0.99。幡的参照圈只有 94 像素、又贴着褶影，读数偏高，
# 1.35 以上补出来的噪点会被判成笔口，按目测取 1.2）
# 可选项（不写就走默认，前三块牌都不写）：seed_rel / seed_grow = 双阈值判墨（墨芯种子阈值、往外长几 px）；
# hole_grow = 挖洞外扩（默认 HOLE_GROW）；island_px = 笔画围住的已知小块小于此面积就并进洞；font = 字库文件名（默认文楷）；
# glyphs = 多字牌逐字的 ch + 外接框规格（同 glyph）；tex_clip = 合成噪声 tanh 软削峰（σ 倍数）；ink_scale = 墨/底比再乘；
# skip_iou = 该牌的幂等门槛（默认 SKIP_IOU）。
# 实测：幡「家」框 595–625×266–311、旧「酿」594–624×314–356；木牌内框暗线 左 x≈836+0.126(y−140)、右 x≈879.5+0.12(y−140)、
# 下 y≈226−0.117(x−850)，倾角 ≈6.8°，旧「酿」在该倾角下 34.2×34.2、中心 (867.1,198.7)；竖牌「来」909–943×439–481，
# 同牌「雨夜客」中轴 x≈926.5。
# 青幡布面（R−B<28 的青灰布逐行量）：左缘 x≈742，右缘 779.5（y≤270）→ 777（y≥318），上缘 y≈257（横杆下的黄边），
# 下缘两角 y≈359.5、V 尖 (759.5,367)；三个伪字 749–770×266–293、751–769×295–322、750–771×328–351，墨重心 x 760.2。
# 青幡 tex_gain 按「只抹不写、落盘后」目看定 0.8（洞里露底处 / 洞外一圈相对高频 0.086 / 0.109；洞外一圈只有 115 像素、
# 全贴着布边和左侧暗褶，读数偏高；1.0 时字区中间的布面比原图两侧的净布花）。
SIGNS = [
    dict(key="banner", label="左侧幡旗", old="酿", new="釀",
         face=[(586.5, 255.5), (629.0, 255.5), (629.0, 349.0), (611.5, 371.0), (588.5, 351.5), (586.5, 348.5)],
         erase=(589, 312, 629, 358), refs=[(591, 262, 632, 312)],
         glyph=dict(cx=609.5, cy=335.5, w=33.0, h=41.5, rot=0.0, weight=0.2, soft=0.35),
         fill=[(1.5, 3.0), (2.5, 6.0), (4.0, 12.0)], tex_lp=(1.5, 3.0), tex_from=[(0, -47), (0, -24), (0, -70)],
         tex=(0.8, 2.0), tex_far=3, tex_edge=2, tex_gain=1.2, seed=1271),
    dict(key="plaque", label="上方木牌", old="酿", new="釀",
         face=[(835.6, 134.0), (879.2, 129.0), (888.6, 219.9), (846.2, 224.8)],
         erase=(843, 178, 890, 224), refs=[(836, 131, 884, 180)],
         glyph=dict(cx=867.1, cy=198.7, w=35.5, h=34.5, rot=6.8, weight=0.2, soft=0.35),
         fill=[(2.0, 2.0), (4.0, 4.0), (8.0, 8.0)], tex_lp=(2.0, 2.0), tex_from=[(-5, -42), (-3, -22), (-7, -60)],
         tex=(0.9, 1.3), tex_far=4, tex_edge=4, tex_gain=1.3, seed=1272),
    dict(key="pillar", label="立柱竖牌", old="来", new="來",
         face=[(906.5, 276.0), (949.0, 276.0), (949.0, 494.0), (906.5, 494.0)],
         erase=(906, 436, 948, 486), refs=[(906, 284, 949, 336), (906, 335, 949, 386), (906, 385, 949, 437)],
         glyph=dict(cx=926.5, cy=460.5, w=36.0, h=42.0, rot=0.0, weight=0.8, soft=0.3),
         fill=[(1.5, 4.0), (2.5, 8.0), (4.0, 16.0)], tex_lp=(1.5, 4.0), tex_from=[(0, -50), (0, -100), (0, -150), (0, -25)],
         tex=(0.5, 2.5), tex_far=2, tex_edge=1, tex_gain=1.0, seed=1273),
    dict(key="flag", label="中部青幡", old="三个伪字", new="新酒",
         face=[(742.0, 257.0), (779.5, 257.0), (779.0, 272.0), (778.0, 290.0), (777.0, 318.0), (777.0, 359.5),
               (759.5, 367.0), (742.0, 359.5)],
         erase=(745, 262, 775, 356), refs=[], seed_rel=0.35, seed_grow=2, hole_grow=3, island_px=40,
         font="MaShanZheng-Regular.ttf",
         glyphs=[dict(ch="新", cx=760.0, cy=287.5, w=26.5, h=30.5, rot=0.0, weight=0.0, soft=0.2),
                 dict(ch="酒", cx=760.0, cy=328.0, w=26.5, h=30.5, rot=0.0, weight=0.0, soft=0.2)],
         fill=[(1.5, 3.0), (2.5, 6.0), (4.0, 12.0)], tex_lp=(1.5, 3.0), tex_from=[],
         tex=(0.5, 1.5), tex_clip=1.6, tex_far=3, tex_edge=2, tex_gain=0.8, ink_scale=0.88, skip_iou=0.45, seed=1274),
]
# 原图旧字笔画指纹（--dump-templates 从 git HEAD c6be6b4 的原图生成，md5 196ccbb7b719dbb9ff978b7e28fc9c1e；
# flag 用双阈值判墨，框 745–775×262–356 里 717 像素）：
# key -> (旧字框, 框内布尔笔画图 packbits base64)
TEMPLATES = {
    "banner": ((589, 312, 629, 358), "AAAAAAAAAAAAAAAAAYAAAAADwAAAAAPgAAAHw/AAAf/B8AAH/+DwAAf/wGAAA/+AfAAAfA/+AAB8H/8AAG4P/wAAb88PAAB/7g8AB3/vHgAH/+/+AAfs7/4AB+/v/gAHb+4eAAdt7jwAB23v/AAHze/8AAf/7/8AB//vB4AH2e8HgAcB748ABx3v/gAH/+/8AAf/zvgAB+HueAAHAe4+AAe/7j8AB//Of4AH/87vwAfv78/gB4H/x/ADAc+D8AAAn4HwAAAfAEAAAA8AQAAADgBQAAAAAPAAAAAAQAAAAABAAAAAAAA="),
    "plaque": ((843, 178, 890, 224), "AAAAAAAAAAAAAAAAAAAAAAAAAAAPAAAAAAAfAAAAAAA/AAAAAAA+AAAAAOAb4AAAB/A/wAAAf+P/gAAP/5//AAAf+H8eAAA/4Hg8AAAx4HH4AAAH3P/wAAAf/f/AAAA/++eAAAP/9w8AAAf87h7AAA/d3v/AABu7v++AAD93fx8AAH/ueHwAAP388PAAAfn5/4AAA/Jz/wAAA6TnPwAAB33OP4AAD//cf+AAH/Od//AAPwc7n/gAcP5/D+AA5/z8BwAA//n4AAAD/PPgAAADwOfAAAAHAI+AAAAEAA4AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=="),
    "pillar": ((906, 436, 948, 486), "AAAAAAAAAAAAAAAAAAAAAAADwAAAAAD4AAAAAD4AAAAAB4AAAAAB4wAAAAB/8AAAIH/8AAAH//+AAAH//8AAAD/+AAAAB/44AAAA94+AAABB5+AAADx58AAAD554AAAD57gAAAB5/PgAAA5//wAAAX//4AAB///4AA////4AB//8AAAB//8AAAA/P+AAAAYf/AAAAAf/gAAAA//4AAAB97+AAAD55/AAAHx4/gAAPh4/4AAfB4f+AB+B4P/gD4B4H/wHwB4D/wCAB4AAAAAP4AAAAAP4AAAAAH4AAAAAD4AAAAAB4AAAAAB4AAAAAAgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="),
    "flag": ((745, 262, 775, 356), "AAAAAAAAAAAAAAAAAAAAAAAwAAABgAAAfEAAA/+AAA/8AAAf4AAB/gAAD+AAADvwAAAP4AAA/4AAD/wAAHPgAAGe4AABP8AAD/4AAH/BgADn/wAAP/wAB/hgAf2/wD+3/gD4P+ADwHAABgHAAAAGAAAAGAAAAGAAAAAAAAAGAAAAGMAADH8AAHl/AAPt/gAPP/AAHf2AAHbmAAP/+AAP9+AAXvIAA/HAAA8GAAAwAEAAgB+AAAH+AAA/4AAB84AAB34AAB/4AAB/YAADr4AAD/4AAD/YAAHJ8AAGA8AAAA4AAAAYAAAAAAAAAAAAAAAAAAAAAAAAAAAAegAAAfAAAAPYAAAP+AAA/+AAP8QAAfwQAAeD8AAA/cAAA+8AAA74ABg/gAB3/AAB/PIAA4f4AAA58AAA5/AAB3/gADr/AAH7/wAP7H4Bd/AAB9+AABgAAAAAAAAAAAAAAAAAAAAAAAA="),
}


# ---------- 小工具 ----------
def poly_cover(poly, shape, ss=4):
    """多边形覆盖率（ss×ss 超采样）。"""
    h, w = shape
    im = Image.new("L", (w * ss, h * ss), 0)
    ImageDraw.Draw(im).polygon([(x * ss, y * ss) for x, y in poly], fill=255)
    a = np.asarray(im, np.float32) / 255.0
    return a.reshape(h, ss, w, ss).mean(axis=(1, 3))


def dilate(m, k=1, diag=True):
    r = m.copy()
    for _ in range(k):
        s = r.copy()
        s[1:] |= r[:-1]
        s[:-1] |= r[1:]
        s[:, 1:] |= r[:, :-1]
        s[:, :-1] |= r[:, 1:]
        if diag:
            s[1:, 1:] |= r[:-1, :-1]
            s[1:, :-1] |= r[:-1, 1:]
            s[:-1, 1:] |= r[1:, :-1]
            s[:-1, :-1] |= r[1:, 1:]
        r = s
    return r


def erode(m, k=1):
    return ~dilate(~m, k, diag=False)


def shift(a, dx, dy, fill=0):
    """out[y, x] = a[y+dy, x+dx]，越界填 fill。"""
    out = np.full_like(a, fill)
    H, W = a.shape[:2]
    oy = slice(max(0, -dy), min(H, H - dy))
    sy = slice(max(0, dy), min(H, H + dy))
    ox = slice(max(0, -dx), min(W, W - dx))
    sx = slice(max(0, dx), min(W, W + dx))
    out[oy, ox] = a[sy, sx]
    return out


def nblur_xy(img, m, sx, sy):
    """mask 内归一化模糊（各向异性）。"""
    mm = m.astype(np.float32)
    mm3 = mm if img.ndim == 2 else mm[..., None]
    return blur_xy(img * mm3, sx, sy) / np.maximum(blur_xy(mm3, sx, sy), 1e-4)


def components(m):
    """8 连通分量（纯 numpy + 栈，墨迹只有几千像素，够快）。返回 [像素坐标数组]。"""
    lab = np.zeros(m.shape, bool)
    comps = []
    H, W = m.shape
    for y0, x0 in zip(*np.nonzero(m)):
        if lab[y0, x0]:
            continue
        stack = [(y0, x0)]
        lab[y0, x0] = True
        pix = []
        while stack:
            y, x = stack.pop()
            pix.append((y, x))
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    yy, xx = y + dy, x + dx
                    if 0 <= yy < H and 0 <= xx < W and m[yy, xx] and not lab[yy, xx]:
                        lab[yy, xx] = True
                        stack.append((yy, xx))
        comps.append(np.array(pix))
    return comps


def iou(a, b):
    u = (a | b).sum()
    return float((a & b).sum() / u) if u else 1.0


def stroke_width(m):
    """每个墨像素横竖游程取小者的中位数（笔宽近似）。"""
    def runs(mm):
        out = np.zeros(mm.shape, np.int32)
        for i in range(mm.shape[0]):
            row = np.concatenate([[0], mm[i].astype(np.int8), [0]])
            d = np.diff(row)
            for a, b in zip(np.nonzero(d == 1)[0], np.nonzero(d == -1)[0]):
                out[i, a:b] = b - a
        return out
    if not m.any():
        return 0.0
    return float(np.median(np.minimum(runs(m), runs(m.T).T)[m]))


# ---------- 一块牌 ----------
class Board:
    """一块牌的处理窗：窗内坐标 = 原图坐标 − (x0, y0)。整牌笔画、已知像素在这里一次算好。"""

    def __init__(self, src, sign):
        H, W = src.shape[:2]
        fx = [p[0] for p in sign["face"]]
        fy = [p[1] for p in sign["face"]]
        self.x0 = max(0, int(np.floor(min(fx))) - MARGIN)
        self.y0 = max(0, int(np.floor(min(fy))) - MARGIN)
        self.x1 = min(W, int(np.ceil(max(fx))) + MARGIN)
        self.y1 = min(H, int(np.ceil(max(fy))) + MARGIN)
        self.img = src[self.y0:self.y1, self.x0:self.x1].astype(np.float32)
        self.lum = luma(self.img)
        self.shape = self.lum.shape
        self.face = poly_cover([(x - self.x0, y - self.y0) for x, y in sign["face"]], self.shape)
        self.face_b = self.face >= 0.5
        ys, xs = np.nonzero(self.face_b)
        self.rel = self._rel((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
        self.seed_rel, self.seed_grow = sign.get("seed_rel"), sign.get("seed_grow", 2)
        self.strokes, self.comps = self._strokes()
        self.hole_grow = sign.get("hole_grow", HOLE_GROW)
        self.known = self.face_b & ~dilate(self.strokes, self.hole_grow)
        # 笔画围住的小块已知像素（字口里的空、笔画夹缝）：四周都是振铃亮边，拿来当已知会在补底里鼓出一圈圈亮斑，
        # 牌上有 island_px 时不当已知，并进相邻的洞一起补
        self.islands = []
        if sign.get("island_px"):
            for pix in components(self.known):
                if len(pix) < sign["island_px"]:
                    self.islands.append(pix)
                    self.known[pix[:, 0], pix[:, 1]] = False

    def hole_of(self, ink):
        """挖洞 = 笔画外扩 hole_grow px（牌面内），再并上贴着它的小块已知像素。"""
        h = dilate(ink, self.hole_grow) & self.face_b
        if self.islands:
            near = dilate(h, 1)
            for pix in self.islands:
                if near[pix[:, 0], pix[:, 1]].any():
                    h[pix[:, 0], pix[:, 1]] = True
        return h

    def box(self, b):
        return (b[0] - self.x0, b[1] - self.y0, b[2] - self.x0, b[3] - self.y0)

    def _rel(self, box, pad=8):
        """框内每像素亮度 ÷ 局部亮底（牌面像素 85 分位），框外为 1。"""
        x0, y0, x1, y1 = box
        X0, Y0 = max(0, x0 - pad), max(0, y0 - pad)
        X1, Y1 = min(self.shape[1], x1 + pad), min(self.shape[0], y1 + pad)
        sub = self.lum[Y0:Y1, X0:X1]
        bg = local_pct(sub, self.face_b[Y0:Y1, X0:X1], BG_RADIUS, BG_Q)
        rel = np.ones(self.shape, np.float32)
        rel[Y0:Y1, X0:X1] = sub / np.maximum(bg, 1.0)
        out = np.ones(self.shape, np.float32)
        out[y0:y1, x0:x1] = rel[y0:y1, x0:x1]
        return out

    def _strokes(self):
        """笔画：判墨后只留够大、带墨芯、不沿牌边走的 8 连通块。返回 (笔画 mask, 连通块列表)。
        牌上有 seed_rel 时走双阈值：先取 rel < seed_rel 的墨芯当种子，只准在 rel < RELATIVE_INK 的像素里向外长
        seed_grow px——青幡的布褶影（rel 0.4–0.7）和字连成一片，单阈值会把整条褶影当成笔画。"""
        ink = (self.rel < RELATIVE_INK) & self.face_b
        if self.seed_rel is not None:
            grown = (self.rel < self.seed_rel) & self.face_b
            for _ in range(self.seed_grow):
                grown = dilate(grown, 1) & ink
            ink = grown
        edge_band = self.face_b & ~erode(self.face_b, EDGE_BAND)
        keep = np.zeros(self.shape, bool)
        comps = []
        for pix in components(ink):
            if len(pix) < MIN_STROKE_PX:
                continue
            if self.rel[pix[:, 0], pix[:, 1]].min() >= CORE_REL:
                continue
            if edge_band[pix[:, 0], pix[:, 1]].mean() > 0.5:
                continue
            keep[pix[:, 0], pix[:, 1]] = True
            comps.append(pix)
        return keep, comps

    def char(self, b):
        """框里那个字的笔画：连通块过半像素落在框里的整块归它（「家」末笔连着布褶垂进下框的那几个像素不归「酿」）。"""
        x0, y0, x1, y1 = self.box(b)
        inbox = np.zeros(self.shape, bool)
        inbox[y0:y1, x0:x1] = True
        m = np.zeros(self.shape, bool)
        for pix in self.comps:
            if inbox[pix[:, 0], pix[:, 1]].mean() > 0.5:
                m[pix[:, 0], pix[:, 1]] = True
        return m

    def paste(self, full, win):
        out = full.copy()
        out[self.y0:self.y1, self.x0:self.x1] = win
        return out


def fill_background(img, known, sigmas):
    """mask 内归一化卷积，由粗到细：细尺度邻域里已知像素够多就用细尺度。img HxWx3 float。"""
    K = known.astype(np.float32)
    res = None
    for sx, sy in reversed(sigmas):
        den = blur_xy(K, sx, sy)
        est = blur_xy(img * K[..., None], sx, sy) / np.maximum(den, 1e-6)[..., None]
        if res is None:
            res = est
        else:
            conf = smoothstep(0.06, 0.30, den)[..., None]
            res = conf * est + (1 - conf) * res
    return res


def fill_hole(bd, hole, sign, rng):
    """洞里的底色 = 低频（多尺度归一化卷积）+ 高频（顺纹借同牌真实肌理，借不到补合成噪声）。
    返回 (补好的窗, 借到肌理的像素比例, 合成噪声的相对幅度)。"""
    known = bd.known & ~hole
    low = fill_background(bd.img, known, sign["fill"])
    lp = nblur_xy(bd.img, known, *sign["tex_lp"])
    hp = bd.img - lp
    # 借肌理只从离任何笔画 tex_far px 以上、离牌面边 tex_edge px 以上的像素借：笔画边上的振铃、笔口残影、
    # 牌边框线借过来都会在洞里映出虚影（木牌上移 60px 会借到内框上沿那道暗线，试过）
    far_px, edge_px = sign.get("tex_far", TEX_FAR), sign.get("tex_edge", TEX_FAR)
    far = known & ~dilate(bd.strokes | hole, far_px) & erode(bd.face_b, edge_px)
    tex = np.zeros_like(bd.img)
    have = np.zeros(bd.shape, bool)
    for dx, dy in sign["tex_from"]:
        take = hole & ~have & shift(far, dx, dy, False)
        tex[take] = shift(hp, dx, dy)[take]
        have |= take
    around = far & dilate(hole, 10)
    amp = float(luma(hp)[around].std() / max(bd.lum[around].mean(), 1.0))
    n = blur_xy(rng.normal(0, 1, bd.shape).astype(np.float32), *sign["tex"])
    n /= n.std() + 1e-6
    if sign.get("tex_clip"):          # 软削峰：高斯噪声 2σ 以上的尖峰在细布上是一颗颗亮斑，真布纹没有
        c = sign["tex_clip"]
        n = c * np.tanh(n / c)
        n /= n.std() + 1e-6
    synth = low * (amp * n)[..., None]
    tex = np.where(have[..., None], tex, synth)
    frac = float(have[hole].mean()) if hole.any() else 1.0
    return low + sign.get("tex_gain", 1.0) * tex, frac, amp


def ink_core(ink, rel):
    """墨芯：笔画内缩 1px（实心部分，不受笔口混色影响）且够深。"""
    return erode(ink, 1) & (rel < CORE_REL)


def ink_ratio(bd, boxes, sign):
    """参照字（与旧字）墨芯 RGB ÷ 墨下补底色（逐通道中位数，按墨芯像素数加权）；墨芯亮度相对起伏（MAD 折标准差）。"""
    rng = np.random.default_rng(0)
    ratios, weights, var = [], [], []
    for box in boxes:
        ink = bd.char(box)
        filled, _, _ = fill_hole(bd, bd.hole_of(ink), sign, rng)
        core = ink_core(ink, bd.rel)
        if core.sum() < 20:
            continue
        ratios.append(np.median(bd.img[core] / np.maximum(filled[core], 1.0), axis=0))
        weights.append(core.sum())
        lc = bd.lum[core]
        var.append(float(1.4826 * np.median(np.abs(lc - np.median(lc))) / max(np.median(lc), 1.0)))
    w = np.array(weights, np.float64)
    return (np.array(ratios) * w[:, None]).sum(0) / w.sum(), float(np.average(var, weights=w))


# ---------- 字形 ----------
_GLYPH_CACHE = {}


def glyph_hires(ch, font_path=None):
    font_path = font_path or FONT
    if (font_path, ch) not in _GLYPH_CACHE:
        font = ImageFont.truetype(font_path, GLYPH_PX)
        n = int(GLYPH_PX * 1.6)
        im = Image.new("L", (n, n), 0)
        ImageDraw.Draw(im).text((GLYPH_PX * 0.3, GLYPH_PX * 0.3), ch, font=font, fill=255)
        g = np.asarray(im, np.float32) / 255.0
        ys, xs = np.nonzero(g > 0.5)
        _GLYPH_CACHE[(font_path, ch)] = (g, (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
    return _GLYPH_CACHE[(font_path, ch)]


def glyph_coverage(ch, spec, shape, off=(0, 0), font_path=None):
    """新字覆盖率（0–1），shape/off 为处理窗。按外接框定位定大小、按倾角旋转，笔宽在字形空间整体调。"""
    g, (gx0, gy0, gx1, gy1) = glyph_hires(ch, font_path)
    gw, gh = gx1 - gx0, gy1 - gy0
    cx, cy, w, h = spec["cx"] - off[0], spec["cy"] - off[1], spec["w"], spec["h"]
    scale = gh / h                                   # 字形像素 / 原图像素
    dw = spec.get("weight", 0.0)
    if abs(dw) > 1e-6:
        sig = 0.6 * scale
        t = NormalDist().cdf(-(dw / 2.0) * scale / sig)   # 阈值移到 t：轮廓外移 dw/2（dw<0 内收）
        g = smoothstep(t - 0.06, t + 0.06, blur(g, sig))
    th = np.radians(spec.get("rot", 0.0))
    c, s = np.cos(th), np.sin(th)
    r = int(np.ceil(max(w, h) * 0.75)) + 4
    X0, Y0 = max(0, int(cx) - r), max(0, int(cy) - r)
    X1, Y1 = min(shape[1], int(cx) + r), min(shape[0], int(cy) + r)
    ys = Y0 + (np.arange((Y1 - Y0) * SS) + 0.5) / SS
    xs = X0 + (np.arange((X1 - X0) * SS) + 0.5) / SS
    Y, X = np.meshgrid(ys, xs, indexing="ij")
    dx, dy = X - cx, Y - cy
    u = c * dx - s * dy                             # 屏幕 → 字自身坐标（字的竖轴下端偏右 rot 度）
    v = s * dx + c * dy
    gx = gx0 + (u / w + 0.5) * gw - 0.5
    gy = gy0 + (v / h + 0.5) * gh - 0.5
    ok = (gx >= 0) & (gy >= 0) & (gx < g.shape[1] - 1) & (gy < g.shape[0] - 1)
    gx = np.clip(gx, 0, g.shape[1] - 1.001)
    gy = np.clip(gy, 0, g.shape[0] - 1.001)
    ix, iy = gx.astype(int), gy.astype(int)
    fx, fy = gx - ix, gy - iy
    val = (g[iy, ix] * (1 - fx) * (1 - fy) + g[iy, ix + 1] * fx * (1 - fy)
           + g[iy + 1, ix] * (1 - fx) * fy + g[iy + 1, ix + 1] * fx * fy) * ok
    out = np.zeros(shape, np.float32)
    out[Y0:Y1, X0:X1] = val.reshape(Y1 - Y0, SS, X1 - X0, SS).mean(axis=(1, 3))
    if spec.get("soft", 0) > 0:
        out = blur(out, spec["soft"])
    return out


def sign_font(sign):
    return os.path.join(FONT_DIR, sign["font"]) if sign.get("font") else FONT


def sign_glyphs(sign):
    """这块牌要写的新字 [(字, 外接框规格)]：单字牌用 new + glyph，多字（青幡「新酒」竖排）用 glyphs 列表。"""
    if "glyphs" in sign:
        return [(g["ch"], g) for g in sign["glyphs"]]
    return [(sign["new"], sign["glyph"])]


def sign_coverage(sign, shape, off):
    """整块牌新字覆盖率：各字分别渲染取大（字框不相交）。"""
    cov = np.zeros(shape, np.float32)
    for ch, spec in sign_glyphs(sign):
        cov = np.maximum(cov, glyph_coverage(ch, spec, shape, off, sign_font(sign)))
    return cov


def process_sign(src, sign, rng):
    """src 整图 (uint8 或 float)。返回 (新整图 float, 改动 alpha 整图, 信息)。"""
    bd = Board(src, sign)
    ratio, ink_var = ink_ratio(bd, sign["refs"] + [sign["erase"]], sign)
    ink = bd.char(sign["erase"])
    hole = bd.hole_of(ink)
    filled, tex_frac, tex_amp = fill_hole(bd, hole, sign, rng)
    # 洞的 alpha：洞内 1，向外羽化约 1px（只在牌面内）
    a_hole = np.maximum(np.clip(blur(hole.astype(np.float32), 0.7) * 1.6, 0, 1), hole) * bd.face
    base = bd.img * (1 - a_hole[..., None]) + filled * a_hole[..., None]
    cov = sign_coverage(sign, bd.shape, (bd.x0, bd.y0)) * bd.face
    if sign.get("no_glyph"):          # 开发用：只看抹字补底
        cov[:] = 0
    n = blur(rng.normal(0, 1, bd.shape).astype(np.float32), 0.6)
    n /= n.std() + 1e-6
    inkc = base * (ratio * sign.get("ink_scale", 1.0))[None, None, :] * (1.0 + INK_VAR_MIX * ink_var * n)[..., None]
    win = base * (1 - cov[..., None]) + inkc * cov[..., None]
    a = np.maximum(a_hole, np.clip(cov * 4, 0, 1))
    a[a < 1.0 / 255] = 0
    win = np.where((a > 0)[..., None], win, bd.img)
    alpha = np.zeros(src.shape[:2], np.float32)
    alpha[bd.y0:bd.y1, bd.x0:bd.x1] = a
    full = lambda m: bd.paste(np.zeros(src.shape[:2], m.dtype), m)   # noqa: E731
    info = dict(ratio=ratio, ink_var=ink_var, tex_frac=tex_frac, tex_amp=tex_amp,
                old=full(ink), hole=full(hole), cov=full(cov),
                base=bd.paste(src.astype(np.float32), base))      # 抹字补底后、写新字前（量残留用）
    return bd.paste(src.astype(np.float32), win), alpha, info


# ---------- 写出：按 MCU 分块 jpegtran -drop ----------
def mcu_size(im):
    s = JpegImagePlugin.get_sampling(im)
    return {0: (8, 8), 1: (16, 8), 2: (16, 16)}.get(s), s


def mcu_rects(changed, mcu):
    """改动像素所在的 MCU，按 MCU 行把相邻的并成矩形。"""
    mw, mh = mcu
    H, W = changed.shape
    ny, nx = -(-H // mh), -(-W // mw)
    t = np.zeros((ny, nx), bool)
    ys, xs = np.nonzero(changed)
    t[ys // mh, xs // mw] = True
    rects = []
    for j in range(ny):
        row = np.concatenate([[0], t[j].astype(np.int8), [0]])
        d = np.diff(row)
        for a, b in zip(np.nonzero(d == 1)[0], np.nonzero(d == -1)[0]):
            rects.append((a * mw, j * mh, min(b * mw, W), min((j + 1) * mh, H)))
    return rects


def decode_nosmooth(path):
    """djpeg -nosmooth：色度按块复制放大，逐块独立解码（用来逐像素核对块外）。没有 djpeg 返回 None。"""
    dj = shutil.which("djpeg")
    if not dj:
        return None
    r = subprocess.run([dj, "-nosmooth", "-ppm", path], capture_output=True)
    if r.returncode != 0:
        return None
    return np.asarray(Image.open(io.BytesIO(r.stdout)).convert("RGB"))


def write_jpeg_mcu(src_path, src_img, new_img, changed, out_path):
    """改动 MCU 按行并成矩形，逐块同量化表同抽样编码后 jpegtran -drop 嵌回；块外逐像素核对不过就不写。"""
    mcu, sampling = mcu_size(src_img)
    jt = shutil.which("jpegtran")
    if not jt or mcu is None:
        raise SystemExit("需要 jpegtran 与 4:4:4/4:2:2/4:2:0 基线 JPEG（sampling=%s）；未写任何文件。" % sampling)
    rects = mcu_rects(changed, mcu)
    qt = src_img.quantization
    with tempfile.TemporaryDirectory() as td:
        cur = os.path.join(td, "cur.jpg")
        shutil.copyfile(src_path, cur)
        drop = os.path.join(td, "drop.jpg")
        nxt = os.path.join(td, "nxt.jpg")
        for x0, y0, x1, y1 in rects:
            Image.fromarray(new_img[y0:y1, x0:x1]).save(drop, "JPEG", qtables=qt, subsampling=sampling)
            r = subprocess.run([jt, "-copy", "all", "-drop", "+%d+%d" % (x0, y0), drop, "-outfile", nxt, cur],
                               capture_output=True, text=True)
            if r.returncode != 0:
                raise SystemExit("jpegtran -drop +%d+%d 失败（rc=%d %s）；未写任何文件。"
                                 % (x0, y0, r.returncode, r.stderr.strip()[:120]))
            shutil.copyfile(nxt, cur)
        a, b = decode_nosmooth(cur), decode_nosmooth(src_path)
        if a is not None and b is not None:
            inside = np.zeros(changed.shape, bool)
            for x0, y0, x1, y1 in rects:
                inside[y0:y1, x0:x1] = True
            bad = int((a[~inside] != b[~inside]).any(-1).sum())
            if bad:
                raise SystemExit("djpeg -nosmooth 核对：改动块外有 %d 像素变了，未写任何文件。" % bad)
        os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
        shutil.copyfile(cur, out_path)
    return "jpegtran -drop ×%d 块（MCU %dx%d，4:2:%s）" % (len(rects), mcu[0], mcu[1],
                                                        {0: "4:4", 1: "2", 2: "0"}[sampling]), rects


# ---------- 幂等判定 ----------
def template_state(src, sign):
    """当前图旧字框里的笔画与原图旧字指纹的 IoU；没有指纹返回 None。"""
    if sign["key"] not in TEMPLATES:
        return None
    box, packed = TEMPLATES[sign["key"]]
    bd = Board(src, sign)
    x0, y0, x1, y1 = bd.box(box)
    cur = np.zeros(bd.shape, bool)
    cur[y0:y1, x0:x1] = bd.char(box)[y0:y1, x0:x1]
    n = (y1 - y0) * (x1 - x0)
    bits = np.unpackbits(np.frombuffer(base64.b64decode(packed), np.uint8))[:n]
    tpl = np.zeros(bd.shape, bool)
    tpl[y0:y1, x0:x1] = bits.reshape(y1 - y0, x1 - x0).astype(bool)
    return iou(cur, tpl)


def dump_template(src, sign):
    bd = Board(src, sign)
    x0, y0, x1, y1 = bd.box(sign["erase"])
    sub = bd.char(sign["erase"])[y0:y1, x0:x1]
    return base64.b64encode(np.packbits(sub.ravel()).tobytes()).decode()


# ---------- 自检 ----------
def char_stats(src, sign, box):
    """一个字的笔宽中位、笔画像素、墨/底亮度比（墨芯中位 ÷ 墨下补底中位）、笔口/墨芯像素比（柔度）。"""
    bd = Board(src, sign)
    ink = bd.char(box)
    filled, _, _ = fill_hole(bd, bd.hole_of(ink), sign, np.random.default_rng(0))
    solid = ink_core(ink, bd.rel)
    core = ink & (bd.rel < CORE_REL)
    ratio = float(np.median(bd.lum[solid]) / max(np.median(luma(filled[solid])), 1.0)) if solid.any() else float("nan")
    return dict(sw=stroke_width(ink), n=int(ink.sum()), ratio=ratio, edge_core=float((ink & ~core).sum() / max(core.sum(), 1)))


def texture_hf(img, sign, mask_fn):
    """牌面相对高频（像素减 tex_lp 平滑后的亮度标准差 ÷ 均亮），只在 mask_fn(bd) 选出的像素上量。"""
    bd = Board(img, sign)
    sel = mask_fn(bd)
    lp = nblur_xy(bd.lum, bd.known, *sign["tex_lp"])
    return float((bd.lum - lp)[sel].std() / max(bd.lum[sel].mean(), 1.0)), int(sel.sum())


def self_check(src, after, alpha, rects, todo, infos, src_path, out_path):
    for s in todo:
        info = infos[s["key"]]
        bd_b, bd_a = Board(src, s), Board(after, s)
        sub = lambda m, bd: m[bd.y0:bd.y1, bd.x0:bd.x1]  # noqa: E731
        old = sub(info["old"], bd_b)
        cov = sub(info["cov"], bd_b)
        only_old = old & ~dilate(cov > 0.15, 1)
        print("  [%s] 「%s」→「%s」：墨/底比 RGB %s，墨芯起伏 %.3f；补底借到同牌肌理 %.0f%%，合成噪声幅度 %.3f" % (
            s["label"], s["old"], s["new"], np.round(info["ratio"], 3), info["ink_var"], 100 * info["tex_frac"], info["tex_amp"]))
        print("    旧字独有笔画区 %d 像素：判墨（rel<%.2f）前 %.1f%% → 后 %.1f%%；平均 rel 前 %.2f → 后 %.2f（牌面干净处 %.2f）" % (
            only_old.sum(), RELATIVE_INK, 100 * (bd_b.rel[only_old] < RELATIVE_INK).mean(),
            100 * (bd_a.rel[only_old] < RELATIVE_INK).mean(), bd_b.rel[only_old].mean(), bd_a.rel[only_old].mean(),
            bd_b.rel[bd_b.known & (bd_b.rel < 1)].mean()))
        bd_e = Board(np.clip(info["base"] + 0.5, 0, 255).astype(np.uint8), s)
        print("    抹字补底后（写新字前）旧字框：判出笔画 前 %d → 后 %d 像素；旧笔画位置判墨 %.1f%%、平均 rel %.2f" % (
            old.sum(), bd_e.char(s["erase"]).sum(), 100 * (bd_e.rel[old] < RELATIVE_INK).mean(), bd_e.rel[old].mean()))
        hole = sub(info["hole"], bd_b)
        bare = lambda bd: hole & ~dilate(cov > 0.02, 2) & bd.face_b   # noqa: E731
        ring = lambda bd: (bd_b.known & dilate(hole, 10) & ~dilate(bd_b.strokes | hole, TEX_FAR)   # noqa: E731
                           & erode(bd_b.face_b, TEX_FAR))
        hf_in, n_in = texture_hf(after, s, bare)
        hf_out, n_out = texture_hf(src, s, ring)
        print("    补底肌理（相对高频）：洞里新字笔画 2px 外露底处 %.3f（%d 像素）/ 洞外离笔画与牌边 4px 以外一圈原图 %.3f（%d 像素）"
              % (hf_in, n_in, hf_out, n_out))
        st_new = char_stats(after, s, s["erase"])
        st_old = char_stats(src, s, s["erase"])
        refs = [char_stats(src, s, b) for b in s["refs"]]
        fmt = lambda k, f: "/".join(f % r[k] for r in refs) or "—（无同牌未改字，比旧字）"   # noqa: E731
        print("    笔宽中位 旧 %.1f 新 %.1f 参照 %s；墨/底亮度比 旧 %.3f 新 %.3f 参照 %s；笔口/墨芯 旧 %.2f 新 %.2f 参照 %s；"
              "笔画像素 旧 %d 新 %d 参照 %s" % (
                  st_old["sw"], st_new["sw"], fmt("sw", "%.1f"), st_old["ratio"], st_new["ratio"], fmt("ratio", "%.3f"),
                  st_old["edge_core"], st_new["edge_core"], fmt("edge_core", "%.2f"), st_old["n"], st_new["n"], fmt("n", "%d")))
    diff = np.abs(after.astype(np.int16) - src.astype(np.int16))
    outside = alpha == 0
    inside_rect = np.zeros(alpha.shape, bool)
    for x0, y0, x1, y1 in rects:
        inside_rect[y0:y1, x0:x1] = True
    print("  改动区（alpha>0）%d 像素，落在 %d 个矩形共 %d 像素的 MCU 里" % ((~outside).sum(), len(rects), inside_rect.sum()))
    print("  改动区外平均绝对差 %.4f、最大 %d；改动块内、改动区外平均绝对差 %.3f（同量化表重编码）" % (
        diff[outside].mean(), diff[outside].max(), diff[outside & inside_rect].mean()))
    a_ns, b_ns = decode_nosmooth(out_path), decode_nosmooth(src_path)
    if a_ns is not None and b_ns is not None:
        print("  改动块外变动像素：djpeg -nosmooth（逐块独立解码）%d；PIL 默认解码 %d（最大差 %d，均在紧贴块边的一圈：色度跨块插值）" % (
            int((a_ns[~inside_rect] != b_ns[~inside_rect]).any(-1).sum()),
            int((diff[~inside_rect].max(-1) > 0).sum()), int(diff[~inside_rect].max())))
    labb, laba = srgb_to_lab(src), srgb_to_lab(after)
    dE = np.sqrt(((laba - labb) ** 2).sum(-1))
    m = alpha > 0
    ring_out = dilate(m, 3) & ~m
    ring_in = m & ~erode(m, 2)
    print("  边界 ΔE76：改动区外 1–3px %.2f，改动区内侧 1–2px %.2f" % (dE[ring_out].mean(), dE[ring_in].mean()))


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--src", default=DEFAULT_SRC)
    ap.add_argument("--out", default=DEFAULT_SRC)
    ap.add_argument("--in-place", action="store_true", help="允许输出覆盖输入文件")
    ap.add_argument("--force", action="store_true", help="跳过幂等检查（调试用）")
    ap.add_argument("--only", default="", help="只处理这几块牌（逗号分隔 key：banner,plaque,pillar,flag）")
    ap.add_argument("--dump-templates", action="store_true", help="从 --src（须为原图）打印旧字笔画指纹，开发用")
    args = ap.parse_args(argv)
    im = Image.open(args.src)
    if im.size != SIZE or im.format != "JPEG":
        print("输入不是 1024x1024 JPEG（%s %s），不是这张底图，跳过。" % (im.format, im.size))
        return 2
    src = np.asarray(im.convert("RGB"))
    signs = [s for s in SIGNS if not args.only or s["key"] in args.only.split(",")]
    if args.dump_templates:
        for s in signs:
            print('    "%s": (%r, "%s"),' % (s["key"], s["erase"], dump_template(src, s)))
        return 0
    if os.path.abspath(args.src) == os.path.abspath(args.out) and not args.in_place:
        print("输出与输入同一路径，需加 --in-place 才写；未写任何文件。")
        return 2
    print("输入 %s（%d 字节，MCU %dx%d）" % ((args.src, os.path.getsize(args.src)) + mcu_size(im)[0]))
    todo, done_keys = [], []
    for s in signs:
        v = template_state(src, s)
        if v is None:
            print("  %s：（没有旧字指纹，直接处理）" % s["label"])
        else:
            done = v < s.get("skip_iou", SKIP_IOU)
            print("  %s：当前笔画与旧字「%s」指纹 IoU %.3f → %s" % (
                s["label"], s["old"], v, "旧字已不在（已换成「%s」）" % s["new"] if done else "旧字仍在，要换"))
            if done:
                done_keys.append(s["key"])
                if not args.force:
                    continue
        todo.append(s)
    if len(signs) == len(SIGNS):
        state = {(): "全新原图（四处都要改）", ("banner", "plaque", "pillar"): "已改「釀」「來」、青幡未改（只改青幡）",
                 ("banner", "plaque", "pillar", "flag"): "四处全部已改"}.get(tuple(done_keys), "部分已改（已改：%s）"
                                                                            % (",".join(done_keys) or "无"))
        print("  状态：%s" % state)
    if not todo:
        print("  %s都已换过字，判定已处理，跳过，未写文件。" % ("四处" if len(signs) == len(SIGNS) else "所选牌"))
        return 0
    for f in sorted({sign_font(s) for s in todo}):
        if not os.path.isfile(f):
            print("缺字体 %s（可用 NK1_FONT_SRC 指定目录），未写任何文件。" % f)
            return 2
    cur = src.astype(np.float32)
    alpha = np.zeros(src.shape[:2], np.float32)
    infos = {}
    for s in todo:
        cur, a, infos[s["key"]] = process_sign(np.clip(cur + 0.5, 0, 255).astype(np.uint8), s,
                                               np.random.default_rng(s["seed"]))
        alpha = np.maximum(alpha, a)
    new = np.clip(cur + 0.5, 0, 255).astype(np.uint8)
    changed = alpha > 0
    new[~changed] = src[~changed]
    how, rects = write_jpeg_mcu(args.src, im, new, changed, args.out)
    after = np.asarray(Image.open(args.out).convert("RGB"))
    print("写出 %s（%d 字节，%s）" % (args.out, os.path.getsize(args.out), how))
    self_check(src, after, alpha, rects, todo, infos, args.src, args.out)
    for s in todo:
        v = template_state(after, s)
        if v is not None:
            print("  幂等自检 %s：写出后笔画与旧字指纹 IoU %.3f（< %.2f 即下次跳过）" % (
                s["label"], v, s.get("skip_iou", SKIP_IOU)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
