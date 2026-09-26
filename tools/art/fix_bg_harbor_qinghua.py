#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""背景画修瑕：泉州港底图码头上的四只青花罐改成泉州磁灶窑青黄釉储运罐（史实纠偏）。

来由：bg_quanzhou_harbor.jpg（1672×941，泉州港页底图，也进过场）码头右下货堆里有四只白地钴蓝缠枝的青花罐
（整组 ≈(1110,798)-(1370,934)）：J1 左大口罐、J2 中圆罐、J3 系耳罐、J4 带盖大罐（最大，≈(1283,810)-(1368,932)）。
成熟青花是元至正以后的器物，1255—1290 一律穿帮。码头上成批堆放的储运罐，宋末元初泉州最该是本地磁灶窑的粗瓷
（孟原召：泉州湾宋船出磁灶窑粗瓷；磁灶窑南宋中晚期至元产酱黑釉、绿釉、青黄釉的大罐、小罐，专供外销储运）。
四只统一改成磁灶「青黄釉」（黄中泛青的橄榄色，一批货同一釉，浓淡差只来自各罐受光），理由：
前排两只红褐编筐罐已是暖褐色，四只再改酱黑釉会糊成一片；青黄釉保住原来这组浅色器在暗角里的冷暖对比与层次，
又和龙泉/市舶司衙内那种体面陈设拉开档次。改釉不改形：口沿、颈、系耳、盖与盖钮全按原轮廓与原明暗走；
盖与罐同釉改色（J4 盖面原有一块赭色暖斑 ≈(1316–1342, 830–837) 与一个暗点，暗点原样留，暖斑按原亮度关系改为暖橄榄色，
保住盖面层次）。
全图另扫过：任务口径命中的聚簇是人物蓝衣、摊棚蓝布篷、蓝漆木箱；码头大水缸（1285–1375,707–790）是灰褐斑驳、
盛水的缸（场景口径 0.5%），左下灰青木箱是箱子——都不是青花，不动。

做法（每只罐单独处理，J4 在前、J3 被它挡住的部分归 J4）：
1. 外轮廓：逐行亮度 / B-R 剖面找边、6–8 倍放大叠线目视核对得多边形（被前景罐与提绳挡住处沿遮挡物边走，
   B2 提绳环挖洞）；4× 超采样求覆盖率，融合 alpha 内收 0.5px、羽化 0.6px，不越出轮廓。
2. 去纹样：本图暖光把钴蓝推成青绿灰（J4 暗部均色 (46,53,44)），色度又是 4:2:0 半分辨率、块状，靠色度找纹样不可靠，
   改用亮度形态学：软闭运算（7×7 窗 92 分位膨胀 → 12 分位腐蚀，再 σ1 轻糊）抹掉比邻域窄的暗笔触，比闭运算暗
   5%–22% 以上的像素渐进提回去（留 15% 当釉层厚薄）。只在罐腹做（BODY_LINE 以下），口沿、唇下阴影、盖沿下的缝、
   罐口 / 耳孔阴影（PROTECT 椭圆）是结构，不动。纹样密处（J4 满身缠枝）白地夹在蓝花间的细亮缝会连成一张「底片」亮网，
   按纹样局部密度把细节向 σ2 平滑收 85%（J1 纹样极淡，只收 30%、提亮上限 0.6，保住原画笔意）。
3. 明暗：罐内大尺度受光按 γ1.35 拉开（原来一半的体积感靠白地/蓝花对比撑着）；整体乘亮度系数 gain（J1 0.64、
   J2/J3 0.66、J4 0.70），亮度前 20% 段渐回 1.0（亮釉的镜面反光不随釉色压暗）；原画亮度 90–97 分位以上的高光
   （口沿、盖沿、左肩受光）原样留住 ×0.95；下腹积釉压暗一档。逐像素封顶：不亮过「去掉纹样后的白瓷」本身。
4. 釉面肌理与光泽：
   J1–J3：沿纬线切线（回转体俯视的扁椭圆弧）撒短笔触（σ长 1.6–4、σ宽 0.6–1.2，另叠一层细笔触），方向随机偏
   0.5 rad，受光处更显；外加 σ6 的低频窑变（亮度 ±3.5%、色度 ±10%）。
   J4（参数见 PAINT / render_j4。r1 的纬线长笔触成了横向拖痕、罐腹发虚；r2 的纬线短笔 + 受光加权在受光左上成了
   浅灰绿碎斑夹暗网脉、读作地衣 / 蛇纹石，次反光是 1–2px 细亮线、像裂纹——均已弃用。r3 做法；其中 a)–c) 的肌理
   现在只留在受光左上（右肩留两成），右肩与下半腹换成 f)）：
   a) 短笔触 650 笔：3× 超采样、钝头（沿笔方向 3 次超椭圆）软边，可见长 ≈7–11px、宽 ≈1.7–2.5px，不透明叠放；
      方向 = 回转体经线（x = ctr(y) + u·hw(y)，随器形竖弯、下腹向底收拢）+ σ8 平滑随机偏角 × 0.3 rad（成组顺经线、
      只小幅摆动），靠边完全顺轮廓；笔触明暗 = 沿竖向拉长的平滑值场（σx1.5 / σy6：同一道釉流的笔明暗相近）+ 独立扰动，
      限幅 −1.7…+1.3（暗笔略多，不出孤立浅色碎点）。
   b) 笔脊浮雕 0.02（r2 0.10 让每笔一亮一暗两道细线，成毛发）。
   c) 原生高频 ×0.15：Yw 先 3×3 软开运算（混合 0.9）压掉白地细缝亮网，再取 mask 内 r=3 盒均值高通。
   以上按「中间调」加权：p = 罐内亮度 15–90 分位归一，权重 interp(p, [0, .25, 1], [.50, 1, .45])；受光左上
   （x<1325、848<y<885，软边 5px）再 ×0.42；再乘竖向渐变 1.16→0.80（y850→925：下腹经线收拢、笔触挤，同权重下
   比右上腹花一截）。减掉 σ3 以上低频（大尺度明暗不动），肌理亮处色度略退、暗处略深（×0.6）。
   d) 光泽：左上腹软光（σ5×8、+25%）；从左肩原高光起笔、顺受光侧往下的镜面高光带（横截面 6 次平顶硬边），
      两粒镜面点；受光区 5 笔脆亮镜面短笔（仿 J3 左肩：可见长 3–5px、宽 ≈1.7px、硬边，挑原白瓷 5px 邻域亮端比底色
      高 50–75 灰阶处）；高光带下方 y873–904 的次反光加宽到 3–4px（σ1.5 高斯软边）、断成 3 截。色取场景光色，
      亮度 ≤ min(165, 原白瓷 5px 邻域亮端)——这片原白瓷 y850 以下本在阴影里（逐像素 L* 40–53），只有左肩 y842–849
      到 L* 62–79，所以带子从那里起笔、往下渐弱；右轮廓内一道弱的暖色环境反光（原图右轮廓本有亮边），亮度 ×1.8、
      逐像素不越原白瓷。
   e) BODY_LINE 以上（盖、盖钮、罐肩、盖面赭斑）评审已过，逐像素沿用 r2：同一 render_j4 用 PAINT_R2 再渲一遍，
      按罐腹权重（BODY_LINE 下 0.5–2px 渐入）合成——肌理高通会把罐腹笔触漏进线上几 px，只换罐腹参数做不到盖面不变。
   f) r3 第 2 次（参数见 BELLY / _belly_glaze）：上面 a) 的竖笔在下半腹成了密集的波状竖细缕、往罐底收成扇形
      （毛发 / 草丛 / 焰纹，下腹高频横向自相关 lag3–4 到 −0.40、竖向到 lag5 仍 0.25 ≈ 7px 周期竖条纹）。受光左上
      （x<1328 且 y<880，含高光带、5 笔短笔、次反光第一截）texmul 逐像素不动（光泽层参数全不动，次反光三截照画），
      其余罐腹（右肩 + 下半腹）换成：
      下腹用 J1–J3 同一套纬线短笔（brush_texture + 细笔触层，偏角 σ0.45）当细纹；右肩用顺经线的短软笔（σ长 0.9–1.4、
      σ宽 0.6–0.9），留两成原笔意与受光左上接上；两段在 y876–902 渐变；细纹 ±2.6σ 外限幅、暗侧 tanh 软限，免得几笔
      同号叠成深洞；6 道近乎平行的直竖釉流（方向 = 经线斜率 × 0.4，间距 / 宽窄随机，不往罐底收拢），多数尾端一颗略深
      的积釉珠、珠上一点受光，积釉处软隆起（左上坡略亮、右下坡略暗）；σ8 低频积釉浓淡让下腹加深（至多 −14%）微绿；
      右肩 / 左下 / 右下各撒 1–3 粒镜面小光点（画在光泽层，同受光区短笔的画法与亮度上限，强度 0.55–0.9）。
      中间调加权放平（0.8 / 1.0 / 0.85），右肩竖向略提（×1.2 → 1.0）。
5. 着色：场景白点取各罐原白地同批像素（罐内亮度 75–97 分位、非场景蓝）的均色比——J4 在棚影里 (1, .993, .789)、
   J3 (1, .960, .771)、J2 (1, .920, .714)、J1 挨着暖筐篓 (1, .889, .606)；乘青黄釉本色 GLAZE (1, 1.01, .68)。
   积釉处色度加深 35%，高光处色度向光色收 85%。落盘后罐腹 L*25–50 中位色相 ≈95–107°、C* ≈21–24（黄绿橄榄）。
6. 写出：本图 4:2:0（MCU 16×16）。改动像素所在 MCU 按行并成矩形，逐块用原图同一套量化表、同一抽样编码，
   jpegtran -drop 逐块无损嵌回（块外 DCT 系数原样照搬）；嵌完用 djpeg -nosmooth（逐块独立解码）核对块外逐像素
   一致，不一致就不写。fix_bg_customs_jar.write_jpeg 只走 4:4:4 单矩形，4:2:0 进去会退回整图重编码，所以这里另写；
   其余小工具（模糊、mask 内归一化、局部分位、Lab、蓝像素、肌理口径）从 fix_bg_customs_jar import。
   PIL 默认的 fancy upsampling 会把块边色度插值进紧贴块外的一圈 1px（最大差 ≈4 灰阶），另行打印。

幂等：先量 J2–J4 罐身（覆盖率 >0.99）里「场景口径」蓝像素（色相 150–260°、S>0.12、V≥0.10：暖光下的钴蓝落在青绿段，
任务口径 HSV 190–250° S>0.18 在本图原图就只有 0.4%，判不了）；原图 10.6%、处理后 0.0%，低于 3% 视为已处理，
打印原因后跳过、不写文件、rc=0，所以日后可以直接对仓库文件运行。渲染用固定随机种子，同一输入两次运行输出逐字节相同。
输出与输入同路径时必须加 --in-place 才写。

用法：
  python3 tools/art/fix_bg_harbor_qinghua.py --in-place           # 就地处理 assets/bg_quanzhou_harbor.jpg（已处理则跳过）
  python3 tools/art/fix_bg_harbor_qinghua.py --out /tmp/cand.jpg  # 只出候选，不动仓库文件
  python3 tools/art/fix_bg_harbor_qinghua.py --src A.jpg --out B.jpg
