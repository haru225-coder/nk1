#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""背景画修瑕：泉州商馆账房（各港「行会」页底图）里的青花器改成宋元之际的单色釉（史实纠偏）。

来由：bg_quanzhou_ledger.jpg（1672x941，Main.gd FACILITY_BG["_guild"]）案上、架上有好几件满绘钴蓝花的青花：
左前书案的笔筒、右案盛香料的直筒罐与浅盘、后案上的提梁盖壶，右下角暗处还有一只大罐。成熟青花是元延祐（1314—1320）
以后、至正（1341—1368）才成熟的器物，1255—1290 的剧情年代一律穿帮（考证见 nk1-history/ceramics_notes.md）。
按商馆陈设改成当时泉州港最常见的几种釉，改釉不改形，罐里的香料、盘里的香料、笔筒里的毛笔一律不动：
  · 笔筒   (243,634)-(367,748)   → 龙泉窑粉青（书案文房器，灯下最显眼，取最体面的一种）
  · 香料罐 (1423,682)-(1553,795) → 龙泉窑粉青：新安船龙泉罐 170 多件；和前面的粉青盘成一套
  · 浅盘   (1253,786)-(1524,902) → 龙泉窑粉青：新安船（1323）龙泉器里盘占七成、30—40cm 大盘百余件
  · 提梁盖壶 (1112,368)-(1188,439) → 泉州磁灶窑酱釉：本地窑口，后案上和铜器、木船模同调，少一件浅色器
  · 右下大罐 (1529,733)-(1672,889) → 龙泉窑梅子青：暗处用更深、玻璃光更强的青，和前面的粉青器区分
  · 左后架带把罐 (577,394)-(657,454) → 龙泉窑粉青，原纹饰压成刻划花积釉（第 2 轮评审补上，见下）
  青白（影青）实测试过（香料罐、笔筒各一版）：这盏暖灯下读成灰白 / 灰褐素罐，看不出青白，最像「去了花的青花」
  （考证笔记 2.2 早有此判断），所以没用。
两件「拿不准」的实测判定（色品判据见下）：右下大罐是暗处的青花（白地色品 b=0.248 与已知青花白地同档，笔触偏蓝占比
0.25—0.30，是素器对照的 2 倍以上），一并处理。左后架带把罐色品上不是钴蓝（笔触不比地蓝，偏蓝占比 5.6%—6.8%，
低于 8% 门槛；地色 b=0.198 低于所有青花白地 0.217—0.254），但第 1 轮评审在 1x 整图里看它读作「褪色青花」：冷灰地
（比周围墙 b=0.144 冷得多）+ 暗石板色大朵缠枝花，靠同时对比被看成蓝花，而且和右架那件原青花盖壶同形——色品判据站得住、
观感判据不过，所以第 2 轮一并改：上龙泉粉青（地色照笔筒的做法），花纹比地子暗的部分压到三成（carve=0.30，
实测平均暗度 0.393→0.192，×0.49），暗处由积釉项染成更深的同色青，读作刻划花积釉；罐口插着的白色细长物（勺柄/钮）不动。
它左边的小盖罐、灯后那只罐是暗橄榄 / 褐色，评审也判不像青花，不动。
画里的玻璃罩煤油灯 (358,333)-(521,701) 也是穿帮，但不在本脚本范围，不动。

第 2 轮（评审意见逐条）：
  · jarL：见上；它不走偏蓝判据，单独用「器身 ΣG/ΣR」判是否已处理（judge="green"，原图 0.787 → 改后 0.860，门槛 0.84）。
  · 香料罐：r1 拟合底色把 2—8px 的笔触起伏也抹平了（评审口径 HF 11.1→4.0，哑、平，读成锡罐）。现在把原图白地自己的
    2—8px 相对起伏按位加回（白地处是它原位的肌理，花处从最近的平移位置借白地肌理、再与同谱段同幅度的各向同性噪声对半混合，
    免得少量白地被反复平移成织纹）；局部均值只在白地像素里算，花边光晕不进来。试过 1—6px（带出 JPEG 块边的格子）
    和花笔触内部自己的肌理（8px 尺度上带出花形暗斑），都弃用。靠灯一侧（左，原图白地列亮度峰 x≈1440）加一道淡竖向釉光，
    两个高斯（2.2px / 6px）叠成的剖面、上下沿渐隐、低频起伏，一半取场景光色，提亮后不超过原白地亮度。
  · 笔筒：a(x) 在器身内部放宽到 σ6px（离轮廓 15px 内渐变回 1.5px，列支撑内归一化），去掉淡竖条；肌理同上（k=1.3，轻一些）；
    肩下断续白点（r1 保留的白地高光，像崩釉）换成一道沿肩部弧线的连续釉光：逐列取原高光超出量作包络、横向 σ5px 平滑、
    峰值定为原峰的六成、左端 16px 渐隐。
  · 茶壶：右下腹青花点暗鬼影 (1164,424)(1168,425)(1172,419) 用周围一圈釉色的归一化模糊补平；提梁内那条冷灰线
    （x=1180，RGB≈80,62,52）B/R 压到 ≤0.45——4:2:0 色度是半分辨率、1px 线的色度改不动（只压色度时编码后仍 0.62），
    所以连同右侧透过提梁看到的暗背景一起压色度，再对线三通道等量减亮（Cb/Cr 不变、Y 降，B/R 随之降），编码后实测 0.48/0.43。
  · 浅盘、右下大罐算法没动（与第 1 轮输出只在和香料罐处理窗重叠处有差）。

判据（为什么不用绝对 HSV 蓝）：整画是一盏暖灯，钴蓝笔触实测多是 B<R 的冷灰，绝对口径（HSV 190—250°、S>0.18、V≥0.10）
在已知青花上只有 0.0%—6.0%，分不出来。改用与明暗无关的色品坐标 b=B/(R+G+B)：明暗只改亮度不改色品，钴料才让色品偏蓝。
「笔触」= 比就近白地（半径 10px 的 85 分位亮度）暗 12% 以上的像素；「偏蓝」= 它的 b 比就近白地的 b（只在白地像素里
归一化模糊）高 0.02 以上。两种口径每次运行都打印（绝对口径另按原器白地做白平衡再算一遍）。

做法（每件器物各自一个处理窗，互不相干）：
1. 轮廓：按放大图逐段描的外轮廓多边形（亚像素，笔筒/罐/盘/壶/大罐各一，壶挖掉提梁里的空当）4 倍超采样求覆盖率；
   融合 alpha 往里收 0.5px、羽化 0.6px（壶的提梁只有 2—3px 宽，不收）。内容物（毛笔、香料）用多边形挖掉，
   在「内容物外扩 6px」和「外轮廓内 2px」两条带里再加一道色品闸：比就近白地暖得多的像素（毛笔、香料、木桌）不改；
   器身内部不设闸（灯下受光面本来就暖，单凭暖度分不开受光瓷面和毛笔）。罐口里的暗内壁只改色品、不动亮度。
2. 去花：花 = 偏蓝 ×（比就近「不偏蓝像素」暗）——相对的是带着原来明暗的不偏蓝像素，所以阴影、足底暗部不算花；
   偏蓝像素连成片处的暖暗花心也算（4:2:0 色度只有半分辨率，花心色品常被拉偏）。
   花的位置换成「白地亮度场 ×（1+ 借来的白地笔触肌理）」：白地亮度场是白地像素的多尺度归一化模糊（1.5—12px 由细到粗补洞），
   肌理按平移贴图从同一件器物的白地里借（同一支笔画的）；颜色换成就近干净白地的色品。
   然后：残留小暗点（横竖都小于 7px）用灰度闭运算补平；花密处 1—8px 中频起伏压一半，免得原来更亮的白地笔触浮成补丁；
   笔筒、香料罐的直筒器身用干净白地拟合 Y≈a(x)·b(y)（回转体明暗只随横向位置变）作底色，1px 笔触肌理留七成；
   口沿下、肩下、足上的箍线（原图正是青花的蓝圈，也是器形的转折凹线）按逐件描的椭圆弧留一道淡暗线，线上断续残点横向抹匀。
3. 上釉：以原器白地为场景白点，逐像素乘釉的本色（保亮度的色比），再乘亮度系数（粉青 0.87、梅子青 0.82、酱釉 0.40，
   都不比它换掉的白瓷亮）；积釉处（凹处、箍线、轮廓两侧掠射处）色度加深、略压暗，受光最亮处色度变淡，低频厚薄不匀；
   粉青厚釉把 1px 笔触压两成半（莹润如玉）。镜面高光在去花之后找（0.7px 与 2.5px 两个尺度上比亮、且在器身亮度前 12%，
   连成片的受光笔触整条保留），保留原来的光源色（粉青留八成、梅子青九成、酱釉全留）——所以仍是亮釉，不是哑光；
   酱釉只留器身亮度前 1.5% 的几处，免得白地碎点在深釉上成白屑。
4. 写出：改动只落在器物所在的 MCU 里（本图 4:2:0，MCU=16x16）。有改动的 MCU 按行合并成若干矩形，逐块用原图同一套量化表
   编码，再用 jpegtran -drop 链式无损嵌回（右、下边缘不满一个 MCU 的块也可以）——块外 DCT 系数与原图逐字节一致
   （djpeg -nosmooth 解码块外 0 变动）；按 libjpeg/PIL 默认的 fancy upsampling 解码，块外紧贴的 1px 会因色度插值有极小
   变动，两种口径都打印。块里没改的像素送编码器时用 -nosmooth 解码值（色度是原样本按 2x2 复制，编码器 2x2 求平均正好取回），
   重编码几乎无损。fix_bg_customs_jar.write_jpeg 只处理 4:4:4（sampling==0），4:2:0 会退回整图重编码，所以这里另写了
   MCU 版；其他小工具（模糊、分位、HSV 蓝、Lab、肌理）从它 import 复用，没改它。

幂等：每件器物先过自己的判据——青花件量「偏蓝笔触占比」（笔触里 b 比就近白地高 0.02 的像素 / 器身像素），
原图 15.5%—40.2%、处理后 ≤3.7%，低于 SKIP_BELOW（8%）视为已处理；jarL 量器身 ΣG/ΣR，≥ GREEN_MIN（0.84）视为已上青釉。
过了判据的件跳过；六件全跳过就打印原因、不写任何文件、rc=0。渲染用固定随机种子，同一输入两次运行输出逐字节相同。
输出与输入同路径时必须加 --in-place 才写。注意：对第 1 轮成品（md5 72bfd08a…）跑，五件青花都判「已处理」跳过，
只会补做 jarL；要得到第 2 轮的全部改进，须从原图（c6be6b4 的 assets/bg_quanzhou_ledger.jpg，md5 670f4a49…）跑。