自检数字（两种口径蓝像素前后、mask 外平均绝对差、改动块外变动像素（-nosmooth / PIL 两种解码）、边界 ΔE、各罐均亮与
原白地同批像素亮度比、L* 峰值与高光像素数、釉色色相/彩度、肌理 HF3/MF9 与同画参照；J4 专项：罐腹高频 std/均值
（亮度减 7×7 盒均值，评审口径；整框与四象限）、罐腹高频偏度、结构张量方向一致性（单一设定 + 评审六种设定最小值）、
下腹高频横向自相关最低值与竖向 lag3、横向长拖痕超额、镜面高光带 L* 与越限像素（逐像素 / 5px 邻域两种上限，
内存 / 落盘分报）、盖面暖斑 Lab、右肩 / 下腹镜面小光点位置）每次运行都会打印。
"""
import argparse
import os
import shutil
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image, ImageDraw, JpegImagePlugin

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from fix_bg_customs_jar import (blur, blur_xy, box_mean, hsv_blue, local_pct, luma, nblur, smoothstep,  # noqa: E402
                                srgb_to_lab, texture)

ROOT = os.path.dirname(os.path.dirname(HERE))
DEFAULT_SRC = os.path.join(ROOT, "assets", "bg_quanzhou_harbor.jpg")
SIZE = (1672, 941)
WORK = (1088, 784, 1392, 941)      # 处理窗（x 16 对齐；下沿到图底）

# ---------- 几何：四只罐的可见外轮廓（原图像素连续坐标，像素 (x,y) 占 [x,x+1)×[y,y+1)） ----------
# 逐行亮度 / B-R 剖面找边 + 6–8 倍放大叠线目视核对；被前景挡住的部分直接沿遮挡物边走。列表顺序即前后：后画的在前。
J1 = [  # 左：大口罐，B1（红褐编筐罐）挡住右下
    (1121.0, 804.0), (1126, 801.0), (1135, 800.2), (1146, 800.2), (1156, 801.2), (1162, 803.5), (1164.0, 808),
    (1165.5, 815), (1168.0, 821), (1169.8, 826), (1170.6, 835), (1171.6, 845), (1172.2, 853), (1171.5, 858.5),
    (1162, 860.0), (1155, 864.5), (1149, 870), (1146, 877), (1144, 885), (1143, 891.0),
    (1130, 892.0), (1124, 890), (1121.5, 885), (1119.5, 876), (1116.5, 866), (1113.5, 857), (1111.2, 846),
    (1111.5, 836), (1113.5, 830), (1116.0, 826), (1118.5, 818), (1119.5, 810),
]
J2 = [  # 中：圆罐，B2（棕罐盖与提绳）挡住下半
    (1207.5, 818), (1212, 815.0), (1220, 813.8), (1230, 813.8), (1238, 815.0), (1243.5, 818.5), (1244, 824),
    (1246.5, 828), (1250.5, 833), (1252.8, 841), (1253.2, 850), (1252, 855),
    (1246, 853), (1240, 852.5), (1230, 853), (1222, 855.5), (1217, 860), (1214, 865), (1206, 866),
    (1201.5, 862), (1198.5, 856), (1197.2, 848), (1197.5, 840), (1199.5, 833), (1203.5, 828), (1206.5, 824),
]
J2_ROPE = [  # B2 提绳环压在 J2 罐身上：挖掉
    (1232.2, 841.0), (1237, 839.9), (1242.5, 839.9), (1246.5, 840.9), (1248.2, 843.2), (1247.0, 845.2),
    (1243.0, 846.6), (1239, 848.0), (1235, 849.0), (1235.3, 853.8), (1227, 853.8), (1227.3, 850), (1229, 848.2),
    (1231.8, 847.8), (1232.3, 845), (1231.2, 843.3),
]
J3 = [  # 右中：系耳罐，右侧被 J4 挡、下半被 B2 盖挡
    (1264.0, 816), (1268, 812.2), (1276, 811.0), (1284, 811.5), (1289, 812.0), (1296, 812.5), (1300.5, 815),
    (1301.0, 820), (1298, 825), (1293.5, 827.5), (1290.0, 834), (1287.5, 840), (1286.0, 848), (1285.0, 856),
    (1278, 858), (1268, 858.5), (1262, 860), (1258.5, 858), (1255.5, 851), (1254.5, 843), (1255.5, 836),
    (1258.5, 829), (1262.0, 825), (1264.0, 821),
]
J4 = [  # 右：带盖大罐（最前）
    (1314.0, 822), (1314.0, 814.5), (1317.5, 811.2), (1326, 810.2), (1334, 810.8), (1337.5, 814), (1337.8, 822),
    (1346, 823.2), (1352, 825.5), (1355.5, 829), (1358.5, 835), (1360.8, 843), (1362.8, 853), (1365.2, 862),
    (1367.0, 871), (1366.6, 880), (1364.0, 890), (1362.8, 900), (1359.5, 910), (1358.0, 918), (1352, 925),
    (1344, 929.5), (1330, 931.5), (1316, 930.5), (1304, 927), (1298.5, 921), (1294.5, 915), (1292.5, 910),
    (1287.0, 902), (1285.8, 890), (1284.2, 880), (1283.2, 868), (1283.2, 858), (1284.2, 850), (1287.0, 840),
    (1291.5, 833), (1296.5, 827), (1303, 823.8),
]
# 纹样提亮时不动的结构暗部：罐口 / 耳孔里的阴影（椭圆 cx, cy, rx, ry）
PROTECT = {
    "J1": [(1142.5, 809.0, 17.0, 5.5)],
    "J2": [(1225.0, 818.5, 10.5, 3.6)],
    "J3": [(1276.5, 815.3, 8.5, 2.8), (1294.3, 815.8, 3.8, 2.4)],
    "J4": [(1325.5, 814.3, 7.8, 2.6)],
}

# 纹样提亮只在罐腹（这条线以下）做：口沿、颈、盖面的暗线是结构（唇下阴影、盖沿下的缝），不能当纹样抹平
BODY_LINE = {
    "J1": [(1108, 820.0), (1125, 820.0), (1145, 821.0), (1165, 820.0), (1176, 820.0)],
    "J2": [(1195, 825.8), (1210, 825.8), (1225, 826.3), (1245, 825.8), (1256, 825.8)],
    "J3": [(1252, 829.0), (1265, 829.0), (1276, 830.5), (1292, 830.0)],
    "J4": [(1281, 838.0), (1296, 842.0), (1310, 846.5), (1325, 848.5), (1340, 848.0), (1352, 845.0), (1364, 840.0)],
}

# ---------- 釉色：各罐场景白点 × 釉本色 × 亮度系数 ----------
# white：该罐原白地同批像素（罐身内亮度 75–97 分位、非场景口径蓝）的均色比，即「白瓷在此处这盏光下」的样子——
#        J4 在棚影里偏冷中性，J1/J2 挨着暖色筐篓与地面反光偏暖；
# albedo：釉本色 RGB 比（相对场景白点）；gain：亮度系数（青黄釉比白瓷暗）；pool：积釉带 y0–y1（下腹色深）；
# lift：纹样提亮上限；flat：纹样密处细节收平比例；tex：釉面笔触肌理幅度。列表顺序即前后：后面的罐在前。
GLAZE = (1.00, 1.01, 0.68)          # 磁灶青黄釉本色（同一批货同一釉；各罐的浓淡差来自各自受光的场景白点与亮度系数）
JARS = [
    dict(name="J1", poly=J1, holes=[], white=(1.0, 0.889, 0.606), albedo=GLAZE, gain=0.64, pool=(835.0, 892.0),
         lift=0.6, flat=0.3, tex=0.10),
    dict(name="J2", poly=J2, holes=[J2_ROPE], white=(1.0, 0.920, 0.714), albedo=GLAZE, gain=0.66, pool=(835.0, 866.0),
         lift=1.0, flat=0.85, tex=0.12),
    dict(name="J3", poly=J3, holes=[], white=(1.0, 0.960, 0.771), albedo=GLAZE, gain=0.66, pool=(832.0, 860.0),
         lift=1.0, flat=0.85, tex=0.12),
    dict(name="J4", poly=J4, holes=[], white=(1.0, 0.993, 0.789), albedo=GLAZE, gain=0.70, pool=(870.0, 931.0),
         lift=1.0),         # J4 的收平、肌理与光泽参数见 PAINT（render_j4）
]

# ---------- 纹样去除 ----------
CLOSE_R = 3                 # 软闭运算半径（先 92 分位膨胀、再 12 分位腐蚀）
CLOSE_Q = (92, 12)
LIFT_T = (0.05, 0.22)       # 比闭运算暗多少（相对）才算纹样笔触
RESID_PAT = 0.15            # 纹样明暗留多少当釉层厚薄起伏
HL_Q = (80.0, 99.5)         # 罐内亮度分位：从 HL_Q[0] 到 HL_Q[1] 亮度系数由 gain 渐变到 HL_GAIN（亮釉的高光不随釉色压暗）
HL_GAIN = 1.0
HL_DESAT = 0.85             # 高光处色度向光色收的比例
SPEC_Q = (90.0, 97.0)       # 原画高光：罐内原亮度分位区间渐入
SPEC_GAIN = 0.95
SPEC_KEEP_Q = (96.0, 99.5)  # 这一段以上的镜面点保留原像素色（光源色）
CLOSE_SOFT = 1.0            # 闭运算结果再 mask 内轻糊，免得方窗分位留下多边形小刻面
DENS_T = (0.08, 0.35)       # 纹样局部密度（g 的 σ2.5 平均）渐入区间
FORM_SIGMA = 6.0
FORM_GAMMA = 1.35
# 釉面肌理：沿纬线（罐面水平弧，俯视 ELEV）的短笔触，幅度 ±1 归一后乘各罐的 tex
TEX_DENSITY = 0.12          # 每像素笔触数
TEX_LEN = (1.6, 4.0)        # 笔触半长 σ（px）
TEX_WID = (0.6, 1.2)        # 笔触半宽 σ（px）
TEX_ANG = 0.50              # 笔触方向对纬线切线的随机偏角 σ（弧度）
TEX_FINE = (0.7, 0.25, (0.8, 1.8), (0.5, 0.8))   # 细笔触层：(相对权重, 密度, 半长, 半宽)
ELEV = 0.22                 # 纬线椭圆扁率（俯视角的正弦）
VAR_AMP = 0.035             # 窑变：低频亮度起伏
VAR_CHROMA = 0.10           # 窑变：低频色度浓淡
# 每只罐的中心线 x 与半宽（算纬线斜率用）
AXIS = {"J1": (1142.0, 30.0), "J2": (1225.0, 28.0), "J3": (1273.0, 22.0), "J4": (1325.0, 42.0)}

# ---------- J4 釉面（r2 重做肌理与光泽，r3 再改罐腹肌理与光泽；J1–J3 仍走上面的通用做法） ----------
# r1 评审：J4 罐腹 3–4 倍下发虚——σ2 收平留下的软云斑 + 纬线长笔触（σ长 4 ≈ 十几 px）成了贯穿罐腹的横向拖痕。
# r2 评审：拖痕与发虚已解决，但 4 倍下左上半腹成了浅灰绿碎斑夹暗橄榄网脉（地衣 / 苔斑 / 蛇纹石），与光亮的 J1–J3
# 不像同一种釉；结构张量方向一致性 0.341 全画最低，四象限高频左上最花（受光处最该光滑），偏度 0.27（光釉应强正偏），
# 整罐半哑光，y872–904 的次反光是 1–2px 细亮线、像裂纹。
# r3（下面 PAINT）：肌理改中间调加权、受光左上再压一档；短笔触加长到可见 7–11px、钝头软边、方向收拢顺经线成组竖弯，
# 明暗值场沿竖向拉长（σx1.5 / σy6，成组顺经线的釉流浓淡），明暗对称；受光区加 5 笔脆亮镜面短笔；
# 次反光加宽到 3–4px、高斯软边、断成 3 截；高光带横截面改平顶硬边。
# 试过不用的（数与图见工作区笔记）：r2 的纬线短笔 + 受光加权（地衣）；笔触密而细且对比高 → 毛发 / 草丛；
# 值场各向同性且粗（σ5）→ 迷彩 / 大理石；笔触各取独立明暗、尖头 → 叶片 / 豹斑；去掉笔脊浮雕只靠淡笔 → 高频只剩 0.06–0.08（r1 的发虚）。
PAINT = dict(
    seed=1277,
    flat=0.85,                  # 纹样密处细节收平比例（同 r1）
    hp_r=3, hp_amp=0.15, hp_clip=0.35,   # 原生高频：Yw（软闭运算提亮后、未收平）的 mask 内 r=3 盒均值高通，系数（r2 0.5），tanh 限幅
    hp_open=(15.0, 85.0, 0.9),  # 取高通前先做 3×3 软开运算（15 分位腐蚀 → 85 分位膨胀）压掉纹样白地细缝连成的 1px 亮网，混合比例（r2 0.7）
    # 肌理幅度权重：p = 罐内亮度 15–90 分位（σ3 平滑）归一；权重 = interp(p, mid_p, mid_w)——中间调最显，
    # 暗部与亮部都收（r2 是 0.25 + 0.75p 的受光加权，肌理全堆在最该光滑的受光左上）；
    # 受光左上（ul：x<ul[0]、ul[1]<y<ul[2]，软边 ul[3]px）再乘 1−ul[4]；再乘一道竖向渐变 tex_vy（y0, y1, 上端, 下端）——
    # 下腹经线收拢、笔触挤在一起，同样权重下比右上腹花一截，靠它把四象限拉平（下半仍不低于上半）
    mid_p=(0.0, 0.25, 1.0), mid_w=(0.50, 1.0, 0.45),
    ul=(1325.0, 848.0, 885.0, 5.0, 0.58),
    tex_vy=(850.0, 925.0, 1.16, 0.80),
    st_n=650, st_amp=0.31,      # 短笔触：数量、幅度
    st_len=(4.5, 7.0), st_wid=(1.2, 1.8),   # 半长 / 半宽（px；可见长 ≈7–11px、宽 ≈1.7–2.5px）
    st_op=(0.6, 0.95), st_jit=0.08, st_soft=0.4,    # 不透明度（后落的笔盖住先前的）、方向随机偏角 σ（弧度）、收边 smoothstep 起点
    st_kap=0.03, st_pow=3.0,    # 笔触微弯 σ；沿笔方向的超椭圆指数（2 = 椭圆尖头，3 = 钝头）
    st_edge=(0.55, 0.85),       # |u| 在这段里由「中部」过渡到「顺轮廓」（经线方向，靠边竖弯）
    ang_sigma=8.0, ang_spread=0.3,         # 中部方向 = 经线 + 平滑随机偏角场（σ8px、幅 0.3 rad；r2 σ5 / 1 rad）：成组顺经线、只小幅摆动
    val_sigma=(1.5, 6.0), val_mix=(0.7, 0.3),     # 笔触明暗 = 平滑值场（σx, σy：沿竖向拉长，同一道釉流的笔明暗相近）+ 独立扰动
    val_clip=(-1.7, 1.3),       # 笔触明暗限幅：亮端收得比暗端紧（暗笔略多，不出孤立的浅色碎点 / 亮焰尖）
    st_neg_lit=0.0,             # r2 受光处压暗笔衰减 45% → 亮笔成浅色碎点；r3 明暗对称
    relief=0.02, light=(0.6, 0.8),         # 笔脊浮雕：颜料厚度场按左上来光的明暗（r2 0.10 → 每笔一亮一暗两道细线，成毛发）
    var=0.02,                   # 窑变低频亮度起伏（r1 0.035）
    tex_lp=3.0,                 # 肌理只留中高频：σ3 以上的低频减掉（r2 σ5：留下的 5–15px 斑块读作迷彩 / 蛇纹）
    tex_desat=0.6,              # 肌理亮处色度略退、暗处略深（釉薄 / 积釉）；r2 1.0 让亮笔退成灰白，读作地衣
    glow=(1306.0, 853.0, 5.0, 8.0, 0.25),  # 左上腹软光：x y σx σy 相对提亮（逐像素不越原白瓷）
    band=[(1304.6, 845.5), (1306.2, 852.0), (1307.6, 859.0), (1308.6, 866.0), (1309.2, 872.0)],   # 镜面高光带中线
    band_w=(1.7, 1.0), band_taper=(1.0, 0.7), band_brk=0.45, band_amt=1.0, band_pow=6.0,   # 上→下半宽、强度、断续、混合、横截面指数（2 = 高斯，6 = 平顶硬边）
    spec_Y=165.0, cap_r=5,      # 高光亮度上限 165（≈L*66），且不越原白瓷 5px 邻域内的亮端
    # 次反光：(中线, σ, 强度, 分段 [(y 起, y 止), ...])；σ1.5 ≈ 可见宽 3–4px、两侧高斯软衰减，每段两端 3px 渐入渐出
    streaks=[([(1309.0, 868.0), (1309.6, 880.0), (1309.8, 892.0), (1309.4, 904.0)], 1.5, 0.55,
              [(873.0, 883.0), (887.0, 895.0), (898.0, 904.0)])],
    glints=[(1305.4, 850.5, 1.0, 0.9), (1307.9, 861.5, 0.8, 0.8)],    # 贴在高光带上的镜面点 (x, y, σ, 强度)
    # 受光区脆亮镜面短笔（仿 J3 左肩）：(x, y, 半长, 相对经线偏角 rad, 强度)；半宽 speck_w、3× 超采样硬边，可见长 3–5px。
    # 位置挑在原白瓷 5px 邻域亮端比底色高 50–75 灰阶处（高光带右侧两笔斜向、左轮廓内两笔顺经线、下方一笔）
    specks=[(1313.5, 852.5, 2.0, -0.5, 1.0), (1317.5, 858.5, 2.2, -0.4, 1.0), (1293.0, 863.0, 2.4, 0.0, 1.0),
            (1293.5, 879.5, 2.4, 0.0, 1.0), (1300.5, 882.0, 2.0, 0.15, 1.0)],
    speck_w=0.85,
    rim=(0.90, 848.0, 918.0, 1.3, 0.8), rim_gain=0.8, rim_col=(1.0, 0.93, 0.74),   # 右轮廓内环境反光（右侧暖色木箱）
    patch_box=(1311.0, 828.5, 1347.0, 839.5), patch_amt=0.9, patch_keep=0.5, patch_col=(1.0, 0.90, 0.46),  # 盖面赭斑
)
# r3 第 2 次（BELLY，只管受光左上以外的罐腹：右肩 + 下半腹；受光左上、高光带、5 笔镜面短笔、次反光、盖面、J1–J3 不动）。
# 第 1 次评审：下半腹是密集的波状竖细缕、往罐底收成扇形，3–8 倍下读作毛发 / 草丛 / 焰纹；下腹高频横向自相关 lag3–4 到 −0.40、
# lag7–8 回到 +0.20，竖向到 lag5 仍 0.25（≈7px 周期的规则竖条纹）。病根：细竖笔 + 竖向拉长的值场（σx1.5）经 σ3 高通成了带通，
# 再加随机偏角场的 S 形摆动、经线随器形收窄往罐底汇成一把。这里改为：
#   下腹用 J1–J3 同一套纬线短笔（brush_texture + 细笔触层）当细纹——同一批货同一种笔意；右肩用顺经线的短软笔（与受光左上
#   那片原笔意同向，方向一致性不掉），两段按 y 渐变；几道近乎平行的直竖釉流（间距 / 宽窄随机、不收拢）带积釉珠；
#   σ8 低频积釉浓淡让下腹加深微绿；右肩 / 下腹阴影里几粒镜面小光点（强度 < 1，同受光区短笔的画法与上限）。
# 试过不用的（数与图见工作区 r3/a2）：只把竖笔改稀改宽改直 → 3 倍下成斑驳 / 蛇纹石；各向同性细点 → 砂粒；正偏细点 → 霜花 / 雨点；
# 纬线短笔偏角收到 0.3 → 横向带状拖痕；右肩也用纬线 → 与受光左上竖向笔意交叉，右肩方向一致性掉到 0.34。
BELLY = dict(
    seed=1283,
    x_in=(1328.0, 1332.0), y_in=(880.0, 890.0),    # 区域 = x≥x_in 或 y≥y_in（两段 smoothstep 取大）；x<1328 且 y<880 恰为 0
    tilt=0.4,                   # 中部方向 = 经线斜率 × 0.4（近乎平行竖直，不往罐底收拢），|u|≥0.85 才完全顺轮廓
    mer_dens=0.35, mer_len=(0.9, 1.4), mer_wid=(0.6, 0.9), mer_jit=0.35,   # 右肩顺经线短软笔：每像素笔数、σ长、σ宽、偏角 σ
    lat_ang=0.45,               # 下腹纬线短笔（J1–J3 的 brush_texture 与细笔触层，笔长笔宽同 TEX_*）的偏角 σ（J1–J3 0.5）
    g_clip=2.6,                 # 细纹限幅：±2.6σ 以外斜率压到 1/4
    mix=(876.0, 902.0, 0.12, 0.15),                # 右肩 → 下腹：y 渐变区间、右肩幅度、下腹幅度
    hp_amp=0.08,                # 原生高频（同 PAINT 的 hp，软开运算后）
    w_p=(0.0, 0.25, 1.0), w_w=(0.8, 1.0, 0.85),   # 中间调加权（比 PAINT 平：暗处、亮处只收一两成）
    vy=(850.0, 925.0, 1.2, 1.0),                   # 竖向渐变（右肩略提：右肩底子最平）
    lp=4.0,                     # 细纹减掉 σ4 以上低频
    # 釉流：条数、起点 y 范围、长、半宽、同段最小横距、暗流占比、带珠占比、珠强度、珠（宽, 长）/ 流宽、珠收边、珠上受光点、
    # 首端渐入长、流身强度、隆起明暗、总幅度
    r_n=6, r_y=(852.0, 900.0), r_len=(16.0, 34.0), r_wid=(1.6, 2.6), r_gap=8, r_dark=0.85, r_drip=0.6, r_bead=0.9,
    r_bead_wl=(1.15, 1.6), r_bead_soft=0.45, r_hl=0.9, r_fade=8.0, r_body=0.8, r_rel=0.7, r_amp=0.24,
    t_floor=0.35,               # 暗侧软限（tanh，texmul 最低 ≈0.65）
    ur_old=0.2,                 # 右肩留两成原 PAINT 笔意
    pool_sigma=8.0, pool_y=(878.0, 926.0), pool_dark=0.14, pool_amp=0.04, pool_chroma=0.15,
    pool_albedo=(0.96, 1.02, 0.62), pool_green=0.5,  # 积釉：σ8 浓淡、y 渐入、加深、浓淡起伏、色度加浓、偏绿本色与混合比
    # 镜面小光点：分区 (x0, x1, y0, y1, 粒数)、y 范围、σ长、半宽、强度、最小间距、偏角 σ
    gl_zones=[(1334, 1358, 852, 884, 3), (1294, 1326, 889, 922, 2), (1326, 1358, 889, 922, 1)],
    gl_y=(855.0, 922.0), gl_len=(1.6, 2.4), gl_wid=0.6, gl_amp=(0.55, 0.9), gl_gap=10.0, gl_jit=0.12,
)
PAINT["belly"] = BELLY
# r2 参数（评审已过的盖面、罐肩等 BODY_LINE 以上部分逐像素沿用它的渲染）：同一 render_j4、同一随机序列，只是这组参数。
# r2 的肌理高通会把罐腹笔触漏进 BODY_LINE 以上几 px，所以不能只换罐腹参数就指望盖面不变——两套各渲一遍，按罐腹权重合成。
PAINT_R2 = dict(
    PAINT, hp_amp=0.5, hp_open=(15.0, 85.0, 0.7), mid_p=(0.0, 1.0), mid_w=(0.25, 1.0), ul=(1325.0, 848.0, 885.0, 5.0, 0.0),
    tex_vy=(850.0, 925.0, 1.0, 1.0), st_n=1500, st_amp=0.34, st_len=(1.8, 3.2), st_wid=(1.0, 1.6), st_jit=0.15, st_soft=0.55,
    st_kap=0.08, st_pow=2.0, ang_sigma=5.0, ang_spread=1.0, val_sigma=(3.0, 3.0), val_mix=(0.55, 0.40), val_clip=(-2.5, 2.5),
    st_neg_lit=0.45, relief=0.10, tex_lp=5.0, tex_desat=1.0, band_pow=2.0, streaks=[], specks=[], belly=None,
)

# ---------- 口径 ----------
BLUE_SCENE_HUE = (150.0, 260.0)   # 场景口径：暖光把钴蓝推成青绿，色相放宽到 150°
BLUE_SCENE_SAT = 0.12
BLUE_VMIN = 0.10
SKIP_BELOW = 0.03                 # J2–J4 场景口径蓝像素占比低于此值视为已处理


def hsv(rgb255):
    r = rgb255.astype(np.float32) / 255.0
    mx, mn = r.max(-1), r.min(-1)
    d = mx - mn
    s = np.where(mx > 0, d / np.maximum(mx, 1e-6), 0.0)
    R, G, B = r[..., 0], r[..., 1], r[..., 2]
    h = np.zeros_like(mx)
    dd = np.maximum(d, 1e-6)
    rr = (mx == R) & (d > 1e-6)
    gg = (mx == G) & (d > 1e-6) & ~rr
    bb = (d > 1e-6) & ~rr & ~gg
    h[rr] = (60 * ((G - B) / dd) % 360)[rr]
    h[gg] = (60 * ((B - R) / dd) + 120)[gg]
    h[bb] = (60 * ((R - G) / dd) + 240)[bb]
    return h, s, mx


def scene_blue(rgb255):
    h, s, v = hsv(rgb255)
    return (h >= BLUE_SCENE_HUE[0]) & (h <= BLUE_SCENE_HUE[1]) & (s > BLUE_SCENE_SAT) & (v >= BLUE_VMIN)


# ---------- 几何 ----------
def _raster(poly, box, ss):
    x0, y0, x1, y1 = box
    m = Image.new("L", ((x1 - x0) * ss, (y1 - y0) * ss), 0)
    ImageDraw.Draw(m).polygon([((x - x0) * ss, (y - y0) * ss) for x, y in poly], fill=255)
    return np.asarray(m) > 0


def _erode(a, k):
    for _ in range(k):
        p = np.pad(a, 1, constant_values=False)
        a = a & p[:-2, 1:-1] & p[2:, 1:-1] & p[1:-1, :-2] & p[1:-1, 2:]
    return a


class Geo:
    """处理窗内每只罐的覆盖率 C、融合 alpha A（内收 0.5px、羽化 0.6px，不越出轮廓）、罐号图。"""

    def __init__(self, box=WORK, ss=4):
        self.box = box
        self.x0, self.y0, self.x1, self.y1 = box
        self.h, self.w = self.y1 - self.y0, self.x1 - self.x0
        taken = np.zeros((self.h * ss, self.w * ss), bool)
        self.C, self.A = {}, {}
        for jar in reversed(JARS):          # 从前往后：前面的罐占掉的像素后面的不再要
            name = jar["name"]
            m = _raster(jar["poly"], box, ss)
            for hp in jar["holes"]:
                m &= ~_raster(hp, box, ss)
            m &= ~taken
            taken |= m
            c = m.reshape(self.h, ss, self.w, ss).mean((1, 3)).astype(np.float32)
            inner = _erode(m, ss // 2).reshape(self.h, ss, self.w, ss).mean((1, 3)).astype(np.float32)
            a = np.clip(blur(inner, 0.6), 0, 1) * (c > 0)
            a[a < 1.0 / 512] = 0.0
            self.C[name], self.A[name] = c, a
        yc = np.arange(self.h, dtype=np.float32) + 0.5 + self.y0
        xc = np.arange(self.w, dtype=np.float32) + 0.5 + self.x0
        self.Y, self.X = np.meshgrid(yc, xc, indexing="ij")
        self.A_all = sum(self.A.values())
        self.C_all = sum(self.C.values())

    def full(self, arr, fill=0):
        out = np.full((SIZE[1], SIZE[0]) + arr.shape[2:], fill, arr.dtype)
        out[self.y0:self.y1, self.x0:self.x1] = arr
        return out

    def protect(self, name):
        p = np.zeros((self.h, self.w), np.float32)
        for cx, cy, rx, ry in PROTECT.get(name, []):
            r = np.sqrt(((self.X - cx) / rx) ** 2 + ((self.Y - cy) / ry) ** 2)
            p = np.maximum(p, 1 - smoothstep(0.8, 1.15, r))
        return p

    def body(self, name):
        """罐腹权重：BODY_LINE 以下 0.5–2px 渐入。"""
        pts = BODY_LINE[name]
        yl = np.interp(self.X[0], [p[0] for p in pts], [p[1] for p in pts])
        return smoothstep(yl[None, :] + 0.5, yl[None, :] + 2.0, self.Y)


# ---------- 渲染 ----------
def brush_texture(geo, name, M, rng, density, length, width, ang=TEX_ANG):
    """mask 内撒短笔触：椭圆高斯，长轴沿该处纬线的切线（回转体俯视：y = y0 + ELEV·hw·sqrt(1-u²)），幅度 N(0,1)。
    ang 为方向随机偏角 σ（J1–J3 用缺省 TEX_ANG；J4 下腹用同一套笔、偏角略收）。返回归一到标准差 1 的起伏场。"""
    cx, hw = AXIS[name]
    ys, xs = np.nonzero(M)
    n = int(len(ys) * density)
    idx = rng.choice(len(ys), n)
    tex = np.zeros(M.shape, np.float32)
    R = int(np.ceil(3 * length[1]))
    oy, ox = np.mgrid[-R:R + 1, -R:R + 1].astype(np.float32)
    for i in range(n):
        y, x = ys[idx[i]], xs[idx[i]]
        jx, jy = rng.uniform(-0.5, 0.5, 2)
        u = np.clip((x + geo.x0 + 0.5 - cx) / hw, -0.95, 0.95)
        slope = -ELEV * u / np.sqrt(1 - u * u)
        th = np.arctan(slope) + rng.normal(0, ang)
        L = rng.uniform(*length)
        Wd = rng.uniform(*width)
        amp = rng.normal(0, 1)
        c, s = np.cos(th), np.sin(th)
        dx, dy = ox - jx, oy - jy
        along = dx * c + dy * s
        across = -dx * s + dy * c
        k = amp * np.exp(-0.5 * ((along / L) ** 2 + (across / Wd) ** 2))
        y0, y1 = max(0, y - R), min(M.shape[0], y + R + 1)
        x0, x1 = max(0, x - R), min(M.shape[1], x + R + 1)
        tex[y0:y1, x0:x1] += k[y0 - (y - R):y1 - (y - R), x0 - (x - R):x1 - (x - R)]
    tex = tex * M
    tex -= tex[M].mean()
    tex /= tex[M].std() + 1e-6
    return tex * M


def _slide(img, r, fn):
    from numpy.lib.stride_tricks import sliding_window_view
    return fn(sliding_window_view(np.pad(img, r), (2 * r + 1, 2 * r + 1)), (-1, -2))


def _soft_strokes(M, R_, rng, theta, n, length, width, jit):
    """R_ 里撒 n 笔高斯软笔（相加、不叠盖），方向 = theta + N(0, jit)；返回 M 内归一到 std 1 的起伏场。"""
    ys, xs = np.nonzero(R_)
    idx = rng.choice(len(ys), n)
    G = np.zeros(M.shape, np.float32)
    Rk = int(np.ceil(3 * max(length[1], width[1])))
    oy, ox = np.mgrid[-Rk:Rk + 1, -Rk:Rk + 1].astype(np.float32)
    for i in range(n):
        y, x = ys[idx[i]], xs[idx[i]]
        jx, jy = rng.uniform(-0.5, 0.5, 2)
        th = theta[y, x] + rng.normal(0, jit)
        L = rng.uniform(*length)
        Wd = rng.uniform(*width)
        amp = rng.normal(0, 1)
        cs, sn = np.cos(th), np.sin(th)
        dx, dy = ox - jx, oy - jy
        kk = amp * np.exp(-0.5 * (((dx * cs + dy * sn) / L) ** 2 + ((-dx * sn + dy * cs) / Wd) ** 2))
        y0, y1 = max(0, y - Rk), min(M.shape[0], y + Rk + 1)
        x0, x1 = max(0, x - Rk), min(M.shape[1], x + Rk + 1)
        G[y0:y1, x0:x1] += kk[y0 - (y - Rk):y1 - (y - Rk), x0 - (x - Rk):x1 - (x - Rk)]
    G = G * M
    return (G - G[R_].mean()) / (G[R_].std() + 1e-6) * M


def _belly_glaze(geo, B, P, M, Mf, body, pl, hp, var, texmul, dctr, dhw, um, em):
    """r3 第 2 次：受光左上以外的罐腹（右肩 + 下半腹）换一套肌理，参数见 BELLY。返回
    (texmul, 区域权重 wr, 积釉权重 wp, 积釉浓淡场 Pv, 细纹场, 釉流场, 镜面小光点列表)。
    wr 在 x < x_in[0] 且 y < y_in[0] 处恰为 0：受光左上（高光带、镜面短笔、次反光第一截所在）逐像素沿用原 texmul。"""
    rng = np.random.default_rng(B["seed"])
    wr = np.maximum(smoothstep(B["y_in"][0], B["y_in"][1], geo.Y), smoothstep(B["x_in"][0], B["x_in"][1], geo.X))
    Rg = M & (body > 0.02) & (wr > 0.3)
    tilt = dctr[:, None] + um * dhw[:, None]                          # 经线斜率 dx/dy（回转体：x = ctr(y) + u·hw(y)）
    theta = np.arctan2(1.0, B["tilt"] * tilt) * (1 - em) + np.arctan2(1.0, tilt) * em   # 中部近乎平行竖直，只靠边顺轮廓
    # a) 细纹两段：右肩顺经线的短软笔；下腹用 J1–J3 同一套纬线短笔（brush_texture + 细笔触层，偏角 lat_ang）。
    #    各自限幅（几笔同号叠在一处会成 −6σ 的深洞），按 y 在 mix[0:2] 间渐变，幅度 mix[2] / mix[3]
    Gm = _soft_strokes(M, Rg, rng, theta, int(Rg.sum() * B["mer_dens"]), B["mer_len"], B["mer_wid"], B["mer_jit"])
    Gl = brush_texture(geo, "J4", Rg, rng, TEX_DENSITY, TEX_LEN, TEX_WID, B["lat_ang"])
    Gl = Gl + TEX_FINE[0] * brush_texture(geo, "J4", Rg, rng, *TEX_FINE[1:], B["lat_ang"])
    Gl = (Gl - Gl[Rg].mean()) / (Gl[Rg].std() + 1e-6) * M
    gc = B["g_clip"]
    Gm, Gl = [np.where(np.abs(a) > gc, np.sign(a) * (gc + (np.abs(a) - gc) * 0.25), a) for a in (Gm, Gl)]
    y0m, y1m, au, al_ = B["mix"]
    wl_ = smoothstep(y0m, y1m, geo.Y)
    Gt = au * Gm * (1 - wl_) + al_ * Gl * wl_
    # b) 釉流：几道宽窄不一、近乎平行的直竖流（间距随机、竖向重叠的两道横向至少隔 r_gap，不往罐底收拢），
    #    暗流（积釉厚）为主、少数亮流；多数尾端一颗略深的积釉珠（水滴形，暗珠左上一点受光）；积釉处微微隆起，
    #    左上来光：左 / 上坡略亮、右 / 下坡略暗（软边，不成细亮线）。3× 超采样
    Rn = np.zeros(M.shape, np.float32)
    SS = 3
    cy, cx = np.nonzero(Rg & (geo.Y >= B["r_y"][0]) & (geo.Y <= B["r_y"][1]))
    Mi = _erode(M, 3)
    nd = int(round(B["r_n"] * B["r_dark"]))
    signs = rng.permutation(np.r_[-np.ones(nd), np.ones(B["r_n"] - nd)])
    placed = []
    for i in range(B["r_n"]):
        Lr = rng.uniform(*B["r_len"])
        for _ in range(40):
            j = rng.integers(len(cy))
            r0, c0 = int(cy[j]), int(cx[j])
            if all(abs(c0 - pc) >= B["r_gap"] or r0 > pr + pl_ or pr > r0 + Lr for pr, pc, pl_ in placed):
                break
        placed.append((r0, c0, Lr))
        w = rng.uniform(*B["r_wid"])
        th = theta[r0, c0] + rng.normal(0, 0.03)
        v = signs[i] * rng.uniform(0.6, 1.0)
        drip = rng.uniform() < B["r_drip"]
        cs, sn = np.cos(th), np.sin(th)
        while Lr > 8 and not Mi[min(int(r0 + sn * Lr), M.shape[0] - 1), min(max(int(c0 + cs * Lr), 0), M.shape[1] - 1)]:
            Lr -= 1.0                                               # 流头落在罐身里（内收 3px），不出轮廓
        xe, ye = c0 + cs * Lr, r0 + sn * Lr
        ry0, ry1 = max(r0 - 3, 0), min(int(ye + 3 * w + 4), M.shape[0])
        rx0, rx1 = max(int(min(c0, xe) - 3 * w - 4), 0), min(int(max(c0, xe) + 3 * w + 5), M.shape[1])
        if ry1 <= ry0 or rx1 <= rx0:
            continue
        gy, gx = np.mgrid[ry0 * SS:ry1 * SS, rx0 * SS:rx1 * SS].astype(np.float32)
        dx, dy = (gx + 0.5) / SS - (c0 + 0.5), (gy + 0.5) / SS - (r0 + 0.5)
        al = dx * cs + dy * sn
        ac = -dx * sn + dy * cs
        wt = w * (0.85 + 0.3 * np.clip(al / Lr, 0, 1))                 # 往下略宽（釉往下积）
        prof = (1 - smoothstep(0.0, 1.0, np.abs(ac) / wt)) * smoothstep(0.0, B["r_fade"], al) * B["r_body"]
        hl = 0.0
        if drip:
            prof = prof * (1 - smoothstep(Lr - 1.0, Lr + 0.5, al))
            bw, bl = B["r_bead_wl"][0] * w, B["r_bead_wl"][1] * w
            rho = np.sqrt(((al - Lr) / bl) ** 2 + (ac / bw) ** 2)
            prof = np.maximum(prof, (1 - smoothstep(B["r_bead_soft"], 1.0, rho)) * B["r_bead"])
            if v < 0:
                rh = np.sqrt(((al - Lr + 0.35 * bl) / (0.5 * bw)) ** 2 + ((ac - 0.4 * bw) / (0.45 * bw)) ** 2)
                hl = (1 - smoothstep(0.5, 1.0, rh)) * B["r_hl"]
        else:
            prof = prof * (1 - smoothstep(Lr - 6.0, Lr, al))
        rel = 0.0
        if v < 0:
            g_y, g_x = np.gradient(prof)
            rel = B["r_rel"] * (P["light"][0] * g_x + P["light"][1] * g_y) * SS
        Rn[ry0:ry1, rx0:rx1] += (v * prof + hl + rel).reshape(ry1 - ry0, SS, rx1 - rx0, SS).mean((1, 3))
    Rn = Rn * M
    # c) 镜面小光点位置（画在光泽层，同受光区脆亮短笔一样取场景光色、亮度 ≤ 原白瓷 5px 邻域亮端，强度 < 1）：
    #    光釉在阴影里也映着环境亮处；右肩 / 左下 / 右下分区各撒几粒，免得挤在一处
    gy_, gx_ = np.nonzero(_erode(Rg, 4) & (geo.Y >= B["gl_y"][0]) & (geo.Y <= B["gl_y"][1]))
    glints = []
    for zx0, zx1, zy0, zy1, zn in B["gl_zones"]:
        ok = (gx_ + geo.x0 >= zx0) & (gx_ + geo.x0 < zx1) & (gy_ + geo.y0 >= zy0) & (gy_ + geo.y0 < zy1)
        zy, zx = gy_[ok], gx_[ok]
        for i in range(zn):
            for _ in range(80):
                j = rng.integers(len(zy))
                r0, c0 = int(zy[j]), int(zx[j])
                if all((r0 - a) ** 2 + (c0 - b) ** 2 >= B["gl_gap"] ** 2 for a, b, *_ in glints):
                    break
            glints.append((r0, c0, rng.uniform(*B["gl_len"]), rng.normal(0, B["gl_jit"]), rng.uniform(*B["gl_amp"])))
    glints = [(c0 + geo.x0 + 0.5, r0 + geo.y0 + 0.5, L2, dth, a2) for r0, c0, L2, dth, a2 in glints]
    # d) 合成：细纹 + 原生高频按中间调加权（再乘竖向渐变），减 σ lp 以上低频；釉流不过高通（宽而软的暗流本身是局部色调）；
    #    暗侧软限（细纹暗团与流头叠在一处时不成深洞，亮侧不压）；右肩留 ur_old 成原笔意，与受光左上那片（原笔意 ×0.42）接得上
    wlo = np.interp(pl, B["w_p"], B["w_w"]).astype(np.float32)
    wlo = wlo * np.interp(geo.Y, B["vy"][:2], B["vy"][2:]).astype(np.float32)
    tl = 1 + (Gt + B["hp_amp"] * hp) * wlo * body + P["var"] * var
    tl = tl - nblur(tl, Mf, B["lp"]) + 1.0
    tl = tl + B["r_amp"] * Rn * wlo * body
    f0 = B["t_floor"]
    tl = np.where(tl < 1, 1 - f0 * np.tanh((1 - tl) / f0), tl)
    wu = smoothstep(B["x_in"][0], B["x_in"][1], geo.X) * (1 - smoothstep(B["y_in"][0], B["y_in"][1], geo.Y))
    tl = tl + B["ur_old"] * (texmul - 1.0) * wu
    texmul = texmul * (1 - wr) + tl * wr
    # e) 低频积釉浓淡（σ pool_sigma）：下腹加深、微绿
    Pv = blur(rng.normal(0, 1, M.shape).astype(np.float32), B["pool_sigma"])
    Pv = Pv / (Pv[M].std() + 1e-6)
    wp = smoothstep(B["pool_y"][0], B["pool_y"][1], geo.Y) * wr * body
    return texmul, wr, wp, Pv, Gt, Rn, glints


def render_j4(win, Y, geo, jar, P=None):
    """J4 釉面：去纹样 / 形体 / 亮度系数与通用做法相同；肌理 = 原生高频 + 顺器形短笔触 + 笔脊浮雕（按 P 加权），
    P["belly"] 非空时受光左上以外的罐腹再换 _belly_glaze 那套（细纹、釉流、积釉浓淡、镜面小光点）；
    光泽加左上腹软光、镜面高光带、次反光、镜面点与脆亮短笔、右轮廓环境反光；盖面赭斑改暖橄榄。
    P 缺省为 PAINT（r3）；传 PAINT_R2 得到 r2 的渲染。返回 (col, info)。"""
    P = PAINT if P is None else P
    name, gain, pool = jar["name"], jar["gain"], jar["pool"]
    rng = np.random.default_rng(P["seed"])
    white = np.array(jar["white"], np.float32)
    white = white / float(luma(white))
    C = geo.C[name]
    M = C > 0.5
    Mf = M.astype(np.float32)
    body = geo.body(name)
    Bn = M & (body > 0.99)
    # 1) 去纹样（同通用做法）
    Yd = local_pct(Y, M, CLOSE_R, CLOSE_Q[0])
    Yc = nblur(local_pct(Yd, M, CLOSE_R, CLOSE_Q[1]), Mf, CLOSE_SOFT)
    dark = np.clip(Yc - Y, 0, None)
    g = smoothstep(LIFT_T[0], LIFT_T[1], dark / np.maximum(Yc, 1.0)) * (1 - geo.protect(name)) * body * jar["lift"]
    Yw0 = Y + (1 - RESID_PAT) * g * dark             # 「去掉纹样后的白瓷」
    Ycap = np.maximum(Y, Yw0)                        # 逐像素亮度上限
    dens = smoothstep(DENS_T[0], DENS_T[1], nblur(g, Mf, 2.5))
    Sm = nblur(Yw0, Mf, 2.0)
    Yw = Sm + (Yw0 - Sm) * (1 - P["flat"] * dens)
    Fm = nblur(Yw, Mf, FORM_SIGMA)
    Yk = Yw * np.power(np.maximum(Fm, 1.0) / float(Fm[C > 0.99].mean()), FORM_GAMMA - 1.0)
    lo, hi = np.percentile(Yk[C > 0.99], HL_Q)
    t = smoothstep(lo, hi, Yk)
    k = gain + (HL_GAIN - gain) * t
    T = smoothstep(pool[0], pool[1], geo.Y)
    lit = 0.5 + 0.5 * smoothstep(np.percentile(Yk[C > 0.99], 20), hi, Yk)

    # 2a) 原生高频：先软开运算压掉白地细缝亮网，再取 mask 内 r=3 盒均值高通（相对量），tanh 限幅
    o0, o1, om = P["hp_open"]
    Yo = local_pct(local_pct(Yw0, M, 1, o0), M, 1, o1) * om + Yw0 * (1 - om)
    bm = box_mean(Yo * Mf, P["hp_r"]) / np.maximum(box_mean(Mf, P["hp_r"]), 1e-3)
    hp = P["hp_clip"] * np.tanh((Yo / np.maximum(bm, 1.0) - 1.0) * M / P["hp_clip"])
    hp = (hp - hp[Bn].mean()) * M

    # 2b) 短笔触：3× 超采样画平顶椭圆，不透明叠放；另记颜料厚度场做浮雕
    ys_, xs_ = np.nonzero(M)
    rows = np.arange(geo.h)
    xl = np.full(geo.h, np.nan)
    xr = np.full(geo.h, np.nan)
    for r in np.unique(ys_):
        xx = xs_[ys_ == r]
        xl[r], xr[r] = xx.min(), xx.max() + 1
    ok = ~np.isnan(xl)
    k1 = np.exp(-0.5 * (np.arange(-9, 10) / 3.0) ** 2)
    k1 /= k1.sum()
    xl = np.convolve(np.pad(np.interp(rows, rows[ok], xl[ok]), 9, mode="edge"), k1, "valid")
    xr = np.convolve(np.pad(np.interp(rows, rows[ok], xr[ok]), 9, mode="edge"), k1, "valid")
    ctr, hw = (xl + xr) / 2, np.maximum((xr - xl) / 2, 1.0)          # 每行轮廓中心与半宽（窗内列坐标）
    dctr, dhw = np.gradient(ctr), np.gradient(hw)
    um = np.clip((np.arange(geo.w, dtype=np.float32)[None, :] + 0.5 - ctr[:, None]) / hw[:, None], -1, 1)
    mer = np.arctan2(1.0, dctr[:, None] + um * dhw[:, None])         # 经线切向（回转体：x = ctr(y) + u·hw(y)）
    em = smoothstep(P["st_edge"][0], P["st_edge"][1], np.abs(um))
    SS = 3
    Fs = np.zeros((geo.h * SS, geo.w * SS), np.float32)
    Hs = np.zeros_like(Fs)
    by, bx = np.nonzero(M & (body > 0.02))
    pick = rng.choice(len(by), P["st_n"])
    Phi = blur(rng.normal(0, 1, Y.shape).astype(np.float32), P["ang_sigma"])
    Phi /= Phi[M].std() + 1e-6
    theta = mer + (1 - em) * P["ang_spread"] * Phi
    Vf = blur_xy(rng.normal(0, 1, Y.shape).astype(np.float32), *P["val_sigma"])
    Vf /= Vf[M].std() + 1e-6
    R = int(np.ceil(SS * (P["st_len"][1] + 1.5)))
    oy, ox = np.mgrid[-R:R + 1, -R:R + 1].astype(np.float32) / SS
    for i in range(P["st_n"]):
        r0, c0 = by[pick[i]], bx[pick[i]]
        jx, jy = rng.uniform(-0.5, 0.5, 2)
        th = theta[r0, c0] + rng.normal(0, P["st_jit"])
        L = rng.uniform(*P["st_len"])
        W = rng.uniform(*P["st_wid"])
        kap = rng.normal(0, P["st_kap"])                            # 笔触微弯
        v = float(np.clip(P["val_mix"][0] * Vf[r0, c0] + P["val_mix"][1] * rng.normal(0, 1), *P["val_clip"]))
        op = rng.uniform(*P["st_op"])
        cs, sn = np.cos(th), np.sin(th)
        dx, dy = ox - jx, oy - jy
        al = dx * cs + dy * sn
        ac = -dx * sn + dy * cs - kap * al * al
        rho = np.sqrt(np.abs(al / L) ** P["st_pow"] + (ac / W) ** 2)     # 沿笔方向超椭圆：笔头钝圆，不成尖头叶片
        a = (1 - smoothstep(P["st_soft"], 1.0, rho)) * op
        Y0, X0 = r0 * SS + SS // 2 - R, c0 * SS + SS // 2 - R
        y0, x0 = max(Y0, 0), max(X0, 0)
        y1, x1 = min(Y0 + 2 * R + 1, Fs.shape[0]), min(X0 + 2 * R + 1, Fs.shape[1])
        aa = a[y0 - Y0:y1 - Y0, x0 - X0:x1 - X0]
        hh = (1 - smoothstep(0.2, 1.0, rho))[y0 - Y0:y1 - Y0, x0 - X0:x1 - X0]
        Fs[y0:y1, x0:x1] = Fs[y0:y1, x0:x1] * (1 - aa) + v * aa
        Hs[y0:y1, x0:x1] = Hs[y0:y1, x0:x1] * (1 - aa) + hh * aa
    F = Fs.reshape(geo.h, SS, geo.w, SS).mean((1, 3))
    F = (F - F[Bn].mean()) / (F[Bn].std() + 1e-6) * M
    gy_, gx_ = np.gradient(Hs)
    Rl = ((P["light"][0] * gx_ + P["light"][1] * gy_) * SS).reshape(geo.h, SS, geo.w, SS).mean((1, 3))
    Rl = (Rl - Rl[Bn].mean()) / (Rl[Bn].std() + 1e-6) * M
    var = blur(rng.normal(0, 1, Y.shape).astype(np.float32), 6.0)
    var /= var[M].std() + 1e-6

    # 3) 合成亮度：底层 × 肌理（肌理去掉 σ5 以上低频），原画高光留住，软光，逐像素封顶
    #    肌理按中间调加权（暗部 / 亮部都收），受光左上再压一档：最该光滑出镜面的地方不再最花
    pl = smoothstep(np.percentile(Yk[C > 0.99], 15), np.percentile(Yk[C > 0.99], 90), nblur(Yk, Mf, 3.0))
    midw = np.interp(pl, P["mid_p"], P["mid_w"]).astype(np.float32)
    ux, uy0, uy1, uf, ua = P["ul"]
    ulw = (1 - smoothstep(ux - uf, ux + uf, geo.X)) * smoothstep(uy0 - uf, uy0 + uf, geo.Y) * (1 - smoothstep(uy1 - uf, uy1 + uf, geo.Y))
    midw = midw * (1 - ua * ulw)
    vy0, vy1, vf0, vf1 = P["tex_vy"]
    midw = midw * np.interp(geo.Y, [vy0, vy1], [vf0, vf1]).astype(np.float32)
    litS = pl
    F = np.where(F < 0, F * (1 - P["st_neg_lit"] * litS), F)
    texmul = 1 + (P["relief"] * Rl + P["hp_amp"] * hp + P["st_amp"] * F) * midw * body + P["var"] * var
    texmul = texmul - nblur(texmul, Mf, P["tex_lp"]) + 1.0
    B = P.get("belly")
    if B:           # 受光左上以外的罐腹换 BELLY 那套肌理（左上那片 wr=0，texmul 逐像素不变）
        texmul, wr, wp, Pv, Gt, Rn, glints = _belly_glaze(geo, B, P, M, Mf, body, pl, hp, var, texmul, dctr, dhw, um, em)
    Ynew = Yk * k * (1 - 0.10 * T) * texmul
    if B:
        Ynew = Ynew * (1 - B["pool_dark"] * wp + B["pool_amp"] * np.clip(Pv, -2.5, 2.5) * wp)
    ws = smoothstep(*np.percentile(Y[C > 0.99], SPEC_Q), Y) * (C > 0.5)
    Ynew = Ynew * (1 - ws) + np.maximum(Ynew, Y * SPEC_GAIN) * ws
    tt = np.maximum(t, ws)
    gx, gy, sx, sy, gamt = P["glow"]
    Ynew = Ynew * (1 + gamt * np.exp(-0.5 * (((geo.X - gx) / sx) ** 2 + ((geo.Y - gy) / sy) ** 2)) * M)
    Ynew = np.minimum(Ynew, Ycap)

    # 4) 色：场景白点 × 釉本色；积釉加深、高光向光色收；肌理亮处略退色、暗处略深
    body_c = white * np.array(jar["albedo"], np.float32)
    body_c = body_c / float(luma(body_c))
    f = (1.0 + 0.35 * T + VAR_CHROMA * var) * (1 - HL_DESAT * tt)
    f = f * np.clip(1 - P["tex_desat"] * (texmul - 1) * body, 0.35, 1.6)
    if B:           # 积釉处色度略浓、色相微向绿偏
        f = f * (1 + B["pool_chroma"] * wp * np.clip(0.6 - 0.4 * Pv, 0, 1.6))
        green = white * np.array(B["pool_albedo"], np.float32)
        green = green / float(luma(green))
        body_c = body_c[None, None, :] + (green - body_c)[None, None, :] * (B["pool_green"] * wp)[..., None]
    ratio = white + f[..., None] * (body_c - white)
    ratio = ratio / np.maximum(luma(ratio), 1e-3)[..., None]
    # 盖同釉改色，但盖面原有一块赭色暖斑（原图 B/R、G/R 都明显低于场景白点）：改暖橄榄，亮度向原图收回 patch_keep
    brel = ((win[..., 2] + 1) / (win[..., 0] + 1)) / jar["white"][2]
    grel = ((win[..., 1] + 1) / (win[..., 0] + 1)) / jar["white"][1]
    px0, py0, px1, py1 = P["patch_box"]
    pz = ((geo.X > px0) & (geo.X < px1) & (geo.Y > py0) & (geo.Y < py1)).astype(np.float32)
    pw = smoothstep(0.85, 0.62, brel) * smoothstep(0.97, 0.86, grel) * pz * (Y > 45) * (1 - body)
    pw = np.clip(blur(pw.astype(np.float32), 0.8) * 1.3, 0, 1) * M * P["patch_amt"]
    warm = white * np.array(P["patch_col"], np.float32)
    warm = warm / float(luma(warm))
    ratio = ratio * (1 - pw[..., None]) + warm[None, None, :] * pw[..., None]
    ratio = ratio / np.maximum(luma(ratio), 1e-3)[..., None]
    Yp = np.minimum(Ynew / np.maximum(k, 1e-3) * ((1 - P["patch_keep"]) * k + P["patch_keep"]), Ycap)
    Ynew = Ynew * (1 - pw) + Yp * pw
    col = ratio * Ynew[..., None]
    wk = smoothstep(*np.percentile(Y[C > 0.99], SPEC_KEEP_Q), Y) * (~scene_blue(win.astype(np.uint8))) * (C > 0.5)
    col = col * (1 - wk[..., None]) + win * (Ynew / np.maximum(Y, 1.0))[..., None] * wk[..., None]

    # 5) 光泽：镜面高光带 + 次反光 + 镜面点，色取场景光色，亮度 ≤ min(spec_Y, 原白瓷 cap_r 邻域亮端)
    capR = _slide(np.where(M, nblur(Ycap, Mf, 1.0), 0), P["cap_r"], np.max)
    spec = white[None, None, :] * np.minimum(capR, P["spec_Y"])[..., None]
    yb = geo.Y
    pts = np.array(P["band"], np.float32)
    inb = smoothstep(pts[0, 1] - 1.5, pts[0, 1] + 1.5, yb) * (1 - smoothstep(pts[-1, 1] - 6, pts[-1, 1], yb))
    bw = np.interp(yb, [pts[0, 1], pts[-1, 1]], P["band_w"])
    brk = 1 - P["band_brk"] * (0.5 + 0.5 * np.cos((yb - pts[0, 1]) / 2.6 + 0.4)) * (0.5 + 0.5 * np.cos((yb - pts[0, 1]) / 4.3))
    gl = np.exp(-0.5 * np.abs((geo.X - np.interp(yb, pts[:, 1], pts[:, 0])) / bw) ** P["band_pow"]) * inb * brk \
        * np.interp(yb, [pts[0, 1], pts[-1, 1]], P["band_taper"]) * M
    gl = np.clip(P["band_amt"] * gl, 0, 1)
    for p2, w2, a2, segs in P["streaks"]:                           # 次反光：宽 3–4px、高斯软边、断成几截
        p2 = np.array(p2, np.float32)
        on = np.zeros_like(yb)
        for sa, sb in segs:
            on = np.maximum(on, smoothstep(sa - 1.5, sa + 1.5, yb) * (1 - smoothstep(sb - 1.5, sb + 1.5, yb)))
        s2 = np.exp(-0.5 * ((geo.X - np.interp(yb, p2[:, 1], p2[:, 0])) / w2) ** 2) * on * M
        gl = np.maximum(gl, np.clip(a2 * s2, 0, 1))
    for x2, y2, s2, a2 in P["glints"]:
        gl = np.maximum(gl, np.clip(a2 * np.exp(-0.5 * (((geo.X - x2) / (0.8 * s2)) ** 2 + ((geo.Y - y2) / s2) ** 2)) * M, 0, 1))
    # 脆亮镜面短笔（仿 J3 左肩）：3× 超采样平顶细椭圆，方向 = 该处经线 + 偏角，硬边
    SSk = 3
    oyk, oxk = np.mgrid[0:geo.h * SSk, 0:geo.w * SSk].astype(np.float32)
    sk_list = [s + (P["speck_w"],) for s in P["specks"]]
    if B:           # 右肩 / 下腹阴影里的几粒镜面小光点（位置见 _belly_glaze）：同一画法，略细、强度 < 1
        sk_list += [g_ + (B["gl_wid"],) for g_ in glints]
    for x2, y2, L2, dth, a2, w2 in sk_list:
        r0, c0 = int(y2 - geo.y0), int(x2 - geo.x0)
        th = mer[r0, c0] + dth
        cs, sn = np.cos(th), np.sin(th)
        y_lo, y_hi = max((r0 - 5) * SSk, 0), min((r0 + 6) * SSk, oyk.shape[0])
        x_lo, x_hi = max((c0 - 5) * SSk, 0), min((c0 + 6) * SSk, oyk.shape[1])
        dx = (oxk[y_lo:y_hi, x_lo:x_hi] + 0.5) / SSk + geo.x0 - x2
        dy = (oyk[y_lo:y_hi, x_lo:x_hi] + 0.5) / SSk + geo.y0 - y2
        rho = np.sqrt(((dx * cs + dy * sn) / L2) ** 2 + ((-dx * sn + dy * cs) / w2) ** 2)
        a = np.zeros(oyk.shape, np.float32)
        a[y_lo:y_hi, x_lo:x_hi] = (1 - smoothstep(0.7, 1.0, rho)) * a2
        a = a.reshape(geo.h, SSk, geo.w, SSk).mean((1, 3)) * M
        gl = np.maximum(gl, np.clip(a, 0, 1))
    col = col * (1 - gl[..., None]) + np.maximum(col, spec) * gl[..., None]
    # 右轮廓内一道弱的环境反光（原图右轮廓本有亮边），亮度 ×(1+rim_gain)、不越原白瓷
    u0, ry0, ry1, rw, ramt = P["rim"]
    rx = geo.x0 + ctr[:, None] + u0 * hw[:, None]
    rim = np.exp(-0.5 * ((geo.X - rx) / rw) ** 2) * smoothstep(ry0, ry0 + 6, geo.Y) * (1 - smoothstep(ry1 - 8, ry1, geo.Y)) * M
    rim = ramt * rim * (0.75 + 0.25 * np.cos((geo.Y - ry0) / 3.7))
    rimc = white * np.array(P["rim_col"], np.float32)
    rimc = rimc / float(luma(rimc))
    rimY = np.minimum(luma(col) * (1 + P["rim_gain"]), Ycap)
    col = col * (1 - rim[..., None]) + rimc[None, None, :] * rimY[..., None] * rim[..., None]
    info = dict(g=g, Yc=Yc, t=t, Ycap=Ycap, capR=capR, gloss=gl, rim=rim, patch=pw, texw=midw * body, texmul=texmul, texp=pl)
    if B:
        info.update(belly_wr=wr, belly_wp=wp, belly_G=Gt, belly_R=Rn, belly_glints=glints)
    return col, info


def render(src, geo, seed=1277):
    win = src[geo.y0:geo.y1, geo.x0:geo.x1].astype(np.float32)
    Y = luma(win)
    out = win.copy()
    info = {}
    rng = np.random.default_rng(seed)
    for jar in JARS:
        if jar["name"] == "J4":                     # 最大、最靠前的一只：单独做肌理与光泽
            col, info["J4"] = render_j4(win, Y, geo, jar, PAINT)
            # BODY_LINE 以上（盖、盖钮、罐肩）逐像素沿用 r2 渲染（评审已过）；罐腹换 r3，按罐腹权重合成
            col_r2, _ = render_j4(win, Y, geo, jar, PAINT_R2)
            wb = geo.body("J4")[..., None]
            col = col * wb + col_r2 * (1 - wb)
            out = out * (1 - geo.A["J4"][..., None]) + col * geo.A["J4"][..., None]
            continue
        name, alb, gain, pool = jar["name"], jar["albedo"], jar["gain"], jar["pool"]
        white = np.array(jar["white"], np.float32)
        white = white / float(luma(white))
        C, A = geo.C[name], geo.A[name]
        M = C > 0.5
        Mf = M.astype(np.float32)
        # 1) 纹样：软闭运算（92 分位膨胀 → 12 分位腐蚀）抹掉比邻域窄的暗笔触；比闭运算暗得多的像素按比例提回去，
        #    只在罐腹做；留 RESID_PAT 的起伏当釉层厚薄
        Yd = local_pct(Y, M, CLOSE_R, CLOSE_Q[0])
        Yc = nblur(local_pct(Yd, M, CLOSE_R, CLOSE_Q[1]), Mf, CLOSE_SOFT)
        dark = np.clip(Yc - Y, 0, None)
        g = smoothstep(LIFT_T[0], LIFT_T[1], dark / np.maximum(Yc, 1.0)) * (1 - geo.protect(name)) * geo.body(name)
        g = g * jar["lift"]
        Yw = Y + (1 - RESID_PAT) * g * dark          # 「去掉纹样后的白瓷」亮度
        Ycap = np.maximum(Y, Yw)                     # 逐像素亮度上限：不亮过它换掉的白瓷
        # 1a) 纹样密处：白地夹在蓝花之间的细亮缝提完暗笔触后会连成一张亮网（纹样的「底片」），
        #     按纹样局部密度把细节向 σ2 平滑收 flat，只留一点笔意，缺的肌理由第 2 步的笔触补
        dens = smoothstep(DENS_T[0], DENS_T[1], nblur(g, Mf, 2.5))
        Sm = nblur(Yw, Mf, 2.0)
        Yw = Sm + (Yw - Sm) * (1 - jar["flat"] * dens)
        # 1b) 形体明暗：罐内大尺度受光按 FORM_GAMMA 拉开（青花罐的明暗有一半靠白地/蓝花对比撑着，换成单色釉要补回体积）
        Fm = nblur(Yw, Mf, FORM_SIGMA)
        fmean = float(Fm[C > 0.99].mean())
        Yk = Yw * np.power(np.maximum(Fm, 1.0) / fmean, FORM_GAMMA - 1.0)
        # 2) 亮度：整体乘 gain（青黄釉比白瓷暗），高光段渐回 HL_GAIN（亮釉镜面反光不随釉色压暗）
        lo, hi = np.percentile(Yk[C > 0.99], HL_Q)
        t = smoothstep(lo, hi, Yk)
        k = gain + (HL_GAIN - gain) * t
        # 积釉：下腹压暗一档；釉面笔触肌理（沿纬线的短笔触，受光处更显）与窑变低频起伏
        T = smoothstep(pool[0], pool[1], geo.Y)
        tex = brush_texture(geo, name, M, rng, TEX_DENSITY, TEX_LEN, TEX_WID)
        tex = tex + TEX_FINE[0] * brush_texture(geo, name, M, rng, *TEX_FINE[1:])
        tex = tex / (tex[M].std() + 1e-6)
        lit = 0.5 + 0.5 * smoothstep(np.percentile(Yk[C > 0.99], 20), hi, Yk)
        var = blur(rng.normal(0, 1, Y.shape).astype(np.float32), 6.0)
        var /= var[M].std() + 1e-6
        Ynew = Yk * k * (1 - 0.10 * T) * (1 + jar["tex"] * lit * tex * geo.body(name) + VAR_AMP * var)
        # 2b) 原画高光（罐内亮度前 SPEC_Q 分位：口沿、盖沿、左肩受光）原样留住，只乘 SPEC_GAIN、色收向光色
        ws = smoothstep(*np.percentile(Y[C > 0.99], SPEC_Q), Y) * (C > 0.5)
        Ynew = Ynew * (1 - ws) + np.maximum(Ynew, Y * SPEC_GAIN) * ws
        t = np.maximum(t, ws)
        Ynew = np.minimum(Ynew, Ycap)
        # 3) 色：场景白点 × 釉本色；积釉色度加深，高光向光色收；窑变：色度随低频起伏略浓淡
        a = np.array(alb, np.float32)
        body = white * a
        body = body / float(luma(body))
        f = (1.0 + 0.35 * T + VAR_CHROMA * var) * (1 - HL_DESAT * t)
        ratio = white + f[..., None] * (body - white)
        ratio = ratio / np.maximum(luma(ratio), 1e-3)[..., None]
        col = ratio * Ynew[..., None]
        # 3b) 最亮的镜面点（原亮度 96–99.5 分位、原色非青蓝）是光源的颜色，与釉色无关：直接用原像素色按新亮度缩放，
        #     免得近白的高光被釉色染绿后 L* 反而升高
        wk = smoothstep(*np.percentile(Y[C > 0.99], SPEC_KEEP_Q), Y) * (~scene_blue(win.astype(np.uint8))) * (C > 0.5)
        col = col * (1 - wk[..., None]) + win * (Ynew / np.maximum(Y, 1.0))[..., None] * wk[..., None]
        out = out * (1 - A[..., None]) + col * A[..., None]
        info[name] = dict(g=g, Yc=Yc, t=t)
    return np.clip(out + 0.5, 0, 255).astype(np.uint8), info


# ---------- 写出：4:2:0 按 MCU 分块 jpegtran -drop ----------
def mcu_size(img):
    s = JpegImagePlugin.get_sampling(img)
    return {0: (8, 8), 1: (16, 8), 2: (16, 16)}.get(s), s


def mcu_rects(changed, mcu):
    """改动像素所在 MCU，按 MCU 行把相邻块并成矩形（裁到图内）。"""
    mw, mh = mcu
    H, W = changed.shape
    gh, gw = -(-H // mh), -(-W // mw)
    pad = np.zeros((gh * mh, gw * mw), bool)
    pad[:H, :W] = changed
    hit = pad.reshape(gh, mh, gw, mw).any((1, 3))
    rects = []
    for j in range(gh):
        i = 0
        while i < gw:
            if hit[j, i]:
                k = i
                while k + 1 < gw and hit[j, k + 1]:
                    k += 1
                rects.append((i * mw, j * mh, min((k + 1) * mw, W), min((j + 1) * mh, H)))
                i = k + 1
            else:
                i += 1
    return rects


def decode_nosmooth(path):
    dj = shutil.which("djpeg")
    if not dj:
        return None
    r = subprocess.run([dj, "-nosmooth", "-ppm", path], capture_output=True)
    if r.returncode != 0:
        return None
    import io
    return np.asarray(Image.open(io.BytesIO(r.stdout)).convert("RGB"))


def write_jpeg_mcu(src_path, src_img, new_img, changed, out_path):
    """改动 MCU 按行并成矩形，逐块同量化表同抽样编码后 jpegtran -drop 嵌回。
    块内没改的像素喂 djpeg -nosmooth 的解码（色度按块复制放大）而不是 PIL 的 fancy 解码：编码器 2×2 平均回去正好
    还原原色度样本，重量化几乎落回原系数，块内 mask 外的代际损失小得多（实测见自检）。"""
    mcu, sampling = mcu_size(src_img)
    jt = shutil.which("jpegtran")
    if not jt or mcu is None:
        raise SystemExit("需要 jpegtran 与基线 JPEG（sampling=%s）；未写任何文件。" % sampling)
    rects = mcu_rects(changed, mcu)
    qt = src_img.quantization
    base = decode_nosmooth(src_path)
    tiles = new_img if base is None else np.where(changed[..., None], new_img, base)
    with tempfile.TemporaryDirectory() as td:
        cur = os.path.join(td, "cur.jpg")
        shutil.copyfile(src_path, cur)
        for n, (x0, y0, x1, y1) in enumerate(rects):
            drop = os.path.join(td, "drop.jpg")
            nxt = os.path.join(td, "nxt%d.jpg" % (n % 2))
            Image.fromarray(np.ascontiguousarray(tiles[y0:y1, x0:x1])).save(drop, "JPEG", qtables=qt, subsampling=sampling)
            r = subprocess.run([jt, "-copy", "all", "-drop", "+%d+%d" % (x0, y0), drop, "-outfile", nxt, cur],
                               capture_output=True, text=True)
            if r.returncode != 0:
                raise SystemExit("jpegtran -drop +%d+%d 失败（rc=%d %s）；未写任何文件。" % (x0, y0, r.returncode, r.stderr.strip()[:120]))
            shutil.copyfile(nxt, cur)
        inside = np.zeros(changed.shape, bool)
        for x0, y0, x1, y1 in rects:
            inside[y0:y1, x0:x1] = True
        a, b = decode_nosmooth(cur), decode_nosmooth(src_path)
        if a is not None and b is not None:
            bad = int((a[~inside] != b[~inside]).any(-1).sum())
            if bad:
                raise SystemExit("djpeg -nosmooth 核对：改动块外有 %d 像素变了，未写任何文件。" % bad)
        os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
        shutil.copyfile(cur, out_path)
    return rects, inside


# ---------- 自检 ----------
def jar_masks(geo, thr=0.99):
    return {n: geo.full((geo.C[n] > thr).astype(np.uint8)).astype(bool) for n in geo.C}


def blue_report(img, geo):
    ms = jar_masks(geo)
    std = hsv_blue(img, BLUE_VMIN)
    sce = scene_blue(img)
    rep = {n: (float(std[m].mean()), float(sce[m].mean())) for n, m in ms.items()}
    m234 = ms["J2"] | ms["J3"] | ms["J4"]
    rep["J2-4"] = (float(std[m234].mean()), float(sce[m234].mean()))
    mall = m234 | ms["J1"]
    rep["全部"] = (float(std[mall].mean()), float(sce[mall].mean()))
    return rep


def _dilate(m, k):
    for _ in range(k):
        p = np.pad(m, 1, constant_values=False)
        m = m | p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:]
    return m


# 肌理量测框（罐腹干净处，评审口径 HF3/MF9 = 亮度减 3×3/9×9 盒均值后的标准差 ÷ 均亮）与同画参照
TEX_RECTS = {"J1": (1118, 825, 1165, 870), "J2": (1203, 832, 1248, 850), "J3": (1260, 832, 1284, 852),
             "J4": (1295, 852, 1355, 905)}
TEX_REFS = {"B2 棕釉罐": (1228, 875, 1278, 920), "大水缸": (1292, 722, 1368, 760)}


def self_check(before, after, geo, rects_inside, src_path, out_path):
    rep = {}
    ms = jar_masks(geo)
    A = geo.full(geo.A_all)
    C = geo.full(geo.C_all)
    diff = np.abs(after.astype(np.int16) - before.astype(np.int16))
    outside = A == 0
    rep["out_mad"] = float(diff[outside].mean())
    rep["out_in_rect_mad"] = float(diff[outside & rects_inside].mean())
    rep["out_in_rect_max"] = int(diff[outside & rects_inside].max())
    d1 = diff.max(-1)
    rep["rect_out_px_pil"] = int((d1[~rects_inside] > 0).sum())
    H_, W_ = rects_inside.shape
    p = np.pad(rects_inside, 1, constant_values=False)
    ring1 = np.zeros_like(rects_inside)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            ring1 |= p[1 + dy:1 + dy + H_, 1 + dx:1 + dx + W_]
    ring1 &= ~rects_inside
    rep["rect_out_px_pil_beyond1"] = int((d1[~rects_inside & ~ring1] > 0).sum())
    rep["rect_out_max_pil"] = int(d1[~rects_inside].max())
    a, b = decode_nosmooth(out_path), decode_nosmooth(src_path)
    rep["rect_out_px_nosmooth"] = None if a is None or b is None else int((a[~rects_inside] != b[~rects_inside]).any(-1).sum())
    # 边界 ΔE76：外轮廓外 1–3px（应≈0，只剩 4:2:0 色度 2×2 共用带过去的一点）、轮廓混色圈、内侧 1–2px
    labb, laba = srgb_to_lab(before), srgb_to_lab(after)
    dE = np.sqrt(((laba - labb) ** 2).sum(-1))
    m0 = C > 0
    ring_out = _dilate(m0, 3) & ~m0
    ring_edge = (C > 0) & (C < 0.99)
    core = C >= 0.99
    ring_in = core & ~_erode(core, 2)
    rep["dE"] = (float(dE[ring_out].mean()), float(dE[ring_edge].mean()), float(dE[ring_in].mean()))
    Lb, La = labb[..., 0], laba[..., 0]
    rep["step"] = (float(Lb[ring_in].mean() - Lb[ring_out].mean()), float(La[ring_in].mean() - La[ring_out].mean()))
    # 各罐：亮度（均亮、原白地亮端同批像素）、L* 峰值与亮釉高光像素数、釉色、肌理
    Yb, Ya = luma(before.astype(np.float32)), luma(after.astype(np.float32))
    sb = scene_blue(before)
    rep["jar"] = {}
    for n, m in ms.items():
        lo, hi = np.percentile(Yb[m], [75, 97])
        wg = m & (Yb >= lo) & (Yb <= hi) & ~sb
        Lm = laba[m]
        mid = (Lm[:, 0] >= 25) & (Lm[:, 0] < 50)
        hue = float(np.median(np.degrees(np.arctan2(Lm[mid, 2], Lm[mid, 1])) % 360))
        chroma = float(np.median(np.hypot(Lm[mid, 1], Lm[mid, 2])))
        cm = after[m].astype(np.float64).mean(0)
        rep["jar"][n] = dict(
            luma=(float(Yb[m].mean()), float(Ya[m].mean())),
            white=(float(Yb[wg].mean()), float(Ya[wg].mean())),
            p97=(float(np.percentile(Yb[m], 97)), float(np.percentile(Ya[m], 97))),
            brighter=float((Ya[m] > Yb[m] + 1).mean()),
            Lmax=(float(Lb[m].max()), float(La[m].max())),
            nhl=(int((Lb[m] > 65).sum()), int((La[m] > 65).sum())),
            hue=hue, chroma=chroma, gr=cm[1] / cm[0], br=cm[2] / cm[0],
            tex=(texture(before, TEX_RECTS[n]), texture(after, TEX_RECTS[n])))
    rep["tex_ref"] = {k: texture(before, r) for k, r in TEX_REFS.items()}
    return rep


def _line(x, n, axis):
    """沿 axis 的 n 点盒均值（same 尺寸，边缘按实际点数平均）。"""
    c = np.cumsum(np.pad(x, [(n // 2 + 1, n // 2) if a == axis else (0, 0) for a in range(2)]), axis=axis)
    s = np.take(c, np.arange(n, c.shape[axis]), axis=axis) - np.take(c, np.arange(0, c.shape[axis] - n), axis=axis)
    return s / n


def j4_check(before, after, geo, info, mem):
    """J4 专项：r1 评审四条（罐腹高频 std/均值、横向长拖痕超额、镜面高光带 L* 与封顶、盖面暖斑）+ r2 评审三条
    （四象限高频、罐腹高频偏度、结构张量方向一致性）。"""
    rep = {}
    body = geo.full(geo.body("J4").astype(np.float32)) > 0.99
    ms = jar_masks(geo)
    for n in ("J1", "J2", "J3", "J4"):
        bb = geo.full(geo.body(n).astype(np.float32)) > 0.99
        m = _erode(ms[n] & bb, 3)
        x0, y0, x1, y1 = TEX_RECTS[n]
        rm = np.zeros_like(m)
        rm[y0:y1, x0:x1] = True
        vals = []
        for img in (before, after):
            Yl = luma(img.astype(np.float32)).astype(np.float64)
            hp = Yl - box_mean(Yl, 3)
            vals.append((hp[rm].std() / Yl[rm].mean(), hp[m].std() / Yl[m].mean(), hp[rm].std()))
        rep["rev_" + n] = vals
    rep["rev_ref"] = {}
    for k_, (x0, y0, x1, y1) in TEX_REFS.items():
        Yl = luma(before.astype(np.float32)).astype(np.float64)
        hp = Yl - box_mean(Yl, 3)
        rep["rev_ref"][k_] = hp[y0:y1, x0:x1].std() / Yl[y0:y1, x0:x1].mean()
    # r2 评审三条（r3 目标）：J4 框 (1292,850)-(1360,925) 对半四象限的高频 std/均亮（∩ 罐身内收 3px）；
    # 罐腹（BODY_LINE 以下、内收 3px）高频偏度（光釉 = 平滑面 + 稀疏亮镜点 = 强正偏）；
    # 结构张量方向一致性（Sobel 梯度、σ1 积分、能量加权的 coherence²；评审原脚本未给，此设定对 HEAD / r1 / r2 的 J4
    # 与 J1、B2、水缸六个评审数都在 ±0.03 内）
    e4 = _erode(ms["J4"], 3)
    quads = dict(左上=(850, 887, 1292, 1326), 右上=(850, 887, 1326, 1360), 左下=(887, 925, 1292, 1326), 右下=(887, 925, 1326, 1360))
    rep["quad"], rep["skew"], rep["coh"] = [], [], []
    for img in (before, after):
        Yl = luma(img.astype(np.float32)).astype(np.float64)
        hp = Yl - box_mean(Yl, 3)
        qd = {}
        for k_, (y0, y1, x0, x1) in quads.items():
            mm = np.zeros_like(e4)
            mm[y0:y1, x0:x1] = True
            mm &= e4
            qd[k_] = float(hp[mm].std() / Yl[mm].mean())
        rep["quad"].append(qd)
        sk = {}
        for n in ("J1", "J3", "J4"):
            bb = geo.full(geo.body(n).astype(np.float32)) > 0.99
            v = hp[_erode(ms[n] & bb, 3)]
            v = v - v.mean()
            sk[n] = float((v ** 3).mean() / (v ** 2).mean() ** 1.5)
        rep["skew"].append(sk)
        ch = {}
        p = np.pad(Yl, 1, mode="edge")
        gx = ((p[:-2, 2:] + 2 * p[1:-1, 2:] + p[2:, 2:]) - (p[:-2, :-2] + 2 * p[1:-1, :-2] + p[2:, :-2])) / 8
        gy = ((p[2:, :-2] + 2 * p[2:, 1:-1] + p[2:, 2:]) - (p[:-2, :-2] + 2 * p[:-2, 1:-1] + p[:-2, 2:])) / 8
        Jxx, Jxy, Jyy = blur(gx * gx, 1.0), blur(gx * gy, 1.0), blur(gy * gy, 1.0)
        den = Jxx + Jyy
        c2 = ((Jxx - Jyy) ** 2 + 4 * Jxy ** 2) / np.maximum(den, 1e-9)
        for n in ("J1", "J4"):
            bb = geo.full(geo.body(n).astype(np.float32)) > 0.99
            mm = _erode(ms[n] & bb, 3)
            ch[n] = float(c2[mm].sum() / den[mm].sum())
        rep["coh"].append(ch)
    # r3 第 1 次评审补的两条：下腹（罐腹内收 3px、y≥887）亮度减 7×7 盒均值后的横向自相关最低值（lag1–10，J1 −0.15，
    # 规则竖条纹会到 −0.4）与竖向 lag3（竖缕会拖到 0.4）；方向一致性另按评审六种结构张量设定（预糊 σ、积分 σ、梯度算子）取最小
    e4b = _erode(ms["J4"] & body, 3)
    low = e4b & (np.arange(SIZE[1])[:, None] >= 887)
    rep["acf"], rep["coh6"] = [], []
    for img in (before, after):
        Yl = luma(img.astype(np.float32)).astype(np.float64)
        hp = Yl - box_mean(Yl, 3)
        ys, xs = np.nonzero(low)
        ac = {}
        for nm, (dy, dx) in (("h", (0, 1)), ("v", (1, 0))):
            vals = []
            for lag in range(1, 11):
                y2, x2 = ys + lag * dy, xs + lag * dx
                ok = low[np.clip(y2, 0, SIZE[1] - 1), np.clip(x2, 0, SIZE[0] - 1)]
                vals.append(float(np.corrcoef(hp[ys[ok], xs[ok]], hp[y2[ok], x2[ok]])[0, 1]))
            ac[nm] = vals
        rep["acf"].append((min(ac["h"]), ac["v"][2]))
        c6 = []
        for pre, integ, sob in ((1.0, 2.0, True), (0.7, 3.0, True), (1.0, 3.0, True), (0.0, 2.0, True), (1.0, 1.5, False), (1.5, 4.0, True)):
            Lb = blur(Yl.astype(np.float32), pre).astype(np.float64) if pre > 0 else Yl
            if sob:
                p = np.pad(Lb, 1, mode="reflect")
                gx = (p[:-2, 2:] + 2 * p[1:-1, 2:] + p[2:, 2:] - p[:-2, :-2] - 2 * p[1:-1, :-2] - p[2:, :-2]) / 8
                gy = (p[2:, :-2] + 2 * p[2:, 1:-1] + p[2:, 2:] - p[:-2, :-2] - 2 * p[:-2, 1:-1] - p[:-2, 2:]) / 8
            else:
                gy, gx = np.gradient(Lb)
            Jxx, Jyy, Jxy = (blur(a.astype(np.float32), integ).astype(np.float64) for a in (gx * gx, gy * gy, gx * gy))
            tr = Jxx + Jyy
            cc = np.sqrt((Jxx - Jyy) ** 2 + 4 * Jxy ** 2) / np.maximum(tr, 1e-9)
            c6.append(float((cc * tr)[e4b].sum() / tr[e4b].sum()))
        rep["coh6"].append(c6)
    # 横向长拖痕：亮度减 3×3 均值后，13px 横向 / 竖向盒均值响应的标准差；超额 = sqrt(max(H²−V², 0))
    m4 = _erode(ms["J4"] & body, 3)
    rep["streak"] = []
    for img in (before, after):
        Yl = luma(img.astype(np.float32)).astype(np.float64)
        h1 = Yl - box_mean(Yl, 1)
        H, V = _line(h1, 13, 1)[m4].std(), _line(h1, 13, 0)[m4].std()
        rep["streak"].append((H, V, float(np.sqrt(max(H * H - V * V, 0.0)))))
    # 镜面高光带：带区 L* 峰值；光泽层（高光带 / 次反光 / 镜面点，权重>0.2）比逐像素原白瓷亮多少、是否越过 5px 邻域亮端
    La, Lb = srgb_to_lab(after)[..., 0], srgb_to_lab(before)[..., 0]
    breg = np.zeros_like(m4)
    breg[850:873, 1301:1315] = True
    breg &= ms["J4"]
    rep["band_L"] = (float(Lb[breg].max()), float(La[breg].max()), float(np.percentile(La[breg], 95)))
    Ya = luma(after.astype(np.float32))
    gm = geo.full(info["gloss"]) > 0.2
    cap, capR = geo.full(info["Ycap"]), geo.full(info["capR"])
    Yo = luma(before.astype(np.float32))
    ex = Ya[gm] - cap[gm]
    capO = np.maximum(capR, Yo)          # 原白瓷 5px 邻域亮端，与原像素本身（保留的原画高光）取大
    rep["gloss"] = (int(gm.sum()), int((ex > 2).sum()), float(ex.max()), int((Ya[gm] > capO[gm] + 2).sum()),
                    float((Ya[gm] - capO[gm]).max()))
    Ym_ = luma(mem.astype(np.float32))
    rep["gloss_mem"] = (int((Ym_[gm] > capO[gm] + 0.5).sum()), float((Ym_[gm] - capO[gm]).max()))
    rest = ms["J4"] & ~_dilate(gm, 2) & ~(geo.full(info["rim"]) > 0.05)
    Ym = luma(mem.astype(np.float32))
    rep["cap_rest"] = (int(rest.sum()), int((Ym[rest] > cap[rest] + 0.5).sum()), int((Ya[rest] > cap[rest] + 2).sum()),
                       float((Ya[rest] - cap[rest]).max()))
    # 盖面暖斑 Lab（斑 = patch 权重 >0.3；邻区 = 盖面斑上方一条）
    pm = geo.full(info["patch"]) > 0.3
    nb = np.zeros_like(pm)
    nb[824:829, 1316:1336] = True
    nb &= ~pm
    rep["patch"] = []
    for img in (before, after):
        lab = srgb_to_lab(img)
        o = []
        for mm in (pm, nb):
            v = lab[mm]
            o.append((float(np.median(v[:, 0])), float(np.median(np.hypot(v[:, 1], v[:, 2]))),
                      float(np.degrees(np.arctan2(np.median(v[:, 2]), np.median(v[:, 1]))) % 360)))
        rep["patch"].append(o)
    rep["patch_n"] = int(pm.sum())
    return rep


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--src", default=DEFAULT_SRC)
    ap.add_argument("--out", default=DEFAULT_SRC)
    ap.add_argument("--in-place", action="store_true", help="允许输出覆盖输入文件")
    ap.add_argument("--force", action="store_true", help="跳过幂等检查（调试用）")
    args = ap.parse_args(argv)
    if os.path.abspath(args.src) == os.path.abspath(args.out) and not args.in_place:
        print("输出与输入同一路径，需加 --in-place 才写；未写任何文件。")
        return 2
    im = Image.open(args.src)
    if im.size != SIZE or im.format != "JPEG":
        print("输入不是 1672x941 JPEG（%s %s），不是这张底图，跳过。" % (im.format, im.size))
        return 2
    src = np.asarray(im.convert("RGB"))
    geo = Geo()
    b0 = blue_report(src, geo)
    print("输入 %s（%d 字节）：J2–J4 罐身场景口径蓝像素 %.1f%%（任务口径 HSV 190–250° S>0.18 V≥0.10：%.2f%%）"
          % (args.src, os.path.getsize(args.src), 100 * b0["J2-4"][1], 100 * b0["J2-4"][0]))
    if b0["J2-4"][1] < SKIP_BELOW and not args.force:
        cm = src[jar_masks(geo)["J4"]].astype(np.float64).mean(0)
        print("  场景口径蓝像素 < %.0f%%，J4 罐身均色 (%.0f,%.0f,%.0f)：判定已处理过（或罐已非青花），跳过，未写文件。"
              % (100 * SKIP_BELOW, *cm))
        return 0
    win_new, info = render(src, geo)
    new = src.copy()
    new[geo.y0:geo.y1, geo.x0:geo.x1] = win_new
    changed = geo.full((geo.A_all > 0).astype(np.uint8)).astype(bool)
    rects, inside = write_jpeg_mcu(args.src, im, new, changed, args.out)
    after = np.asarray(Image.open(args.out).convert("RGB"))
    b1 = blue_report(after, geo)
    rep = self_check(src, after, geo, inside, args.src, args.out)
    mcu, _ = mcu_size(im)
    print("写出 %s（%d 字节，jpegtran -drop ×%d 块，MCU %dx%d，4:2:0；改动 MCU 共 %d 像素）"
          % (args.out, os.path.getsize(args.out), len(rects), mcu[0], mcu[1], int(inside.sum())))
    for n in ("J1", "J2", "J3", "J4", "J2-4", "全部"):
        print("  蓝像素 %-5s 任务口径 %.2f%% → %.2f%%；场景口径（色相 150–260° S>0.12 V≥0.10）%.2f%% → %.2f%%"
              % (n, 100 * b0[n][0], 100 * b1[n][0], 100 * b0[n][1], 100 * b1[n][1]))
    print("  mask 外（alpha=0）全图平均绝对差 %.5f；改动块内 mask 外平均绝对差 %.3f、最大 %d（4:2:0 色度 2×2 共用 + 块内重量化）"
          % (rep["out_mad"], rep["out_in_rect_mad"], rep["out_in_rect_max"]))
    print("  改动块外变动像素：djpeg -nosmooth（逐块独立解码）%s；PIL 默认解码 %d（最大差 %d，离块边 >1px 的 %d——"
          "fancy upsampling 把块边色度插值进紧贴的一圈）"
          % (rep["rect_out_px_nosmooth"], rep["rect_out_px_pil"], rep["rect_out_max_pil"], rep["rect_out_px_pil_beyond1"]))
    print("  边界 ΔE76：轮廓外 1–3px %.2f，轮廓混色圈 %.2f，内侧 1–2px %.2f；跨轮廓 L* 台阶（内−外）%.1f → %.1f"
          % (*rep["dE"], *rep["step"]))
    for n in ("J1", "J2", "J3", "J4"):
        j = rep["jar"][n]
        print("  %s 罐身均亮 %.1f → %.1f；原白地亮端同批像素 %.1f → %.1f（×%.2f）；97 分位 %.0f → %.0f；比原像素亮的 %.1f%%"
              % (n, *j["luma"], *j["white"], j["white"][1] / j["white"][0], *j["p97"], 100 * j["brighter"]))
        print("      L* 峰值 %.1f → %.1f、L*>65 高光像素 %d → %d；釉色 L*25–50 中位 h %.0f° C* %.1f、均色 G/R %.3f B/R %.3f"
              % (*j["Lmax"], *j["nhl"], j["hue"], j["chroma"], j["gr"], j["br"]))
        tb, ta = j["tex"]
        print("      肌理 %s 均亮/HF3/MF9 前 %.1f/%.1f%%/%.1f%% → 后 %.1f/%.1f%%/%.1f%%"
              % (TEX_RECTS[n], tb[0], 100 * tb[1], 100 * tb[2], ta[0], 100 * ta[1], 100 * ta[2]))
    print("  同画参照肌理：" + "；".join("%s %.1f/%.1f%%/%.1f%%" % (k, v[0], 100 * v[1], 100 * v[2]) for k, v in rep["tex_ref"].items()))
    q = j4_check(src, after, geo, info["J4"], new)
    print("  罐腹高频 std/均值（亮度减 7×7 盒均值，评审口径；框 / 罐腹内收 3px）：")
    for n in ("J1", "J2", "J3", "J4"):
        (fb, bb_, sb_), (fa, ba, sa) = q["rev_" + n]
        print("      %s 框 %.3f → %.3f（HF std %.1f → %.1f）；罐腹 %.3f → %.3f" % (n, fb, fa, sb_, sa, bb_, ba))
    print("      同画参照：" + "；".join("%s %.3f" % kv for kv in q["rev_ref"].items()))
    (qb, qa) = q["quad"]
    print("  J4 框 (1292,850)-(1360,925) 四象限高频 std/均亮：" + "；".join("%s %.3f → %.3f" % (k_, qb[k_], qa[k_]) for k_ in qb))
    (kb, ka), (cb, ca) = q["skew"], q["coh"]
    print("  罐腹高频偏度（r=3 高通，内收 3px）：" + "；".join("%s %.2f → %.2f" % (n, kb[n], ka[n]) for n in kb)
          + "；结构张量方向一致性：" + "；".join("%s %.3f → %.3f" % (n, cb[n], ca[n]) for n in cb))
    (hb_, vb_), (ha_, va_) = q["acf"]
    print("  J4 下腹（y≥887）高频自相关：横向最低（lag1–10）%+.2f → %+.2f，竖向 lag3 %.2f → %.2f；"
          "方向一致性六种设定 %s → %s（最小 %.3f）"
          % (hb_, ha_, vb_, va_, "/".join("%.2f" % c for c in q["coh6"][0]), "/".join("%.2f" % c for c in q["coh6"][1]),
             min(q["coh6"][1])))
    bl = info["J4"].get("belly_glints", [])
    if bl:
        print("  J4 右肩 / 下腹镜面小光点 %d 粒：" % len(bl) + " ".join("(%.0f,%.0f)" % g_[:2] for g_ in bl))
    (hb, vb, eb), (ha, va, ea) = q["streak"]
    print("  J4 横向长拖痕（13px 横 / 竖线响应，超额=√max(H²−V²,0)）：前 %.2f/%.2f 超额 %.2f → 后 %.2f/%.2f 超额 %.2f"
          % (hb, vb, eb, ha, va, ea))
    print("  J4 镜面高光带（x1301–1314 y850–872）L* 峰值 %.1f → %.1f（后 95 分位 %.1f）；光泽层 %d 像素，比逐像素原白瓷亮 >2 的 %d"
          "（最多 +%.1f 灰阶），比原白瓷 5px 邻域亮端（与原像素取大）亮 >2 的 %d（最多 %+.1f）"
          % (*q["band_L"], *q["gloss"]))
    print("      光泽层内存渲染越 5px 邻域亮端 >0.5 的 %d（最多 %+.1f）；落盘多出的是 JPEG 重量化振铃" % q["gloss_mem"])
    print("      光泽层与右轮廓反光以外 %d 像素：内存渲染越逐像素上限 %d；落盘后越 >2 的 %d（最多 +%.1f，JPEG 重量化振铃）"
          % q["cap_rest"])
    (pb, nbb), (pa, nba) = q["patch"]
    print("  J4 盖面暖斑（%d 像素）L*/C*/h 前 %.1f/%.1f/%.0f° → 后 %.1f/%.1f/%.0f°；盖面邻区 前 %.1f/%.1f/%.0f° → 后 %.1f/%.1f/%.0f°"
          % (q["patch_n"], *pb, *pa, *nbb, *nba))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