用法：
  python3 tools/art/fix_bg_ledger_qinghua.py --in-place           # 就地处理 assets/bg_quanzhou_ledger.jpg（已处理过则跳过）
  python3 tools/art/fix_bg_ledger_qinghua.py --out /tmp/cand.jpg  # 只出候选，不动仓库文件
  python3 tools/art/fix_bg_ledger_qinghua.py --src A.jpg --out B.jpg [--only brushpot,plate] [--glaze spicejar=qingbai]
自检数字（两种口径的蓝占比前后、器外平均绝对差、块外变动像素、边界 ΔE、白地同批像素亮度比与色比、内容物变动、
高光保留、肌理 HF3/MF9、器身肌理 std(Y−高斯σ3)（整器内缩 3px 与器身内框两种，右下大罐作参照）、器身 G/R、
jarL 纹饰对比）每次运行都会打印。一次约 1.5 分钟。
"""
import argparse
import os
import shutil
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image, ImageDraw, JpegImagePlugin

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fix_bg_customs_jar import (blur, blur_xy, hsv_blue, local_pct, luma, smoothstep,  # noqa: E402
                                srgb_to_lab, texture)

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DEFAULT_SRC = os.path.join(ROOT, "assets", "bg_quanzhou_ledger.jpg")
DEFAULT_OUT = DEFAULT_SRC
SIZE = (1672, 941)
JPEGTRAN = os.environ.get("NK1_JPEGTRAN") or shutil.which("jpegtran")  # libjpeg-turbo；取不到时写出前报错
DJPEG = os.environ.get("NK1_DJPEG") or shutil.which("djpeg")

# ---- 判据 ----
BLUE_HUE, BLUE_SAT, BLUE_VMIN = (190.0, 250.0), 0.18, 0.10     # 任务口径（与 fix_bg_customs_jar 相同）
GROUND_R, GROUND_Q = 10, 85          # 就近白地：半径 10px 的 85 分位亮度（大于花团半径）
STROKE_D = 0.12                      # 比白地暗 12% 以上算笔触
COBALT_DB = 0.02                     # 色品 b 比就近白地高 0.02 以上算偏蓝
SKIP_BELOW = 0.08                    # 偏蓝笔触占器身 < 8% 视为已处理（原图 15.5%–40.2%，处理后 ≤3.6%）

# ---- 釉 ----
# albedo：釉的本色相对白瓷（R=1），逐像素乘在原器白地上（场景白点）；k：亮度系数（白瓷=1）
# pool：积釉处色度加深倍数；hi：受光最亮处色度减淡；soft：粉青厚釉把笔触肌理压一点（莹润如玉）
# groove：箍线处积釉暗线深浅；groove_c：箍线处色度再加深；mid：花区 1–8px 中频起伏压掉的比例
# spec_q：保留原高光的亮度门槛（器身亮度分位）；深色釉只留最亮的几处，免得白地碎点在深釉上成白屑
# edge_c / edge_d：轮廓边色度加深 / 压暗；albedo_pool：积釉处（箍线、凹处）偏向的颜色（青白积釉闪水绿）
# spec_keep：高光保留原光源色的比例（粉青乳浊、高光软一点；深色釉全留）
# 青白一档实测过（笔筒、香料罐各试一次）：暖暗光下读成灰白 / 灰褐素罐，看不出是青白，也最像「去了花的青花」，
# 与考证笔记 2.2 的判断一致，所以最终没用上；留在表里供 --glaze 对照。
GLAZES = {
    "longquan_fen": dict(name="龙泉粉青", albedo=(1.0, 1.13, 1.04), k=0.87, pool=0.70, hi=0.45, soft=0.25, noise=0.18,
                         groove=0.22, groove_c=1.2, mid=0.5, spec_q=88, edge_c=0.9, edge_d=0.12, spec_keep=0.8),
    "longquan_mei": dict(name="龙泉梅子青", albedo=(1.0, 1.24, 1.04), k=0.82, pool=0.50, hi=0.40, soft=0.15, noise=0.18,
                         groove=0.22, groove_c=1.0, mid=0.4, spec_q=88, edge_c=0.6, edge_d=0.08, spec_keep=0.9),
    "qingbai": dict(name="青白（影青）", albedo=(1.0, 1.05, 1.06), albedo_pool=(1.0, 1.13, 1.22), k=0.97, pool=0.90,
                    hi=0.60, soft=0.0, noise=0.12, groove=0.28, groove_c=1.4, mid=0.5, spec_q=88, edge_c=0.6, edge_d=0.05,
                    spec_keep=1.0),
    "jiang": dict(name="磁灶酱釉", albedo=(1.0, 0.64, 0.40), k=0.40, pool=0.25, hi=0.35, soft=0.0, noise=0.10,
                  groove=0.15, groove_c=0.3, mid=0.5, spec_q=98.5, edge_c=0.2, edge_d=0.15, spec_keep=1.0),
}

# ---- 器物：外轮廓多边形（原图像素坐标，像素中心在 +0.5）、挖掉的内容物 / 孔、色品闸阈值 ----
# 色品闸：暖度 3(R−B)/(R+G+B) 比就近白地高出这个区间就渐渐不改（白地约 0.5；毛笔 +0.4、木桌/香料 +0.5 以上）
WARM_GATE = (0.22, 0.40)
OBJECTS = [
    dict(key="brushpot", label="笔筒", glaze="longquan_fen",
         outer=[(254.5, 641.0), (257.0, 638.5), (275.0, 637.6), (300.0, 637.2), (325.0, 637.4), (343.0, 638.2),
                (352.0, 640.0), (357.0, 644.0), (357.5, 651.0), (360.0, 655.0), (362.5, 659.0), (363.5, 664.0),
                (363.5, 700.0), (362.6, 712.0), (361.6, 725.0), (360.2, 732.0), (357.5, 737.5), (352.0, 740.5),
                (340.0, 741.8), (320.0, 742.6), (300.0, 742.8), (280.0, 742.4), (265.0, 741.4), (256.0, 740.0),
                (250.0, 737.0), (246.5, 732.0), (244.8, 725.0), (244.2, 700.0), (244.2, 675.0), (244.6, 664.0),
                (246.0, 657.5), (249.5, 652.0), (252.0, 647.0)],
         holes=[],
         contents=[[(262.0, 648.0), (275.0, 642.5), (300.0, 640.0), (330.0, 641.0), (347.0, 644.5), (351.0, 650.0),
                    (344.0, 654.5), (320.0, 657.0), (290.0, 657.0), (268.0, 654.5)]],
         grooves=[(247.0, 653.0, 305.0, 659.5, 362.0, 655.0, 1.1, 0.7),     # 唇下
                  (245.0, 666.0, 305.0, 671.0, 363.0, 666.0, 1.0, 0.45),    # 肩下
                  (250.0, 730.0, 305.0, 734.5, 360.0, 730.0, 0.9, 0.6),     # 足上两道
                  (253.0, 735.0, 305.0, 738.5, 357.0, 735.0, 0.9, 0.5)],
         cyl=dict(top=(246.0, 662.0, 305.0, 669.0, 363.0, 662.0), bottom=(248.0, 726.0, 305.0, 730.0, 361.0, 726.0), w=0.75,
                  a_sigma=6.0),            # r2：a(x) 放宽到 σ6px（器身内部），去掉 σ1.5 时拟合出来的淡竖条
         tex=dict(k=1.3, s=(1.8, 8.0)),   # r2：就地取原图 2–8px 中频笔触肌理加回器身（r1 拟合底色把它抹平了）
         # r2：肩下原白地残留的断续高光点（像崩釉）→ 沿肩部弧线连成一道渐隐的连续釉光，峰值压到原来的六成
         streaks=[dict(arc=(314.0, 673.0, 331.0, 675.0, 356.0, 668.8), band=3.4, w=0.8, sx=5.0, gain=0.6, fade=16.0)],
         warm_gate=WARM_GATE),
    dict(key="spicejar", label="香料罐", glaze="longquan_fen",
         outer=[(1424.5, 697.0), (1430.0, 690.0), (1440.0, 686.5), (1460.0, 684.0), (1480.0, 683.0), (1500.0, 683.5),
                (1520.0, 685.5), (1535.0, 689.0), (1545.0, 693.0), (1551.0, 698.0), (1552.0, 703.0), (1551.5, 710.0),
                (1550.6, 730.0), (1549.2, 750.0), (1547.8, 765.0), (1545.5, 776.0), (1540.5, 783.5), (1530.0, 787.8),
                (1510.0, 789.8), (1490.0, 790.6), (1470.0, 790.4), (1450.0, 789.4), (1437.0, 787.0), (1430.0, 782.5),
                (1427.5, 775.0), (1427.0, 760.0), (1426.5, 740.0), (1426.0, 720.0), (1425.0, 705.0)],
         holes=[],
         contents=[[(1435.0, 701.0), (1445.0, 694.0), (1470.0, 690.0), (1500.0, 690.0), (1525.0, 692.0), (1540.0, 697.0),
                    (1543.0, 703.0), (1535.0, 709.0), (1510.0, 713.0), (1480.0, 714.0), (1455.0, 713.0), (1440.0, 709.0)]],
         grooves=[(1428.0, 709.0, 1488.0, 720.5, 1549.0, 709.0, 1.1, 0.7),  # 口沿下两道
                  (1428.0, 714.0, 1488.0, 726.0, 1549.0, 714.0, 1.0, 0.45),
                  (1430.0, 772.0, 1488.0, 780.5, 1546.0, 772.0, 1.0, 0.6)],  # 足上
         cyl=dict(top=(1427.0, 704.0, 1488.0, 717.0, 1550.0, 704.0), bottom=(1429.0, 776.0, 1488.0, 787.0, 1546.0, 776.0), w=0.8,
                  a_sigma=3.0),
         tex=dict(k=2.0, s=(1.8, 8.0)),   # r2：器身中频肌理找回（评审：r1 太平，读成锡罐 / 哑光）；1–2px 带里是 JPEG 块边，不借
         # r2：靠灯一侧（左）一道淡竖向釉光：原图白地列亮度峰在 x≈1440（80 分位 92，r1 只剩 72）
         glaze_light=dict(x=1440.5, s=2.2, s2=6.0, a=0.16, a2=0.06),
         warm_gate=WARM_GATE),
    dict(key="plate", label="浅盘", glaze="longquan_fen",
         outer=[(1253.8, 826.0), (1256.0, 816.0), (1263.0, 806.0), (1275.0, 799.0), (1300.0, 792.0), (1325.0, 789.0),
                (1350.0, 788.0), (1375.0, 787.5), (1400.0, 788.5), (1425.0, 790.5), (1450.0, 793.5), (1470.0, 796.5),
                (1485.0, 799.5), (1500.0, 803.5), (1510.0, 808.0), (1517.0, 814.0), (1522.0, 821.0), (1524.0, 830.0),
                (1521.0, 837.0), (1516.0, 845.0), (1508.0, 855.0), (1497.0, 866.0), (1482.0, 878.0), (1465.0, 887.0),
                (1445.0, 894.0), (1425.0, 897.5), (1400.0, 899.0), (1380.0, 898.5), (1355.0, 896.5), (1333.0, 892.0),
                (1315.0, 885.0), (1300.0, 876.0), (1288.0, 867.0), (1275.0, 857.0), (1265.0, 848.0), (1258.0, 838.0)],
         holes=[],
         contents=[[(1296.0, 820.0), (1307.0, 813.0), (1324.0, 811.0), (1342.0, 810.0), (1357.0, 802.0), (1375.0, 798.0),
                    (1395.0, 798.0), (1418.0, 802.0), (1438.0, 806.0), (1452.0, 811.0), (1462.0, 818.0), (1466.0, 826.0),
                    (1466.0, 835.0), (1460.0, 843.0), (1448.0, 849.0), (1430.0, 851.0), (1400.0, 852.5), (1360.0, 851.5),
                    (1332.0, 848.5), (1310.0, 843.0), (1298.0, 835.0), (1293.0, 827.0)]],
         warm_gate=WARM_GATE),
    dict(key="teapot", label="提梁盖壶", glaze="jiang",
         outer=[(1141.5, 369.0), (1144.0, 367.5), (1148.0, 367.5), (1150.5, 369.5), (1151.0, 374.5), (1150.5, 378.0),
                (1158.0, 378.5), (1166.0, 379.5), (1170.5, 381.5), (1171.0, 384.5), (1168.5, 387.5),
                (1172.0, 389.5), (1176.5, 392.0), (1180.0, 390.5), (1184.5, 391.0), (1187.5, 394.0), (1188.4, 399.0),
                (1188.2, 404.0), (1187.8, 407.5), (1186.5, 411.0), (1185.0, 414.5), (1183.5, 416.5), (1181.0, 418.5),
                (1180.0, 420.5), (1178.5, 423.0), (1177.0, 426.0), (1175.2, 428.5), (1172.8, 430.5), (1170.0, 432.5),
                (1167.5, 435.0), (1163.0, 437.0), (1155.0, 438.2), (1145.0, 438.4), (1135.0, 437.4),
                (1127.0, 434.5), (1120.5, 430.0), (1115.5, 424.0), (1112.5, 417.0), (1111.5, 409.0), (1112.5, 401.0),
                (1115.0, 395.5), (1119.5, 391.5), (1125.0, 389.5),
                (1123.5, 386.5), (1123.2, 383.0), (1126.0, 380.5), (1133.0, 378.8), (1141.0, 378.2), (1141.0, 374.0)],
         holes=[[(1180.3, 397.0), (1182.5, 396.0), (1184.3, 398.0), (1184.6, 402.0), (1183.8, 406.5), (1182.0, 409.5),
                 (1180.6, 409.0), (1180.2, 403.0)]],
         contents=[], shrink=0.0, band=1,
         # r2：右下腹两粒原青花点的暗鬼影，用周围釉色补平
         spots=[(1164.6, 424.4, 2.8), (1168.3, 424.7, 1.9), (1172.6, 419.4, 2.2)],
         # r2：提梁内侧器身右缘那条 1–2px 冷灰亮线（RGB≈80,62,52，B/R≈0.65）压到 B/R≤0.45，读作暖色轮廓光而不是残留白地
         # 4:2:0 色度只有半分辨率、高频又量化得狠，只压这 1–2px 压不下去（实测编码后 B/R 仍 0.62）→ 连同右侧透过提梁看到的
         # 暗背景（中性灰 ≈(29,29,31)，周围墙是暖暗褐）一起压，凑满两个色度样本宽
         caps=[dict(poly=[(1179.3, 398.6), (1184.3, 398.6), (1184.3, 409.6), (1179.3, 409.6)], br=0.45, ymin=0.0,
                    ydim=0.55, yref=35.0)],
         warm_gate=None),     # 背后是暗墙、没有内容物；提梁只有 2–3px 宽，开闸会把整条梁剔掉留成白边
    dict(key="jarR", label="右下大罐", glaze="longquan_mei",
         outer=[(1549.0, 752.0), (1552.0, 746.0), (1560.0, 741.0), (1575.0, 737.0), (1600.0, 734.5), (1630.0, 733.5),
                (1660.0, 734.0), (1673.0, 734.5), (1673.0, 889.0), (1660.0, 889.0), (1630.0, 889.0), (1600.0, 887.0),
                (1575.0, 882.0), (1555.0, 872.0), (1541.0, 860.0), (1534.5, 846.0), (1531.2, 828.0), (1531.4, 810.0),
                (1533.5, 795.0), (1539.0, 783.0), (1546.0, 774.0), (1549.0, 765.0)],
         holes=[],
         contents=[],
         keep_luma=[[(1556.0, 752.0), (1565.0, 744.0), (1590.0, 740.0), (1620.0, 738.5), (1673.0, 738.5),
                     (1673.0, 769.0), (1640.0, 770.0), (1610.0, 769.0), (1580.0, 766.0), (1562.0, 760.0)]],
         warm_gate=WARM_GATE),
    # r2 新增：左后架带把罐。色品上笔触不比地蓝（偏蓝占比 5.6%，低于 8% 门槛），但整器冷灰地 + 暗石板色大朵缠枝花，
    # 在暖墙前靠同时对比读成「褪色青花」，且与右架原青花盖壶同形 → 改龙泉粉青，花纹比地子暗的部分压到三成
    # （实测平均暗度 ×0.49），积釉加深（pool 1.1）染成更深的同色青（刻划花积釉）。
    # 它不走偏蓝判据，单独用「器身 G/R」判是否已处理（judge="green"）。
    dict(key="jarL", label="左后架带把罐", glaze="longquan_fen", mode="carve", judge="green", carve=0.30, ground_r=16,
         glaze_over=dict(pool=1.10),
         outer=[(591.0, 398.5), (593.5, 396.3), (598.0, 395.4), (606.0, 395.0), (615.0, 394.7), (625.0, 394.7),
                (632.0, 395.0), (636.5, 396.3), (639.3, 397.3), (639.8, 399.0), (638.5, 400.5), (637.3, 402.0),
                (637.8, 403.3), (640.0, 404.2), (641.5, 405.2), (642.8, 406.2), (644.0, 407.2), (645.4, 408.2),
                (646.6, 409.0), (648.0, 409.3), (649.0, 408.4), (651.0, 407.6), (654.0, 407.8), (656.0, 408.6),
                (657.0, 410.5), (657.0, 414.0), (656.8, 418.0), (656.0, 420.0), (654.8, 421.6), (653.6, 423.0),
                (652.4, 424.5), (651.8, 426.0), (651.8, 429.0), (651.0, 431.0), (650.2, 433.0), (649.5, 435.0),
                (649.0, 437.0), (647.5, 439.0), (646.0, 441.0), (644.8, 442.5), (643.0, 444.3), (641.2, 446.0),
                (640.2, 447.5), (640.0, 450.5), (639.0, 451.8), (632.0, 452.8), (620.0, 453.3), (606.0, 453.8),
                (598.0, 453.6), (593.5, 452.6), (591.3, 451.2), (589.3, 449.3), (587.8, 447.3), (586.0, 445.3),
                (584.3, 443.2), (582.5, 441.0), (581.3, 439.0), (580.5, 437.0), (579.5, 435.0), (578.6, 433.0),
                (577.7, 431.0), (577.4, 428.0), (577.2, 424.0), (577.3, 420.0), (577.7, 417.0), (578.5, 414.2),
                (579.4, 412.5), (580.4, 411.0), (581.0, 409.6), (582.4, 408.3), (584.2, 407.0), (585.7, 406.0),
                (587.4, 405.0), (589.5, 404.4), (591.2, 403.8), (590.8, 401.5), (590.4, 400.0)],
         holes=[[(648.8, 410.7), (654.6, 410.7), (654.7, 414.0), (654.6, 418.5), (654.0, 420.2), (653.4, 421.4),
                 (652.5, 422.4), (651.6, 422.0), (650.9, 420.5), (650.2, 418.5), (649.6, 416.5), (649.4, 414.0),
                 (648.9, 412.0)]],
         contents=[[(618.8, 393.0), (621.6, 393.0), (621.6, 400.2), (618.8, 400.2)]],   # 插在罐口的细长物（勺柄/钮），不动
         keep_luma=[[(595.0, 397.2), (605.0, 396.7), (620.0, 396.5), (632.0, 396.9), (635.0, 398.2), (633.0, 400.0),
                     (620.0, 400.3), (605.0, 400.3), (596.0, 399.6)]],                    # 罐口里的暗内壁：只改色品
         warm_gate=WARM_GATE),
]
GREEN_MIN = 0.84                 # jarL：器身 G/R ≥ 0.84 视为已上青釉（原图 0.79）
SHIFTS_BIG = [(dx, 0) for dx in (7, -7, 12, -12, 18, -18, 25, -25, 33, -33, 42, -42, 52, -52)] + \
             [(dx, dy) for dy in (5, -5, 10, -10, 16, -16) for dx in (0, 9, -9, 18, -18, 30, -30, 45, -45)]
# 器身内框（避开口沿、箍线、足、轮廓）：肌理口径 std(Y − 高斯σ3) 在这里量，右下大罐（原生笔触基本没动）作参照
TEX_BOX = dict(brushpot=(255, 675, 352, 725), spicejar=(1436, 724, 1540, 772), plate=(1270, 852, 1500, 890),
               teapot=(1120, 395, 1175, 432), jarR=(1548, 780, 1650, 870), jarL=(588, 410, 640, 445))
MARGIN = 14                      # 处理窗外扩（模糊余量）
SEED = 1277


# ---------- 小工具 ----------
def poly_cover(polys, x0, y0, w, h, ss=4, shrink=0.0):
    """多边形覆盖率（ss 倍超采样）；shrink>0 时先按超采样像素腐蚀（往里收 shrink 像素）。"""
    if not polys:
        return np.zeros((h, w), np.float32)
    im = Image.new("L", (w * ss, h * ss), 0)
    d = ImageDraw.Draw(im)
    for P in polys:
        d.polygon([((x - x0) * ss, (y - y0) * ss) for x, y in P], fill=255)
    m = np.asarray(im) > 127
    k = int(round(shrink * ss))
    for _ in range(k):
        m = m & np.roll(m, 1, 0) & np.roll(m, -1, 0) & np.roll(m, 1, 1) & np.roll(m, -1, 1)
    return m.reshape(h, ss, w, ss).mean(axis=(1, 3)).astype(np.float32)


def ms_nblur(img, wt, sigmas=(1.5, 3.0, 6.0, 12.0)):
    """多尺度 mask 内归一化模糊：由粗到细，细尺度有足够支撑的地方用细尺度（补洞不糊白地）。"""
    ww = wt if img.ndim == 2 else wt[..., None]
    out = None
    for s in sorted(sigmas, reverse=True):
        num = blur(img * ww, s)
        den = blur(wt, s)
        v = num / np.maximum(den if img.ndim == 2 else den[..., None], 1e-5)
        if out is None:
            out = v
        else:
            a = smoothstep(0.08, 0.30, den)
            a = a if img.ndim == 2 else a[..., None]
            out = a * v + (1 - a) * out
    return out


def dilate(m, n):
    out = m.copy()
    for _ in range(n):
        out = out | np.roll(out, 1, 0) | np.roll(out, -1, 0) | np.roll(out, 1, 1) | np.roll(out, -1, 1)
    return out


def close_line(x, L, axis):
    """一维灰度闭运算（先取窗口最大再取最小），窗口长 L，沿 axis。"""
    r = L // 2
    mx = x.copy()
    for s in range(-r, r + 1):
        mx = np.maximum(mx, np.roll(x, s, axis))
    mn = mx.copy()
    for s in range(-r, r + 1):
        mn = np.minimum(mn, np.roll(mx, s, axis))
    return mn


def groove_field(ob):
    """逐件指定的箍线：每条是过 (左, 中, 右) 三点的抛物线（圆口正视成椭圆弧，前低两端高），
    横向两端渐隐，纵向高斯宽 w、强度 s。"""
    out = np.zeros((ob.h, ob.w), np.float32)
    yy, xx = np.mgrid[0:ob.h, 0:ob.w].astype(np.float32)
    X, Yc = xx + ob.x0 + 0.5, yy + ob.y0 + 0.5
    for xl, yl, xm, ym, xr, yr, w, s in ob.spec.get("grooves", []):
        c = np.polyfit([xl, xm, xr], [yl, ym, yr], 2)
        yc = np.polyval(c, X)
        g = s * np.exp(-0.5 * ((Yc - yc) / w) ** 2) * smoothstep(xl - 1.0, xl + 4.0, X) * (1 - smoothstep(xr - 4.0, xr + 1.0, X))
        out = np.maximum(out, g.astype(np.float32))
    return out * ob.core


def nblur1d(v, m, s):
    """一维 mask 内归一化模糊（列支撑之外的 0 不拉进来）。"""
    return blur((v * m)[None, :], s)[0] / np.maximum(blur(m[None, :].astype(np.float32), s)[0], 1e-4)


def cyl_shading(Y, w, ob, y0, y1, iters=8, a_sigma=1.5):
    """器身 y0–y1 行内用加权交替最小二乘拟合 Y ≈ a(x)·b(y)，返回整窗大小的拟合值。
    a 在器身内部按 a_sigma 平滑（r2：笔筒放宽到 6px 去淡竖条），离左右轮廓 3+2σ px 以内渐变回 1.5px，
    免得把轮廓边的暗部抹进器身；都用列支撑内归一化，不把窗外的 0 拉进来。b 按 3px 平滑。"""
    r0 = max(0, int(np.floor(y0 - ob.y0)) - 2)
    r1 = min(ob.h, int(np.ceil(y1 - ob.y0)) + 2)
    sub, ww = Y[r0:r1], w[r0:r1]
    sup = (ww.sum(0) > 0.5).astype(np.float32)
    idx = np.nonzero(sup)[0]
    xs = np.arange(ob.w, dtype=np.float32)
    dist = np.minimum(xs - idx.min(), idx.max() - xs) if idx.size else np.zeros_like(xs)
    t = smoothstep(3.0, 3.0 + 2.0 * a_sigma, dist) if a_sigma > 1.5 else np.zeros_like(xs)
    b = np.ones(r1 - r0, np.float32)
    a = np.ones(ob.w, np.float32)
    for _ in range(iters):
        a = (ww * sub * b[:, None]).sum(0) / np.maximum((ww * b[:, None] ** 2).sum(0), 1e-4)
        a1 = nblur1d(a, sup, 1.5)
        a = a1 if a_sigma <= 1.5 else a1 * (1 - t) + nblur1d(a, sup, a_sigma) * t
        b = (ww * sub * a[None, :]).sum(1) / np.maximum((ww * a[None, :] ** 2).sum(1), 1e-4)
        b = blur(b[:, None], 3.0)[:, 0]
    out = Y.copy()
    out[r0:r1] = a[None, :] * b[:, None]
    return out


def maxfilt(x, r=1):
    out = x.copy()
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            out = np.maximum(out, np.roll(np.roll(x, dy, 0), dx, 1))
    return out


def chroma_b(rgb):
    return (rgb[..., 2] + 1.0) / (rgb.sum(-1) + 3.0)


def warmth(rgb):
    return (rgb[..., 0] - rgb[..., 2]) / np.maximum(rgb.sum(-1), 3.0) * 3.0


SHIFTS = [(dx, 0) for dx in (7, -7, 11, -11, 15, -15, 20, -20, 26, -26, 33, -33)] + \
         [(dx, dy) for dy in (4, -4, 8, -8) for dx in (0, 9, -9, 17, -17, 28, -28)]


def shift_fill(h, ok, need, shifts=None):
    """平移贴图：need 处取最近一个平移后落在 ok（白地）上的肌理值。"""
    out = np.where(ok, h, 0.0).astype(np.float32)
    todo = need & ~ok
    for dx, dy in (shifts or SHIFTS):
        if not todo.any():
            break
        sh = np.roll(np.roll(h, dy, 0), dx, 1)
        so = np.roll(np.roll(ok, dy, 0), dx, 1)
        take = todo & so
        out[take] = sh[take]
        todo &= ~take
    return out, todo


def region_mid(Y, R, s):
    """区域内相对中频起伏：细、粗两级模糊都只在区域 R 的像素里做归一化，区域边界的台阶不进来。"""
    w = R.astype(np.float32)
    fine = ms_nblur(Y, w, (s[0], 2 * s[0]))
    base = ms_nblur(Y, w, (s[1], 2 * s[1], 4 * s[1]))
    return np.clip(fine / np.maximum(base, 1.0) - 1.0, -0.25, 0.25)


def borrow_mid(Y, ok, need, s, rng, mix=0.5):
    """r2：中频肌理（s[0]–s[1] px 尺度的相对起伏）取原图自己的白地笔触肌理。
    白地（ok）处就是它原位的肌理；局部均值只在白地像素里做归一化模糊，所以花边的白地不会带出花形的光晕。
    花处从最近的平移位置借白地肌理（SHIFTS_BIG），再与同谱段、同幅度的各向同性滤波噪声按 mix 混合，
    免得少量白地被反复平移后成片重复（织纹感）；借不到的全用噪声。
    试过花笔触内部自己的肌理（单独归一化、按白地幅度定标）：8px 尺度上带出花形暗斑（鬼影），弃用。
    返回相对起伏场 M（≈0 均值，乘到亮度上用）与统计。"""
    src = erode(ok, 1)
    M = region_mid(Y, ok, s)
    sd = float(M[src].std()) if src.any() else 0.0
    Mf, left = shift_fill(M, src, need, SHIFTS_BIG)
    n = rng.normal(0, 1, Y.shape).astype(np.float32)
    n = blur(n, s[0]) - blur(n, s[1])
    n *= sd / (float(n.std()) + 1e-6)
    borrowed = need & ~src & ~left
    # 平移借来的与噪声按 mix 混合（两个独立场按 √ 权重混合，幅度不变）
    a, b = np.sqrt(1.0 - mix), np.sqrt(mix)
    Mf = np.where(borrowed, a * Mf + b * n, Mf)
    Mf[left] = n[left]
    Mf = blur(Mf, 0.5)                       # 借来的块与块之间的接缝软一点
    return Mf, dict(src=int(src.sum()), need=int(need.sum()), borrowed=int(borrowed.sum()), left=int(left.sum()), sd=sd)


def arc_y(p, X):
    """过 (左, 中, 右) 三点的抛物线（圆口正视的椭圆弧）。"""
    return np.polyval(np.polyfit(p[0::2], p[1::2], 2), X)


# ---------- 判据 ----------
class Obj:
    def __init__(self, spec):
        self.spec = spec
        xs = [p[0] for p in spec["outer"]]
        ys = [p[1] for p in spec["outer"]]
        self.x0 = max(0, int(np.floor(min(xs))) - MARGIN)
        self.y0 = max(0, int(np.floor(min(ys))) - MARGIN)
        self.x1 = min(SIZE[0], int(np.ceil(max(xs))) + MARGIN)
        self.y1 = min(SIZE[1], int(np.ceil(max(ys))) + MARGIN)
        w, h = self.x1 - self.x0, self.y1 - self.y0
        self.w, self.h = w, h
        args = (self.x0, self.y0, w, h)
        cov = poly_cover([spec["outer"]], *args)
        hole = poly_cover(spec.get("holes", []), *args)
        cont = poly_cover(spec.get("contents", []), *args)
        self.C = np.clip(cov - hole, 0, 1)                            # 真实覆盖率
        shrink = spec.get("shrink", 0.5)
        inner = poly_cover([spec["outer"]], *args, shrink=shrink) if shrink > 0 else cov
        A = np.clip(blur(inner, 0.6), 0, 1) * (self.C > 0)
        self.cont = np.clip(blur(cont, 0.7), 0, 1)
        self.A = A * (1 - self.cont) * (1 - np.clip(blur(hole, 0.5), 0, 1)) * (hole < 0.5)
        self.A[self.A < 1.0 / 512] = 0.0
        self.core = (self.C > 0.99) & (cont < 0.01) & (hole < 0.01)
        # 保留原亮度的区域（罐口里的暗内壁等）：只改色品、上釉，不去花不补亮
        self.keep = np.clip(blur(poly_cover(spec.get("keep_luma", []), *args), 1.0), 0, 1)
        # 色品闸只在「内容物外扩 6px」与「外轮廓内 band px」这两条带里起作用；器身内部一律照改
        # （灯下受光面本来就暖，单凭暖度分不开受光瓷面和毛笔）
        near_cont = dilate(cont > 0.01, 6) if spec.get("contents") else np.zeros_like(self.core)
        band = (self.C > 0) & ~erode(self.C >= 0.99, spec.get("band", 2))
        self.zone = near_cont | band
        # r2：色品封顶区（茶壶提梁内冷线）不受 alpha 限制，单独记覆盖率
        self.capcov = poly_cover([c["poly"] for c in spec.get("caps", [])], *args)

    def grid(self):
        """像素中心的原图坐标 (X, Y)。"""
        yy, xx = np.mgrid[0:self.h, 0:self.w].astype(np.float32)
        return xx + self.x0 + 0.5, yy + self.y0 + 0.5

    def win(self, img):
        return img[self.y0:self.y1, self.x0:self.x1]

    def full(self, arr, fill=0):
        out = np.full((SIZE[1], SIZE[0]) + arr.shape[2:], fill, arr.dtype)
        out[self.y0:self.y1, self.x0:self.x1] = arr
        return out


def ground_fields(rgb, core):
    """就近白地亮度 Wg、暗度 d、色品 b 与就近白地色品差 db。"""
    Y = luma(rgb)
    Wg = local_pct(Y, core, GROUND_R, GROUND_Q)
    d = 1.0 - Y / np.maximum(Wg, 1.0)
    cb = chroma_b(rgb)
    g0 = (core & (d < 0.10)).astype(np.float32)
    cbg = ms_nblur(cb, g0, (2.0, 4.0, 8.0))
    return Y, Wg, d, cb, cb - cbg


def cobalt_share(rgb, core):
    """偏蓝笔触占器身比例（本脚本的判据与幂等口径）。"""
    Y, Wg, d, cb, db = ground_fields(rgb, core)
    m = core & (Y > 6)
    return float(((d > STROKE_D) & (db > COBALT_DB))[m].mean())


def blue_abs(rgb, core):
    return float(hsv_blue(np.clip(rgb, 0, 255).astype(np.uint8), BLUE_VMIN)[core].mean())


def blue_wb(rgb, core, white):
    """按原器白地（白地像素的平均色）白平衡后，再用任务口径数蓝像素。"""
    wb = np.clip(rgb / white * float(white.mean()), 0, 255).astype(np.uint8)
    return float(hsv_blue(wb, BLUE_VMIN)[core].mean())


def green_ratio(rgb, ob):
    """器身 ΣG/ΣR（jarL 的判据：原图冷灰地 0.79，上龙泉青后 ≥0.84）。"""
    Y = luma(rgb)
    m = ob.core & (Y > 12) & (ob.keep < 0.5)
    return float(rgb[..., 1][m].sum() / max(rgb[..., 0][m].sum(), 1.0))


def judge(ob, rgb):
    """幂等判据：返回 (是否仍需处理, 说明)。青花件看偏蓝笔触占比，jarL 看器身 G/R。"""
    if ob.spec.get("judge") == "green":
        g = green_ratio(rgb, ob)
        return g < GREEN_MIN, "器身 G/R %.3f（< %.2f 为未上青釉）" % (g, GREEN_MIN)
    share = cobalt_share(rgb, ob.core)
    return share >= SKIP_BELOW, "偏蓝笔触占器身 %.1f%%（≥ %.0f%% 为青花）" % (100 * share, 100 * SKIP_BELOW)


def hf_std(rgb, core):
    """肌理口径（r2 自定）：器身内缩 3px，亮度减高斯 σ3 后的标准差（亮度单位）。"""
    Y = luma(rgb)
    return float((Y - blur(Y, 3.0))[erode(core, 3)].std())


def carve_ground(rgb, ob):
    """刻花件（jarL）的地子亮度场：比就近（半径 ground_r、85 分位）白地暗不到 8% 的像素做多尺度归一化模糊。"""
    Y = luma(rgb)
    Wg = local_pct(Y, ob.core, ob.spec.get("ground_r", GROUND_R), GROUND_Q)
    d = 1.0 - Y / np.maximum(Wg, 1.0)
    gw = (ob.core & (d < 0.08) & (ob.keep < 0.5)).astype(np.float32)
    return Y, Wg, d, gw


# ---------- 渲染 ----------
def glaze_of(spec):
    g = dict(GLAZES[spec["glaze"]])
    g.update(spec.get("glaze_over", {}))
    return g


def warm_gate_field(rgb, ob, d):
    """色品闸（只在内容物周边与外轮廓带里）：比就近白地暖得多的像素不改（木桌、毛笔、香料、暖墙）。"""
    spec = ob.spec
    if not spec["warm_gate"]:
        return np.ones(rgb.shape[:2], np.float32)
    wm = warmth(rgb)
    g0 = (ob.core & (d < 0.10)).astype(np.float32)
    wm_g = ms_nblur(wm, g0, (3.0, 6.0, 12.0))
    gate = 1.0 - smoothstep(spec["warm_gate"][0], spec["warm_gate"][1], wm - wm_g)
    return np.where(ob.zone, gate, 1.0).astype(np.float32)


def decorate_qinghua(rgb, ob, G_, gate, rng):
    """青花件：去花（亮度换白地、色品换白地色品），返回去花后的 rgb_d 与高光、箍线等中间量。"""
    spec = ob.spec
    core = ob.core
    Y, Wg, d, cb, db = ground_fields(rgb, core)
    # 1) 花的软权重：偏蓝 × 偏暗。「偏暗」相对的是就近「不偏蓝像素」的亮度（它带着器身原来的明暗），
    #    所以阴影、足底暗部不算花，只有蓝笔触算；花团内部（偏蓝覆盖连成片处）的暖暗花心也算
    inside = (ob.C > 0.3).astype(np.float32)
    keep = ob.keep
    Pc = smoothstep(0.008, 0.035, db)
    Pn = smoothstep(0.15, 0.45, blur(maxfilt(Pc, 1), 1.5))
    nb = (core & (db < 0.004)).astype(np.float32)
    Gnb = ms_nblur(Y, nb, (2.0, 4.0, 8.0, 16.0))
    d2 = 1.0 - Y / np.maximum(Gnb, 1.0)
    Pd = smoothstep(0.0, 0.14, d2)
    P = np.clip(Pd * np.maximum(Pc, Pn) * inside * gate * (1 - keep), 0, 1)
    P = np.maximum(P, blur(P, 0.6) * 0.8)                      # 笔触边缘的 JPEG 过渡圈
    # 高光（仅用来把它们排除出白地统计；最终保留哪些高光在去花之后再定）
    Yb2 = blur(Y, 2.0)
    top = np.percentile(Y[core], G_["spec_q"])
    spec0 = smoothstep(1.06, 1.22, Y / np.maximum(Yb2, 1.0)) * smoothstep(0.85 * top, 1.15 * top, Y) * inside
    # 2) 去花：白地亮度场 + 借白地肌理 + 白地色品（只取干净白地：不偏蓝、不暗、离花 1px 以上）
    wgt = inside * (1 - P) ** 2 * (1 - spec0)
    Gl = ms_nblur(Y, wgt)
    Gs = ms_nblur(Y, wgt, (1.5, 3.0))
    hrel = np.clip(Y / np.maximum(Gs, 1.0) - 1.0, -0.22, 0.22)
    clean = erode((P < 0.03) & (db < 0.008) & (d2 < 0.15) & (spec0 < 0.1) & (ob.C > 0.9) & (gate > 0.9) & (Y > 8), 1)
    need = (P > 0.02) & (ob.C > 0.0)
    hfill, left = shift_fill(hrel, clean, need)
    hfill[left] = 0.0
    white = ms_nblur(rgb / np.maximum(Y, 1.0)[..., None], clean.astype(np.float32), (3.0, 6.0, 12.0, 24.0))
    white = white / np.maximum(luma(white), 1e-3)[..., None]
    Yp = Gl * (1.0 + hfill)
    # 亮度只在「偏蓝且偏暗」处换（P）；色品在所有偏蓝处都换成白地色品（Pch，不乘暗度），浅蓝笔触边也不留蓝
    Pch = np.clip(np.maximum(smoothstep(0.003, 0.020, db), Pn) * inside * gate, 0, 1)
    Yd0 = Y * (1 - P) + Yp * P
    # 2b) 残点：花心没认全留下的小暗点（横竖两个方向都小于 7px 的暗斑）用灰度闭运算补平；
    #     横线、竖线（口沿、肩、足的转折线）闭运算不掉，照留
    near = dilate(P > 0.05, 3) & core & (keep < 0.5)
    Yds = np.minimum(close_line(Yd0, 7, 1), close_line(Yd0, 7, 0))
    wsp = smoothstep(0.05, 0.16, (Yds - Yd0) / np.maximum(Yds, 1.0)) * near
    Yd0 = Yd0 + wsp * (Yds - Yd0)
    Pch = np.maximum(Pch, wsp)
    # 2c) 花区中频压一半：补上的地是周边白地的平均，原来更亮的白地笔触会浮成一块块「补丁」；
    #     在花密的区域把 1–8px 尺度的起伏压到一半（大尺度明暗与 1px 笔触肌理不动）
    Z = np.clip(blur((P > 0.3).astype(np.float32), 3.0) * 1.6, 0, 1) * inside * (1 - keep)
    S = ms_nblur(Yd0, inside, (4.0, 8.0))
    B1 = blur(Yd0, 1.0)
    Yd0 = S + (1.0 - G_["mid"] * Z) * (B1 - S) + (Yd0 - B1)
    # 2c') 直筒器身（笔筒、香料罐）：明暗基本只随横向位置变（回转体、光从左前来），
    #      用干净白地拟合 Y ≈ a(x)·b(y) 作为器身底色，把白地笔触留下的亮块并进去；1px 笔触肌理照留
    Mtex, tex_info, wzt = None, None, None
    if spec.get("cyl"):
        cz = spec["cyl"]
        Xc = ob.x0 + np.arange(ob.w, dtype=np.float32)[None, :] + 0.5
        Yc = ob.y0 + np.arange(ob.h, dtype=np.float32)[:, None] + 0.5
        yt = arc_y(cz["top"], Xc)          # 上沿弧（口沿/肩下的椭圆弧）
        yb = arc_y(cz["bottom"], Xc)
        Ycyl = cyl_shading(Yd0, (clean & (spec0 < 0.1)).astype(np.float32) + 0.05 * core, ob,
                           min(cz["top"][1::2]), max(cz["bottom"][1::2]), a_sigma=cz.get("a_sigma", 1.5))
        wz0 = smoothstep(yt, yt + 4.0, Yc) * (1 - smoothstep(yb - 4.0, yb, Yc)) * erode(core, 2) * (1 - keep)
        wz = blur((cz["w"] * wz0).astype(np.float32), 1.0)
        fine = 1.0 + 0.7 * (Yd0 / np.maximum(blur(Yd0, 1.0), 1.0) - 1.0)
        Yd0 = Yd0 * (1 - wz) + Ycyl * fine * wz
        # r2：拟合底色把 2–8px 的笔触起伏也抹平了（评审：HF 11.1→4.0，读成锡罐 / 哑光）。
        #     从原图干净白地平移借中频肌理，按拟合权重加回器身（干净白地处就是它自己原来的肌理，花处是借来的）
        if spec.get("tex"):
            # 肌理来源比「干净白地」放宽（花密的器身上干净白地只剩几十个像素，借来会成片重复）：
            # 不偏蓝（db<0.015）、不在花里（P<0.08）、非高光、器身拟合区内；局部均值只在这些像素里算
            ok = (P < 0.08) & (db < 0.015) & (spec0 < 0.2) & (ob.C > 0.9) & (wz0 > 0.5) & (Y > 6) & (gate > 0.9)
            Mtex, tex_info = borrow_mid(Y, ok, wz > 0.01, spec["tex"]["s"], rng, spec["tex"].get("mix", 0.5))
            wzt = np.clip(wz / cz["w"], 0, 1)
    # 2d) 口沿、肩、足的箍线（逐件指定的弧线）：原图这里是青花的蓝圈，也正是器形的转折凹线；
    #     釉在凹线里积厚，留一道淡暗线，上釉时色度加深
    gdark = groove_field(ob) * (1 - keep)
    gsm = np.clip(gdark * 2.0, 0, 1)                    # 箍线上残留的断续暗点顺着线横向抹匀，成一道连续的凹线
    Yd0 = Yd0 * (1 - gsm) + blur_xy(Yd0, 3.0, 0.3) * gsm
    Yd0 = Yd0 * (1.0 - G_["groove"] * gdark)
    # 镜面高光（去花之后再找：白地小岛夹在蓝花里时并不是高光）。在 0.7px 与 2.5px 两个尺度上比亮，
    # 连成片的受光笔触整条保留，不会只留几个亮点、断成划痕。借来的肌理在找完高光之后才加，免得肌理亮点被当成高光
    Ys = blur(Yd0, 0.7)
    spec_m = smoothstep(1.04, 1.16, Ys / np.maximum(blur(Yd0, 2.5), 1.0)) * smoothstep(0.80 * top, 1.10 * top, Ys) * inside
    if Mtex is not None:
        Yd0 = Yd0 * (1.0 + spec["tex"]["k"] * Mtex * wzt * (1 - gdark))
    chrom = rgb / np.maximum(Y, 1.0)[..., None]
    chrom = chrom * (1 - Pch)[..., None] + white * Pch[..., None]
    chrom = chrom / np.maximum(luma(chrom), 1e-3)[..., None]
    rgb_d = Yd0[..., None] * chrom
    return rgb_d, spec_m, top, gdark, dict(P=P, white=white, groove=gdark, wsp=wsp, Wg=Wg, tex=tex_info)


def decorate_carve(rgb, ob, G_, gate, rng):
    """r2：刻花件（jarL）。原纹饰不是钴蓝而是暗石板色，不去掉，改成龙泉刻划花积釉：
    比地子暗的部分按 carve（0.40）压对比（亮的不动），整器色品换成地子色品，再和别的件一样上釉；
    积釉处（原纹饰的暗处）由上釉步骤的 pool 项加深成更深的同色青。"""
    spec = ob.spec
    core, keep = ob.core, ob.keep
    inside = (ob.C > 0.3).astype(np.float32)
    Y, Wg, d, gw0 = carve_ground(rgb, ob)
    top = np.percentile(Y[core], G_["spec_q"])
    spec0 = smoothstep(1.06, 1.22, Y / np.maximum(blur(Y, 2.0), 1.0)) * smoothstep(0.85 * top, 1.15 * top, Y) * inside
    gw = gw0 * (spec0 < 0.1)
    Gg = ms_nblur(Y, gw, (2.0, 4.0, 8.0, 16.0))
    rel = 1.0 - Y / np.maximum(Gg, 1.0)
    P = smoothstep(0.02, 0.10, rel) * inside * (1 - keep) * gate * (1 - spec0)
    Yd0 = Y + (1.0 - spec["carve"]) * np.maximum(Gg - Y, 0.0) * P
    white = ms_nblur(rgb / np.maximum(Y, 1.0)[..., None], gw, (3.0, 6.0, 12.0, 24.0))
    white = white / np.maximum(luma(white), 1e-3)[..., None]
    Pch = inside * gate
    chrom = rgb / np.maximum(Y, 1.0)[..., None]
    chrom = chrom * (1 - Pch)[..., None] + white * Pch[..., None]
    chrom = chrom / np.maximum(luma(chrom), 1e-3)[..., None]
    rgb_d = Yd0[..., None] * chrom
    gdark = groove_field(ob) * (1 - keep)
    Ys = blur(Yd0, 0.7)
    spec_m = smoothstep(1.04, 1.16, Ys / np.maximum(blur(Yd0, 2.5), 1.0)) * smoothstep(0.80 * top, 1.10 * top, Ys) * inside
    return rgb_d, spec_m, top, gdark, dict(P=P, white=white, groove=gdark, wsp=np.zeros_like(P), Wg=Wg, tex=None)


def add_streak(rgb, col, sm, ob, st):
    """r2：把弧线带里断续的原高光点（白地残留，像崩釉）换成一道沿弧线的连续釉光：
    逐列取带内高光超出量的最大值作包络，横向高斯 sx 平滑后峰值定为原峰的 gain 倍，左端 fade px 渐隐；
    纵向是宽 w 的高斯；颜色取原高光的光源色。带内原高光不再保留。"""
    X, Yc = ob.grid()
    xl, xr = st["arc"][0], st["arc"][4]
    dy = Yc - arc_y(st["arc"], X)
    inx = smoothstep(xl - 3.0, xl, X) * (1 - smoothstep(xr, xr + 3.0, X))
    bandm = (1 - smoothstep(st["band"], st["band"] + 1.5, np.abs(dy))) * inx * (ob.C > 0.3)
    ex = np.maximum(luma(rgb) - luma(col), 0.0) * sm * bandm
    peak = float(ex.max())
    if peak <= 0:
        return col, sm
    env = ex.max(axis=0)
    env_s = blur(env[None, :], st["sx"])[0]
    env_s *= st["gain"] * peak / max(float(env_s.max()), 1e-3)
    xs = X[0]
    env_s *= smoothstep(xl, xl + st["fade"], xs) * (1 - smoothstep(xr - 3.0, xr, xs))
    prof = np.exp(-0.5 * (dy / st["w"]) ** 2) * inx
    lc = (rgb * ex[..., None]).sum((0, 1)) / max(float((luma(rgb) * ex).sum()), 1e-3)    # 光源色（亮度归一）
    col = col + (env_s[None, :] * prof)[..., None] * lc[None, None, :]
    return col, sm * (1 - bandm)


def add_glaze_light(col, ob, gl, white, Wg):
    """r2：直筒器身靠灯一侧的淡竖向釉光（粉青乳浊，宽而软）：两个高斯叠成的横向剖面 × 上下沿渐隐 × 低频起伏，
    颜色一半取场景光色（原白地色品）一半保留釉色；提亮后的亮度不超过原白地（就近 85 分位）。"""
    X, Yc = ob.grid()
    cz = ob.spec["cyl"]
    yt, yb = arc_y(cz["top"], X), arc_y(cz["bottom"], X)
    env = smoothstep(yt + 2.0, yt + 9.0, Yc) * (1 - smoothstep(yb - 10.0, yb - 2.0, Yc))
    rng = np.random.default_rng(SEED + 7)
    nz = blur(rng.normal(0, 1, (ob.h, 1)).astype(np.float32), 4.0)
    mod = 1.0 + 0.25 * nz / (float(nz.std()) + 1e-6)
    prof = gl["a"] * np.exp(-0.5 * ((X - gl["x"]) / gl["s"]) ** 2) + gl["a2"] * np.exp(-0.5 * ((X - gl["x"]) / gl["s2"]) ** 2)
    L = np.clip(prof * env * mod, 0, None) * erode(ob.core, 1)
    Yc_ = luma(col)
    Yn = np.minimum(Yc_ * (1.0 + L), np.maximum(Yc_, Wg))
    cc = col / np.maximum(Yc_, 1.0)[..., None]
    return col + (Yn - Yc_)[..., None] * (0.5 * white + 0.5 * cc)


def fill_spots(col, ob, spots):
    """r2：小暗点（原青花点的鬼影）用周围一圈釉色的归一化模糊补平（取样圈避开所有暗点）。"""
    X, Yc = ob.grid()
    dists = [np.hypot(X - sx, Yc - sy) for sx, sy, _ in spots]
    near_any = np.zeros(X.shape, bool)
    for dist, (_, _, r) in zip(dists, spots):
        near_any |= dist <= r + 0.8
    for dist, (_, _, r) in zip(dists, spots):
        D = (1 - smoothstep(r - 0.6, r + 0.6, dist)) * (ob.C > 0.5)
        ring = ((dist < r + 3.5) & ~near_any & ob.core).astype(np.float32)
        fill = ms_nblur(col, ring, (1.5, 3.0))
        col = col * (1 - D[..., None]) + fill * D[..., None]
    return col


def render(src, ob, seed=SEED):
    spec = ob.spec
    G_ = glaze_of(spec)
    rgb = ob.win(src).astype(np.float32)
    core, keep = ob.core, ob.keep
    rng = np.random.default_rng(seed + sum(map(ord, spec["key"])))
    Y0 = luma(rgb)
    d0 = 1.0 - Y0 / np.maximum(local_pct(Y0, core, GROUND_R, GROUND_Q), 1.0)
    gate = warm_gate_field(rgb, ob, d0)
    inside = (ob.C > 0.3).astype(np.float32)
    deco = decorate_carve if spec.get("mode") == "carve" else decorate_qinghua
    rgb_d, spec_m, top, gdark, dbg = deco(rgb, ob, G_, gate, rng)
    Yd = luma(rgb_d)
    if G_["soft"] > 0:                                             # 粉青厚釉：笔触肌理压一点
        Yd_s = ms_nblur(Yd, inside, (0.9,))
        rgb_d = rgb_d * (1 + G_["soft"] * (Yd_s / np.maximum(Yd, 1.0) - 1.0))[..., None]
        Yd = luma(rgb_d)
    base = ms_nblur(Yd, inside * (1 - spec_m), (4.0, 8.0))
    rec = np.clip(1.0 - Yd / np.maximum(base, 1.0), 0.0, 0.5) / 0.5          # 凹处/暗处 → 积釉
    lit = np.clip(Yd / np.maximum(np.percentile(Yd[core], 97), 1.0), 0, 1)
    n = blur(rng.normal(0, 1, Yd.shape).astype(np.float32), 3.0)
    n /= n.std() + 1e-6
    # 轮廓边：回转体两侧掠射看穿的釉层厚，色更深、略暗（龙泉厚釉尤其明显）
    edge = (1.0 - smoothstep(0.55, 0.97, blur(ob.C, 3.5))) * inside * (1 - keep)
    f = (1.0 + G_["pool"] * rec + G_["noise"] * n - G_["hi"] * smoothstep(0.6, 1.0, lit)
         + G_["groove_c"] * gdark + G_["edge_c"] * edge)
    f = np.clip(f, 0.3, 2.6)[..., None]
    alb = np.array(G_["albedo"], np.float32)
    alb = alb / float(luma(alb))
    albp = np.array(G_.get("albedo_pool", G_["albedo"]), np.float32)
    albp = albp / float(luma(albp))
    tp = np.clip(G_["groove_c"] * gdark + 0.5 * G_["pool"] * rec, 0, 1.5)[..., None]   # 积釉处偏向「积釉色」
    ratio = 1.0 + f * (alb - 1.0) + tp * (albp - alb)
    ratio = ratio / np.maximum(luma(ratio), 1e-3)[..., None]
    col = rgb_d * ratio * (G_["k"] * (1.0 - G_["edge_d"] * edge))[..., None]
    # 镜面高光：保留原光源色与亮度（深色釉上高光对比更强，读成亮面）
    sm = spec_m * G_["spec_keep"]
    for st in spec.get("streaks", []):                 # r2：断续高光点 → 连续渐隐釉光
        col, sm = add_streak(rgb, col, sm, ob, st)
    col = col * (1 - sm[..., None]) + rgb * sm[..., None]
    if spec.get("glaze_light"):                        # r2：靠灯一侧的淡竖向釉光
        col = add_glaze_light(col, ob, spec["glaze_light"], dbg["white"], dbg["Wg"])
    if spec.get("spots"):                              # r2：补平青花点鬼影
        col = fill_spots(col, ob, spec["spots"])
    A = (ob.A * gate)[..., None]
    out = rgb * (1 - A) + col * A
    for cp in spec.get("caps", []):                    # r2：色品封顶（B/R ≤ br），不受 alpha 限制
        cov = poly_cover([cp["poly"]], ob.x0, ob.y0, ob.w, ob.h)
        c = cov * smoothstep(cp["ymin"] - 5.0, cp["ymin"] + 5.0, luma(out))
        out[..., 2] = out[..., 2] * (1 - c) + np.minimum(out[..., 2], cp["br"] * out[..., 0]) * c
        if cp.get("ydim"):
            # 色度是半分辨率、1px 细线的色度改不动；亮度是全分辨率 → 三通道等量减亮（Cb/Cr 不变、Y 下降，B/R 随之下降），
            # 比 yref 亮的部分压掉 ydim 的比例，线仍比壶身亮一点，读作淡淡的轮廓光
            Yo = luma(out)
            out = out - (cp["ydim"] * np.maximum(Yo - cp["yref"], 0.0) * cov)[..., None]
    touch = (ob.A > 0) | (ob.capcov > 0)
    dbg.update(spec=spec_m, gate=gate)
    return np.clip(out + 0.5, 0, 255).astype(np.uint8), touch, dbg


# ---------- 写出（MCU 对齐、多矩形链式 jpegtran -drop） ----------
def mcu_size(im):
    layers = im.layer            # [(id, h, v, qt), ...]
    hmax = max(l[1] for l in layers)
    vmax = max(l[2] for l in layers)
    return 8 * hmax, 8 * vmax


def changed_mcu_rects(mask, mw, mh):
    """有改动的 MCU → 按行合并连续段，再把上下相同的段并成矩形。返回像素矩形（右/下边缘裁到图内）。"""
    H, W = mask.shape
    ny, nx = -(-H // mh), -(-W // mw)
    pad = np.zeros((ny * mh, nx * mw), bool)
    pad[:H, :W] = mask
    blk = pad.reshape(ny, mh, nx, mw).any(axis=(1, 3))
    runs = []
    for j in range(ny):
        i = 0
        while i < nx:
            if blk[j, i]:
                s = i
                while i < nx and blk[j, i]:
                    i += 1
                runs.append((j, s, i))
            else:
                i += 1
    rects = []                    # (j0, j1, s, e)
    for j, s, e in runs:
        for r in rects:
            if r[1] == j and r[2] == s and r[3] == e:
                r[1] = j + 1
                break
        else:
            rects.append([j, j + 1, s, e])
    out = []
    for j0, j1, s, e in rects:
        out.append((s * mw, j0 * mh, min(e * mw, W), min(j1 * mh, H)))
    return out, blk


def _drop_all(src_path, inp, rects, qt, sampling, td, tag):
    if not JPEGTRAN:
        raise SystemExit("找不到 jpegtran：装 libjpeg-turbo（放进 PATH），或设环境变量 NK1_JPEGTRAN 指向它")
    cur = src_path
    for i, (x0, y0, x1, y1) in enumerate(rects):
        drop = os.path.join(td, "%s_drop%d.jpg" % (tag, i))
        nxt = os.path.join(td, "%s_cur%d.jpg" % (tag, i + 1))
        Image.fromarray(np.clip(inp[y0:y1, x0:x1] + 0.5, 0, 255).astype(np.uint8)).save(
            drop, "JPEG", qtables=qt, subsampling=sampling)
        r = subprocess.run([JPEGTRAN, "-copy", "all", "-drop", "+%d+%d" % (x0, y0), drop, "-outfile", nxt, cur],
                           capture_output=True, text=True)
        if r.returncode != 0:
            raise RuntimeError("jpegtran -drop 失败：%s" % r.stderr.strip()[:200])
        cur = nxt
    return cur


def write_jpeg_mcu(src_path, src_img, new_img, rects, out_path):
    """逐矩形用原图量化表 + 同样抽样编码，jpegtran -drop 链式嵌回；块外 DCT 系数与原图逐字节一致。
    块里没改的像素（背景、香料、毛笔）送进编码器的不是常规解码值，而是 djpeg -nosmooth 的解码值：
    它的色度是原图色度样本按 2x2 复制的，编码器按 2x2 求平均正好取回原样本，重编码几乎无损
    （实测笔筒一块 MAD 0.67→0.12、有变动的像素 57%→14%）。改过的像素照常用新 RGB。"""
    qt = src_img.quantization
    sampling = JpegImagePlugin.get_sampling(src_img)
    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    src_arr = np.asarray(src_img.convert("RGB"))
    changed = np.any(new_img != src_arr, axis=-1)
    enc = np.where(changed[..., None], new_img, decode_nosmooth(src_path))
    with tempfile.TemporaryDirectory() as td:
        cur = _drop_all(src_path, enc.astype(np.float32), rects, qt, sampling, td, "d")
        shutil.copyfile(cur, out_path)
    return "jpegtran -drop ×%d 块（MCU %s；未改像素按 -nosmooth 解码值送编）" % (
        len(rects), "x".join(map(str, mcu_size(src_img))))


def decode_nosmooth(path):
    if not DJPEG:
        raise SystemExit("找不到 djpeg：装 libjpeg-turbo（放进 PATH），或设环境变量 NK1_DJPEG 指向它")
    with tempfile.TemporaryDirectory() as td:
        p = os.path.join(td, "a.ppm")
        subprocess.run([DJPEG, "-nosmooth", "-ppm", "-outfile", p, path], check=True)
        return np.asarray(Image.open(p).convert("RGB"))


# ---------- 自检 ----------
def erode(m, n):
    out = m.copy()
    for _ in range(n):
        out = out & np.roll(out, 1, 0) & np.roll(out, -1, 0) & np.roll(out, 1, 1) & np.roll(out, -1, 1)
    return out


def self_check(before, after, objs, touched, blkmask, src_path, out_path):
    rep = {"objs": []}
    diff = np.abs(after.astype(np.int16) - before.astype(np.int16)).max(-1)
    Aall = np.zeros(before.shape[:2], np.float32)
    for ob in objs:
        Aall = np.maximum(Aall, ob.full(np.maximum(ob.A, ob.capcov).astype(np.float32)))
    outside = Aall == 0
    rep["outside_mad"] = float(np.abs(after.astype(np.int16) - before.astype(np.int16))[outside].mean())
    rep["outside_changed"] = int((diff[outside] > 0).sum())
    rep["outside_blocks_changed"] = int((diff[~blkmask] > 0).sum())
    fringe = dilate(blkmask, 1) & ~blkmask
    rep["fringe_changed"] = int((diff[fringe] > 0).sum())
    rep["beyond_fringe_changed"] = int((diff[~dilate(blkmask, 1)] > 0).sum())
    rep["inblock_outside_mad"] = float(np.abs(after.astype(np.int16) - before.astype(np.int16))[outside & blkmask].mean())
    a_ns = decode_nosmooth(src_path)
    b_ns = decode_nosmooth(out_path)
    rep["nosmooth_outside_blocks_changed"] = int((np.abs(a_ns.astype(np.int16) - b_ns.astype(np.int16)).max(-1)[~blkmask] > 0).sum())
    labb, laba = srgb_to_lab(before), srgb_to_lab(after)
    dE = np.sqrt(((laba - labb) ** 2).sum(-1))
    for ob in objs:
        if ob.spec["key"] not in touched:
            continue
        r = {"key": ob.spec["key"], "label": ob.spec["label"], "glaze": GLAZES[ob.spec["glaze"]]["name"]}
        wb, wa = ob.win(before).astype(np.float32), ob.win(after).astype(np.float32)
        core = ob.core
        Yb = luma(wb)
        Wg = local_pct(Yb, core, GROUND_R, GROUND_Q)
        d = 1 - Yb / np.maximum(Wg, 1)
        gpx = core & (d < 0.08) & (Yb < np.percentile(Yb[core], 97))
        white = wb[gpx].mean(0)
        r["cobalt"] = (cobalt_share(wb, core), cobalt_share(wa, core))
        r["abs"] = (blue_abs(wb, core), blue_abs(wa, core))
        r["wb"] = (blue_wb(wb, core, white), blue_wb(wa, core, white))
        gb, ga = wb[gpx].astype(np.float64).mean(0), wa[gpx].astype(np.float64).mean(0)
        r["ground"] = dict(n=int(gpx.sum()), lb=float(luma(gb)), la=float(luma(ga)), gr_b=gb[1] / gb[0], br_b=gb[2] / gb[0],
                           gr_a=ga[1] / ga[0], br_a=ga[2] / ga[0], rgb_b=gb, rgb_a=ga)
        Ya = luma(wa)
        r["luma"] = (float(Yb[core].mean()), float(Ya[core].mean()))
        top = core & (Yb >= np.percentile(Yb[core], 99.5))
        r["spec"] = (float(Yb[top].mean()), float(Ya[top].mean()))
        Cm = ob.C > 0
        ro = dilate(Cm, 3) & ~Cm
        ri = Cm & ~erode(ob.C >= 1, 2) & (ob.C >= 1)
        dEw = ob.win(dE)
        r["dE_out"] = float(dEw[ro].mean())
        r["dE_in"] = float(dEw[ri & core].mean()) if (ri & core).any() else float("nan")
        cm = erode(ob.cont > 0.99, 2)
        dd = np.abs(wa - wb).max(-1)
        r["contents"] = (int(cm.sum()), float(dd[cm].mean()) if cm.any() else 0.0, int((dd[cm] > 3).sum()) if cm.any() else 0)
        xs, ys = np.nonzero(core.T)
        bx = (int(xs.min() + ob.x0 + 4), int(ys.min() + ob.y0 + 4), int(xs.max() + ob.x0 - 4), int(ys.max() + ob.y0 - 4))
        r["tex"] = (texture(before, bx), texture(after, bx), bx)
        r["hf"] = (hf_std(wb, core), hf_std(wa, core))
        x0_, y0_, x1_, y1_ = TEX_BOX[ob.spec["key"]]
        Yfb, Yfa = luma(before.astype(np.float32)), luma(after.astype(np.float32))
        r["hfbox"] = (float((Yfb - blur(Yfb, 3.0))[y0_:y1_, x0_:x1_].std()), float((Yfa - blur(Yfa, 3.0))[y0_:y1_, x0_:x1_].std()))
        r["gr"] = (green_ratio(wb, ob), green_ratio(wa, ob))
        if ob.spec.get("mode") == "carve":
            # 纹饰对比：原图比地子暗 10% 以上的像素，前后各自相对本图地子场（同一批地子像素）的平均暗度
            Yb_, _, _, gw = carve_ground(wb, ob)
            Ya_ = luma(wa)
            Ggb = ms_nblur(Yb_, gw, (2.0, 4.0, 8.0, 16.0))
            Gga = ms_nblur(Ya_, gw, (2.0, 4.0, 8.0, 16.0))
            relb = 1 - Yb_ / np.maximum(Ggb, 1.0)
            pm = core & (relb > 0.10) & (ob.keep < 0.5)
            rela = 1 - Ya_ / np.maximum(Gga, 1.0)
            r["carve"] = (int(pm.sum()), float(relb[pm].mean()), float(rela[pm].mean()))
        rep["objs"].append(r)
    return rep


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--src", default=DEFAULT_SRC)
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--in-place", action="store_true", help="允许输出覆盖输入文件")
    ap.add_argument("--force", action="store_true", help="跳过幂等检查（调试用）")
    ap.add_argument("--only", default="", help="只处理这些器物（逗号分隔 key）")
    ap.add_argument("--glaze", default="", help="调试用：临时换釉，如 brushpot=qingbai,spicejar=longquan_fen")
    args = ap.parse_args(argv)
    for kv in filter(None, args.glaze.split(",")):
        k, v = kv.split("=")
        for s in OBJECTS:
            if s["key"] == k:
                s["glaze"] = v
    if os.path.abspath(args.src) == os.path.abspath(args.out) and not args.in_place:
        print("输出与输入同一路径，需加 --in-place 才写；未写任何文件。")
        return 2
    im = Image.open(args.src)
    if im.size != SIZE or im.format != "JPEG":
        print("输入不是 1672x941 JPEG（%s %s），不是这张底图，跳过。" % (im.format, im.size))
        return 2
    src = np.asarray(im.convert("RGB"))
    objs = [Obj(s) for s in OBJECTS]
    only = set(filter(None, args.only.split(",")))
    print("输入 %s（%d 字节）" % (args.src, os.path.getsize(args.src)))
    todo = []
    for ob in objs:
        key = ob.spec["key"]
        if only and key not in only:
            continue
        need, why = judge(ob, ob.win(src).astype(np.float32))
        tag = "处理" if (need or args.force) else "跳过（判定已处理或已非青花）"
        print("  %-8s %-6s %s → %s" % (key, ob.spec["label"], why, tag))
        if need or args.force:
            todo.append(ob)
    if not todo:
        print("  没有需要处理的器物：判定已处理过，跳过，未写文件。")
        return 0
    new = src.copy()
    touched = set()
    for ob in todo:
        win_new, touch, _ = render(src, ob)
        cur = ob.win(new)
        cur[touch] = win_new[touch]
        touched.add(ob.spec["key"])
    mask = np.any(new != src, axis=-1)
    mw, mh = mcu_size(im)
    rects, blk = changed_mcu_rects(mask, mw, mh)
    blkmask = np.repeat(np.repeat(blk, mh, 0), mw, 1)[:SIZE[1], :SIZE[0]]
    how = write_jpeg_mcu(args.src, im, new, rects, args.out)
    after = np.asarray(Image.open(args.out).convert("RGB"))
    rep = self_check(src, after, objs, touched, blkmask, args.src, args.out)
    print("写出 %s（%d 字节，%s，改动 MCU %d 个）" % (args.out, os.path.getsize(args.out), how, int(blk.sum())))
    print("  器外（alpha=0）平均绝对差 %.4f、变动像素 %d；块内器外平均绝对差 %.3f"
          % (rep["outside_mad"], rep["outside_changed"], rep["inblock_outside_mad"]))
    print("  改动块外变动像素：DCT 口径（djpeg -nosmooth）%d；默认解码 %d（全在块外紧贴 1px：%d，1px 以外 %d）"
          % (rep["nosmooth_outside_blocks_changed"], rep["outside_blocks_changed"], rep["fringe_changed"], rep["beyond_fringe_changed"]))
    for r in rep["objs"]:
        g = r["ground"]
        print("  [%s %s → %s]" % (r["key"], r["label"], r["glaze"]))
        print("    偏蓝笔触 %.1f%% → %.1f%%；任务口径蓝像素 %.2f%% → %.2f%%；按原器白地白平衡后 %.1f%% → %.1f%%"
              % (100 * r["cobalt"][0], 100 * r["cobalt"][1], 100 * r["abs"][0], 100 * r["abs"][1], 100 * r["wb"][0], 100 * r["wb"][1]))
        print("    白地同批像素 n=%d：(%.0f,%.0f,%.0f) → (%.0f,%.0f,%.0f)，亮度 %.1f → %.1f（×%.3f）；G/R %.3f→%.3f、B/R %.3f→%.3f（折本色 %.3f/%.3f）"
              % (g["n"], *g["rgb_b"], *g["rgb_a"], g["lb"], g["la"], g["la"] / g["lb"], g["gr_b"], g["gr_a"], g["br_b"], g["br_a"],
                 g["gr_a"] / g["gr_b"], g["br_a"] / g["br_b"]))
        print("    器身均亮 %.1f → %.1f；最亮 0.5%% 像素（高光）%.1f → %.1f；边界 ΔE76 轮廓外 1–3px %.2f、内侧 1–2px %.2f"
              % (*r["luma"], *r["spec"], r["dE_out"], r["dE_in"]))
        tb, ta, bx = r["tex"]
        print("    肌理（框 %s，均亮/HF3/MF9）%.1f/%.1f%%/%.1f%% → %.1f/%.1f%%/%.1f%%；内容物（内缩 2px）%d px 平均差 %.3f、>3 的 %d px"
              % (bx, tb[0], 100 * tb[1], 100 * tb[2], ta[0], 100 * ta[1], 100 * ta[2], *r["contents"]))
        print("    器身肌理 std(Y−高斯σ3)（内缩 3px）%.1f → %.1f（×%.2f）；器身内框 %s %.1f → %.1f；器身 G/R %.3f → %.3f"
              % (r["hf"][0], r["hf"][1], r["hf"][1] / max(r["hf"][0], 1e-6), TEX_BOX[r["key"]], *r["hfbox"], *r["gr"]))
        if "carve" in r:
            n_, cb_, ca_ = r["carve"]
            print("    纹饰对比（原图比地子暗 10%% 以上的 %d px，平均暗度）%.3f → %.3f（×%.2f）" % (n_, cb_, ca_, ca_ / max(cb_, 1e-6)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
