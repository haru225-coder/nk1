#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""过场背景修瑕：两张过场图里的青花器改釉（史实纠偏，改釉不改形）。

来由：成熟青花是元至正（1341—1368）以后的器物，最早的纪年青花是 1319 年（黄梅凌氏墓塔盖瓶），
1323 年新安船两万件外销瓷里还没有青花；剧情年代 1255—1290 的福建沿海 / 临安出现青花一律穿帮。
考证与可替换的釉见 docs/史实核对_兴化1277与底图穿帮_2026-09-26.md，做法与数值参照市舶司罐 tools/art/fix_bg_customs_jar.py
（两位评审第二轮通过：场景白点 × 釉本色、亮度 ≤ 原白地、保留镜面高光与釉面起伏）。
本脚本处理两张过场图（表驱动：IMAGES 每张图一条、每只器一条）：
  · assets/cutscene/cs_counting_house.jpg（1672x941，货栈账房，章末了结「账上的距离」第 2 镜）
      - 前景鼓腹青花笔洗 → 龙泉窑粉青：文房器里最体面的一类（南宋晚期白胎厚釉，素面）。
      - 货架上灰白地深色团花盖罐：实测判定为青花，改。暗花 B/R 0.71，比它自己的白地（0.49）冷得多，也比同画
        暖光下所有暗物冷（算盘珠 0.35、货架暗部 0.27、左邻灰罐 0.29）；按白地白平衡后冷度 0.71/0.49≈1.45，
        与同画确定是青花的笔洗（1.07/0.76≈1.41）几乎一样。铁绘（磁州窑 / 吉州窑黑褐花）在这盏金色暖光下只会比
        白地更暖，不会更冷。→ 景德镇青白瓷（影青）盖罐：宋元泉州出口大宗，保留原画「浅色罐」的明度结构。
  · assets/cutscene/cs_quanzhou_fanfang.jpg（1792x1008，泉州番坊街景，结局「泉州蒲氏的船」第 1 镜）
      - 左下高身大罐 → 龙泉窑粉青：新安船龙泉罐 170 余件，街市高档货；它是左下角唯一的浅色器，
        换深釉会把左下角三只罐糊成一团，所以取浅的青瓷。
      - 中下大圆罐 → 泉州磁灶窑绿釉：本地储运 / 外销罐（孟原召：磁灶窑「军持、龙纹大罐、小罐」专供外销）。
      - 中下小罐（压在大罐前）→ 磁灶窑青黄釉：与身后绿釉大罐拉开色相，前后两罐不糊成一片。
    街上其余罐不在本脚本范围（左下两只褐罐、大罐后小绿罐、右下灰绿罐），不动。
  两种粉青用同一本色（与市舶司罐同值），同一种釉不因画而异；各画只换场景白点。

做法（每只器同一流程，参数在表里）：
1. 轮廓：按 8 倍放大图逐像素描的多边形（像素边坐标）8 倍超采样求覆盖率 C；被前景遮挡的部分（笔洗口里的笔、
   压进圈足的细棍、前排罐、麻袋）用排除多边形扣掉；被画框截断的器（左下大罐）轮廓贴画框。
   融合 alpha 往里收 0.5px、羽化 0.6px，轮廓混色圈留原像素，不起光晕、不起硬边。
2. 纹饰判定 D：亮度低于局部白地包络（局部 85 分位）一截，或偏暗且比周围白地偏冷（(B−R)/Y 高出周围白地）。
   只在纹饰带的行里判（口沿、唇下投影照原样）；往外扩 1px 吃掉笔触的抗锯齿边。
3. 受光 S：只用白地像素（去掉镜面点）拟合回转体坐标 (u, t) 的低阶 log 多项式（Huber 重加权），再按 beta 叠回
   白地多尺度补齐后的大尺度残差（σ4）。纹饰占七成的笔洗、盖罐 beta=0.3——白地太稀，补齐的残差会留成花形暗斑；
   街上三罐纹饰稀，beta=0.7，多留原画的受光起伏。笔洗 γ=1.4、盖罐 γ=1.25 的体积对比（原画靠青白对比立体，换成单色釉后要靠明暗）。
4. 釉面起伏（不平铺、不搬运借来的肌理）：白地像素按白地局部均值归一、纹饰像素按纹饰局部均值归一——
   都是原画同一支笔的起伏；纹饰内的起伏先轻糊、再按白地的标准差缩放到同一幅度，交界 1–2px 用多尺度补齐。
   r1a 用「位移搬运 + 小块镜像平铺」时出了网格织纹，本版不用。
   盖罐（r2）：纹饰占七成、原白地只剩一张网，单放大原白地起伏会把网格形状放大出来（高通图有纹饰残影，试过）；
   改为 原白地细起伏（σ1 类内归一，暗侧限 −4%，不成麻点）+ 交界带按邻近起伏幅度补同尺度颗粒 + 与左邻灰罐同向的
   横向稀疏亮笔触（顺纬线弯）+ 一层低频色块，全部固定种子、逐像素独立。
5. 镜面：原图明显高出受光的点（Y/S 过门槛，平滑加权）带原像素色叠回，不乘釉色、不压暗（亮釉的镜面反射与釉色无关）；
   弱的白地笔触并进漫射（直接叠回会在素面釉上成星点、划痕）。笔洗按原画高光落点（窗在画左）补一片窗光柔光和两粒
   窗光镜面点；盖罐（r2）柔光降到 0.04 挪到左上肩，左上肩补一粒主镜面点（带淡釉光圈）+ 一粒小点（光源色取原画奶白亮点
   的色比），原画肩部正中那粒奶白亮点 (300–301, 457) 带原色叠回（keep），两侧轮廓内加环境反光（左窗光、右麻袋金黄）。
6. 着色：场景白点取这只器原白地像素的色比（逐点 σ5 摊开，与平均白点对半混），即「白瓷在这盏光下的样子」，乘釉本色
   （相对 R 的比，归一到同亮度）。漫射亮度 × k（k<1：新釉不比它换掉的白瓷亮；口沿釉薄只压一部分）。
   釉层厚薄场：下腹积釉色深、口沿釉薄色淡（出筋）、一层低频厚薄不匀（固定种子）；受光最亮处色度减淡。
   r2 补充：rim_tint——口沿颈部统一乘一层本色（笔洗 0.5、左下罐 0.5），不再读成没上釉的灰口；
   lit——中下大罐左上夕照受光带亮度回到原白地漫射（k→1）、色度减 0.85×、白点用当地的暖色；
   lumkeep——笔洗圈足足沿（777–778 行）照原画亮度；中下大罐左下暗楔按原画白地包络压回（包络不含阴影里的纹饰笔画）。
7. 写出：改动只落在器物所在的 8×8 块里（两图都是 4:4:4 基线，iMCU=8；1672/1792/1008 是 8 的倍数，941 末行块不满，
   器物不在那里）。所有器物改动块求并集，逐块行取连续段，每段用原图同一套量化表编码后 jpegtran -drop 无损嵌回
   （复用 fix_bg_customs_jar.write_jpeg），每块只编码一次；块外像素与原图逐字节一致。jpegtran 不可用或校验不过就中止、不写文件。

幂等：每只器先量输入的纹饰特征（纹饰带里「比白地暗且偏冷」的像素占比 + 钴蓝占比），都低于表里的门槛就判定已处理、跳过；
整张图的器都已处理就打印原因、rc=0、不写文件——所以日后可以直接对仓库文件运行。另有「锚点」核对（每张图两块器物以外的
32×32 小区均色）：对不上说明不是这张画（重导入换了源图、裁切变了等），rc=2 不写。渲染用固定随机种子，同一输入两次运行
输出逐字节相同。输出与输入同路径时必须加 --in-place 才写。
注意：幂等判的是「还有没有青花」，不认版本——已经是 r1 成品的图再跑本版也判已处理、跳过；要换成本版效果须从 git 原图
（c6be6b4 及以前的青花版）重跑。

会被谁覆盖：tools/art/import_cutscene_bgs.py 的 MANIFEST 登记了这两张图（cs_counting_house ← 仓库内 assets/bg_gpt_1.png；
cs_quanzhou_fanfang ← Codex 素材池 port_pools/quanzhou/005.jpg）。不带 --force 且来源摘要未变时它跳过不重写；带 --force
或来源 / 裁切变了会从来源重新导出，青花就回来了——**重跑导入后须再跑本脚本**。
另外它的 --check / --data-only（docs/过场分镜.md 的契约门禁）按 assets/cutscene/.import_manifest.json 记的 out_sha1 核对产物：
本脚本改图后这两条记录要更新（来源目录在时，不带 --force 跑一次导入会就地把 out_sha1 补成当前文件，不重编码图），否则该门禁报 sha1 不符。
tools/art/build_portraits.py 把 cs_quanzhou_fanfang.jpg 当「蕃坊 / 大食」剪影卡的模糊背景读，只读不写。

镜头（data/cutscenes.json）：账房这一镜 cam 取景 x≈312–1427，笔洗不入画，盖罐只露右缘 ~13px；番坊这一镜 cam_from 露左下大罐上部、
两端都露中下大罐上半，中下小罐在满 letterbox 后被遮（开头 1.2s letterbox 未满时露上沿）。

用法：
  python3 tools/art/fix_cs_qinghua.py --in-place                 # 就地处理两张图（已处理过的跳过）
  python3 tools/art/fix_cs_qinghua.py --only counting_house --src A.jpg --out B.jpg   # 只出候选，不动仓库文件
  python3 tools/art/fix_cs_qinghua.py --out-dir /tmp/cand        # 两张都出候选到目录
自检数字（每只器：钴蓝占比与纹饰特征前后、mask 外平均绝对差、块外变动像素、边界 ΔE、白地同批像素亮度比与色比、肌理 HF3、
评审口径高通 std）每次都打印。
轮次：r0/r0b/r1a 为中断前的草稿（位移搬运去纹饰 + 平铺借肌理，有网格织纹与纹饰残影）；r1 起为本版做法；
r2 按独立评审意见：盖罐补肌理 / 镜面点 / 冷调，笔洗颈部统一本色与足沿，左下罐罐口，中下大罐受光带与暗楔，中下小罐色相。
"""
import argparse
import os
import shutil
import sys
import tempfile

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fix_bg_customs_jar import (blur, blur_xy, box_mean, hsv_blue, local_pct, luma,  # noqa: E402
                                nblur, smoothstep, srgb_to_lab, write_jpeg)

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BLUE_VMIN = 0.10
SEED = 1277

# ---------- 釉 ----------
# albedo：中性光下的本色（相对 R 的比），着色时乘在场景白点上再归一化到同亮度；
# k：漫射亮度相对原白地的倍数（≤1）；chroma_t：积釉色度加深；hi_drop：受光最亮处色度减淡；
# dark_t：积釉压暗；rim_thin：口沿釉薄（出筋）色度减淡。
GLAZES = {
    # 与市舶司罐同值（fix_bg_customs_jar：ALBEDO (1, 1.105, 1.00)、亮度 ≈0.93×原白地）
    "longquan_fenqing": dict(label="龙泉窑粉青", albedo=(1.0, 1.105, 1.00), k=0.93, chroma_t=0.30, hi_drop=0.45,
                             dark_t=0.08, rim_thin=0.55),
    # r2：r1 的 (1, 1.035, 1.04) 在这盏琥珀色暖光下几乎没冷下来（白地同批 B/R 0.435 → 0.449、b* 24.3 → 23.6），
    # 少了青花的对比就读作黄褐。加到 (1, 1.06, 1.17)、受光处色度只减 0.30：同批 B/R ≈0.50、a* ≈3.4、b* ≈20——货架上最白最冷的一只
    "qingbai": dict(label="景德镇青白瓷（影青）", albedo=(1.0, 1.06, 1.17), k=0.95, chroma_t=0.50, hi_drop=0.30,
                    dark_t=0.05, rim_thin=0.70),
    "cizao_green": dict(label="磁灶窑绿釉", albedo=(1.0, 1.14, 0.86), k=0.74, chroma_t=0.40, hi_drop=0.50,
                        dark_t=0.12, rim_thin=0.45),
    # r2：色相再往黄褐推 ~10°（Lab 色相 98° → ~87°），和身后绿釉大罐拉得更开
    "cizao_qinghuang": dict(label="磁灶窑青黄釉", albedo=(1.0, 0.85, 0.565), k=0.88, chroma_t=0.30, hi_drop=0.45,
                            dark_t=0.10, rim_thin=0.45),
}

# ---------- 图与器（像素边坐标：像素 (i,j) 占 [i,i+1]×[j,j+1]） ----------
# 每只器的渲染参数：dq 纹饰暗度门槛 (起, 满)；dcool 偏冷门槛；beta 大尺度残差叠回比例；gamma 体积对比；
# tex_keep / tex_s / td_blur / td_gain / tex_clip / tex_noise(_s) 釉面起伏；strokes 笔触 (幅度, sx, sy, 细颗粒, 稀疏门槛, 纬线弯, 暗笔比例)；
# patches 色块 (幅度, sx, sy, 锐度)；spec_gate 镜面门槛（Y/S）；sheen 柔光 (x, y, σx, σy, 强度)；
# specs 镜面点 (x, y, σx, σy, 强度, 目标亮度[, 光源色比])；refl 环境反光 (u, y 起, y 止, 半宽, 强度, 色比)；
# keep 原画亮点叠回 (x, y, σ, 强度)；rim_tint 口沿本色强度；lit 受光带 (x, y, σx, σy, 强度, 色度减)；
# lumkeep 照原画明暗（见 render）；skip 幂等门槛 (纹饰特征, 钴蓝)。
IMAGES = [
    dict(
        key="counting_house",
        file="assets/cutscene/cs_counting_house.jpg",
        size=(1672, 941),
        anchors=[((560, 700, 592, 732), (62.4, 45.9, 28.3)), ((1000, 560, 1032, 592), (35.8, 24.3, 12.9))],
        tex_ref=("左邻灰罐", (246, 428, 266, 446)),
        vessels=[
            dict(
                name="washer", label="前景鼓腹笔洗", glaze="longquan_fenqing",
                outline=[(104.5, 716.5), (106, 713.5), (109, 712), (113, 711), (120, 710), (130, 709.3), (145, 708.8),
                         (160, 708.3), (170, 707.8), (176, 707.8), (180.5, 708.8), (183.3, 710.5), (184.3, 712.5),
                         (183.8, 715), (182.5, 718), (181, 721), (180.5, 724), (180.5, 728), (181.5, 731), (183, 734),
                         (184.5, 738), (185.6, 743), (185.8, 748), (185.2, 753), (184, 758), (182, 762), (180, 765.5),
                         (177, 769.5), (173.5, 773), (169, 776), (163, 778), (150, 778.6), (130, 778.6), (121, 777.8),
                         (116, 775.5), (112, 772), (108.5, 768), (105.5, 764), (103.3, 760), (102.2, 755), (101.8, 750),
                         (101.9, 745), (102.4, 740), (103.5, 736), (105, 733), (107, 731), (109, 729), (109.8, 726),
                         (109, 723), (107, 720.5), (105.3, 718.5)],
                # 口内（暗）与插在口里的一把笔（在后沿前面）：不动
                exclude=[[(107.5, 716), (111, 714), (117, 713), (120, 711.5), (121, 704), (167, 704), (168, 709.8),
                          (172, 710.3), (177, 710.6), (180.3, 712.2), (180.5, 714.5), (178.5, 717), (170, 719.6),
                          (160, 720.5), (145, 720.8), (130, 720.6), (118, 719.8), (111, 718.3)],
                         # 从右下斜插过来的浅色细棍，左端压在圈足最底下 776–778 行
                         [(148, 775.5), (152.5, 775.5), (157, 776.8), (161.5, 778.2), (163, 779.5), (148, 779.5)]],
                # 逐行实测：722–724 唇口前沿亮线、725–727 唇下暗槽（含一道青花线）、728–731 浅色凸棱、732–737 回纹带、
                # 738 起腹部白地。口沿区到 731：唇口—暗槽—凸棱的明暗照原画（颈肩转折的形体线索），只换釉色
                deco_y=(731.5, 777.0), rim_y=(707.5, 731.0), pool_y=(758.0, 777.0),
                env_r=4, env_q=85, env_s=2.5,
                beta=0.30, gamma=1.4, tex_keep=0.6, td_blur=0.9, td_gain=0.6, spec_gate=(1.35, 1.8),
                # r2：口沿颈部（707.5–731）统一乘一层粉青本色，强度 0.5（r1 只按「釉薄」减到 ~0.2，颈部读成灰蓝、与腹部色相断开）
                rim_tint=0.5,
                # r2：圈足那道浅色足沿（777–778 行，原亮度 45–68）照原画亮度留回（r1 被积釉压暗、k 压到 ~0.86）
                lumkeep=[("rows", 776.2, 778.8, 0.5, 1.0, 1.0)],
                # 窗在画左：原画左肩 (105,735) 有一道窗光亮边；柔光与镜面点落在它内侧的上腹
                sheen=[(117.0, 741.0, 4.0, 6.0, 0.14)],
                specs=[(114.5, 737.5, 1.0, 1.5, 0.85, 150.0), (117.2, 741.8, 0.7, 0.8, 0.40, 150.0)],
            ),
            dict(
                name="pot", label="货架团花盖罐", glaze="qingbai",
                outline=[(280.5, 441.5), (297, 441.2), (313.5, 441.5), (314.5, 445), (313.5, 448.5), (315, 450),
                         (318, 452), (320.5, 455), (322, 459), (322.8, 464), (322.8, 470), (322, 476), (320.5, 481),
                         (318, 485), (315, 487.5), (310, 489), (290, 489.5), (278, 488.5), (273.5, 486), (270.5, 482),
                         (268.5, 477), (267.3, 471), (267.3, 465), (268.5, 460), (271, 456), (274.5, 452.5),
                         (278.5, 450), (280.5, 448.5), (280, 445)],
                exclude=[],
                deco_y=(451.0, 487.0), rim_y=(441.0, 450.0), pool_y=(476.0, 488.0),
                env_r=4, env_q=85, env_s=2.5,
                # r2：r1 罐身是一团极平滑的球面渐变（评审高通 std 1.71，左邻灰罐 6.35、麻袋 4.78）。纹饰占七成，原白地只剩一张网，
                # 放大它的起伏就放大出纹饰网格（试过，高通图有残影）；改为：原白地细起伏（σ1 类内归一、暗侧限 −4%，免得成麻点）
                # + 与左邻灰罐同向的横向亮笔触（稀疏、顺纬线弯）+ 一层低频色块，都用固定种子、不平铺。
                beta=0.30, gamma=1.25, tex_s=1.0, tex_keep=0.95, td_blur=0.5, td_gain=1.0, tex_clip=(-0.04, 0.3),
                tex_noise=0.7, tex_noise_s=(1.0, 0.6),
                strokes=(0.24, 2.0, 0.6, 0.0, 0.7, 3.0, 0.25), patches=(0.06, 2.5, 1.5, 2.5),
                # 柔光 0.12 → 0.04，挪到朝窗的左上肩，不再是居中的一团软光斑
                sheen=[(284.0, 455.0, 5.0, 3.0, 0.04)],
                # 朝窗（画左上）的左上肩：一粒主镜面点（带一圈淡釉光）+ 一粒小点；光源色取原画那粒奶白亮点的色比
                # （181,159,120），是窗外日光，不是室内暖光的白点（用白点色时成一粒金黄点，试过）
                specs=[(280.8, 455.2, 1.1, 0.8, 0.95, 210.0, (181, 159, 120)),
                       (280.8, 455.2, 2.4, 1.8, 0.16, 165.0, (181, 159, 120)),
                       (285.3, 453.8, 0.6, 0.5, 0.75, 185.0, (181, 159, 120))],
                # 亮釉两侧映出环境：左轮廓内一道窗光（暖白），右轮廓内映出麻袋的金黄（麻袋原图均色比 1.39:0.93:0.33）
                refl=[(-0.80, 455, 474, 0.07, 0.40, (1.08, 1.0, 0.80)), (0.83, 458, 484, 0.08, 0.32, (1.39, 0.93, 0.33))],
                # 原画肩部正中那粒奶白亮点 (300–301, 457) 带原色叠回
                keep=[(301.0, 457.5, 0.75, 1.15)],
            ),
        ],
    ),
    dict(
        key="quanzhou_fanfang",
        file="assets/cutscene/cs_quanzhou_fanfang.jpg",
        size=(1792, 1008),
        anchors=[((400, 900, 432, 932), (66.6, 57.4, 53.6)), ((1000, 900, 1032, 932), (47.8, 28.4, 23.6))],
        tex_ref=("右下灰绿罐", (1722, 935, 1768, 975)),
        vessels=[
            dict(
                name="left_big", label="左下高身大罐", glaze="longquan_fenqing",
                outline=[(21, 783.5), (22, 781), (30, 779), (45, 778.3), (60, 778), (75, 778.3), (87, 779.5), (92, 782),
                         (92.5, 786), (91, 790), (89, 793.5), (88, 796.5), (87.5, 799), (92, 801), (100, 803.5),
                         (106, 806.5), (110.5, 810), (114, 815), (116.5, 821), (118.3, 828), (119.3, 835), (119.6, 843),
                         (119.4, 852), (118.8, 861), (117.8, 870), (116.3, 878), (114, 886), (111, 894), (107, 902),
                         # 左缘：罐身按口沿中心（x≈56.5）与右缘对称推算越出画框，815 行以下贴 x=0
                         (102, 910), (95, 918), (70, 926), (40, 928), (15, 927), (0, 926), (0, 815), (3, 809),
                         (9, 805), (14, 801.5), (20, 799.5), (24, 798),
                         (22.5, 796), (21, 792), (20.5, 787)],
                exclude=[
                    # 前排褐罐 A（口沿椭圆 + 罐身）
                    [(47.5, 893), (49, 889.5), (55, 887), (65, 886), (75, 885.8), (85, 886.3), (93, 888), (97, 891),
                     (97.5, 894.5), (96, 898), (94, 901), (100, 904), (106, 908), (111, 913), (115, 920), (117, 930),
                     (117, 1008), (20, 1008), (22, 935), (26, 921), (32, 912), (40, 905), (47, 901), (47.5, 897)],
                    # 右侧褐罐 B
                    [(111, 1008), (111, 900), (113, 885), (118, 876), (125, 866), (135, 861), (200, 861), (200, 1008)],
                ],
                deco_y=(801.0, 926.0), rim_y=(777.5, 800.0), pool_y=(880.0, 926.0),
                env_r=6, env_q=85, env_s=3.0,
                beta=0.70, tex_keep=1.25,
                # r2：罐口按釉薄处的浅青乘本色，强度 0.45（r1 口沿色度 C 0.7–1.4、几乎是灰，读成没上釉的口）
                rim_tint=0.5,
            ),
            dict(
                name="mid_big", label="中下大圆罐", glaze="cizao_green",
                outline=[(730.8, 823.5), (733, 820), (740, 818), (755, 817.3), (770, 817.3), (785, 818), (792, 820),
                         (795, 823.5), (794, 827), (791, 829.5), (795, 831), (801.7, 833), (810, 840), (816, 848),
                         (819, 860), (820, 872), (819, 883), (816.7, 895), (813, 905), (808, 915), (800, 925),
                         (780, 934), (750, 934), (735, 928), (728, 915), (724, 908), (720, 900), (716, 892), (711, 885),
                         (707.5, 875), (705.8, 863), (706.7, 855), (709, 845), (713, 838), (721.7, 833), (729, 830.5),
                         (731.5, 828)],
                exclude=[
                    # 压在前面的小罐
                    [(746.7, 915), (750, 911), (760, 909.3), (775, 909), (790, 909.5), (798, 911.5), (801.7, 915),
                     (801, 919.5), (800, 923.5), (804, 926), (808, 929), (813, 935), (816.7, 945), (818.3, 958),
                     (818.3, 1008), (728, 1008), (728.3, 953), (730, 942), (733, 933), (740, 929), (748, 926),
                     (747.5, 920)],
                ],
                deco_y=(831.0, 934.0), rim_y=(817.0, 831.0), pool_y=(890.0, 934.0),
                env_r=5, env_q=85, env_s=3.0,
                # 左上一大片是夕照直射的受光带（不是镜面点）：留在白地里，让受光与白点都跟着它走
                beta=0.70, h_knee=1.30,
                # r2：左上夕照受光带亮度回到原白地漫射（r1 该片 L* 44.3 → 40.7），色度减 0.45 留住夕照的暖色
                lit=[(721.0, 851.0, 9.0, 12.0, 0.8, 0.85)],
                # r2：左下被麻袋与小罐夹住的暗楔（原 L* 4–8）r1 被补亮到 9–15；照原画明暗压回
                lumkeep=[("dark", (716, 880, 752, 932), 36.0, 24.0, 1.0, 1.0)],
            ),
            dict(
                name="mid_small", label="中下小罐", glaze="cizao_qinghuang",
                outline=[(746.7, 915), (750, 911), (760, 909.3), (775, 909), (790, 909.5), (798, 911.5), (801.7, 915),
                         (801, 919.5), (800, 923.5), (804, 926), (808, 929), (813, 935), (816.7, 945), (818.3, 958),
                         (817.5, 972), (815, 985), (812.5, 997), (810.8, 1008), (734, 1008), (732.5, 992), (730, 978),
                         (728.3, 965), (728.3, 953), (730, 942), (733, 933), (740, 929), (748, 926), (747.5, 920)],
                exclude=[],
                deco_y=(927.0, 1008.0), rim_y=(908.5, 927.0), pool_y=(975.0, 1008.0),
                env_r=5, env_q=85, env_s=3.0,
                beta=0.70,
            ),
        ],
    ),
]

SS = 8          # 覆盖率超采样倍数
MARGIN = 6      # 处理窗外扩（再按 8 对齐）
KNEE = 1.12     # 漫射封顶：受光参考的倍数，超出的算镜面


# ---------- 几何 ----------
def _raster(polys, box, ss=SS):
    x0, y0, x1, y1 = box
    im = Image.new("L", ((x1 - x0) * ss, (y1 - y0) * ss), 0)
    d = ImageDraw.Draw(im)
    for p in polys:
        d.polygon([((x - x0) * ss - 0.5, (y - y0) * ss - 0.5) for x, y in p], fill=255)
    return np.asarray(im) > 127


def _erode_edge(m, k):
    """二值腐蚀 k 次（4 邻域，边缘复制——器物被画框截断时不从画框那一侧往里收）。"""
    r = m.copy()
    for _ in range(k):
        p = np.pad(r, 1, mode="edge")
        r = p[1:-1, 1:-1] & p[:-2, 1:-1] & p[2:, 1:-1] & p[1:-1, :-2] & p[1:-1, 2:]
    return r


def _dilate(m, k=1):
    """灰度 / 二值膨胀 k 次（4 邻域取最大，边缘复制）。"""
    r = m.copy()
    for _ in range(k):
        p = np.pad(r, 1, mode="edge")
        r = np.maximum.reduce([p[1:-1, 1:-1], p[:-2, 1:-1], p[2:, 1:-1], p[1:-1, :-2], p[1:-1, 2:]])
    return r


def _down(a, ss=SS):
    h, w = a.shape[0] // ss, a.shape[1] // ss
    return a.reshape(h, ss, w, ss).mean(axis=(1, 3)).astype(np.float32)


class Vessel:
    def __init__(self, cfg, size):
        self.cfg = cfg
        W, H = size
        xs = [x for x, _ in cfg["outline"]]
        ys = [y for _, y in cfg["outline"]]
        x0 = max(0, (int(np.floor(min(xs))) - MARGIN) // 8 * 8)
        y0 = max(0, (int(np.floor(min(ys))) - MARGIN) // 8 * 8)
        x1 = min(W, -(-(int(np.ceil(max(xs))) + MARGIN) // 8) * 8)
        y1 = min(H, -(-(int(np.ceil(max(ys))) + MARGIN) // 8) * 8)
        self.box = (x0, y0, x1, y1)
        self.h, self.w = y1 - y0, x1 - x0
        whole = _raster([cfg["outline"]], self.box)
        inside = whole.copy()
        if cfg["exclude"]:
            inside &= ~_raster(cfg["exclude"], self.box)
        self.C = _down(inside)
        inner = _down(_erode_edge(inside, SS // 2))            # 往里收 0.5px
        self.A = np.clip(blur(inner, 0.6), 0, 1) * (self.C > 0)
        self.A[self.A < 1.0 / 512] = 0.0
        self.M = self.C > 0.95
        yc = np.arange(self.h, dtype=np.float32) + 0.5 + y0
        xc = np.arange(self.w, dtype=np.float32) + 0.5 + x0
        self.Y, self.X = np.meshgrid(yc, xc, indexing="ij")
        # 回转体坐标：逐行左右边（整条轮廓、不扣遮挡）→ 经向 u∈[-1,1]；纵向 t∈[-1,1]（口沿顶 → 底）
        Cw = _down(whole)
        rows = np.nonzero((Cw > 0.5).any(1))[0]
        L = np.array([np.nonzero(Cw[j] > 0.5)[0].min() for j in rows], np.float32)
        R = np.array([np.nonzero(Cw[j] > 0.5)[0].max() + 1 for j in rows], np.float32)
        allr = np.arange(self.h)
        L = np.interp(allr, rows, L) + x0
        R = np.interp(allr, rows, R) + x0
        self.u = np.clip((self.X - ((L + R) / 2)[:, None]) / np.maximum((R - L) / 2, 1.0)[:, None], -1, 1)
        top, bot = min(ys), max(ys)
        self.t = np.clip((self.Y - top) / (bot - top) * 2 - 1, -1, 1)

    def win(self, img):
        x0, y0, x1, y1 = self.box
        return img[y0:y1, x0:x1]

    def zone(self, key, ramp=1.5):
        a, b = self.cfg[key]
        ramp = max(ramp, 1e-3)
        return smoothstep(a - ramp, a + ramp, self.Y) * (1 - smoothstep(b - ramp, b + ramp, self.Y))


def change_boxes(alpha_full):
    """全部改动像素（alpha>0）所在的 8×8 块，逐块行取连续段 → [(x0, y0, x1, y1)]，每块只出现一次。"""
    H, W = alpha_full.shape
    bh, bw = -(-H // 8), -(-W // 8)
    pad = np.zeros((bh * 8, bw * 8), bool)
    pad[:H, :W] = alpha_full > 0
    blk = pad.reshape(bh, 8, bw, 8).any(axis=(1, 3))
    out = []
    for by in range(bh):
        row = blk[by]
        bx = 0
        while bx < bw:
            if row[bx]:
                e = bx
                while e + 1 < bw and row[e + 1]:
                    e += 1
                out.append((bx * 8, by * 8, min(W, (e + 1) * 8), min(H, by * 8 + 8)))
                bx = e + 1
            else:
                bx += 1
    return out, int(blk.sum())


# ---------- 量测 ----------
def fill(val, wgt, scales=(1.0, 2.0, 4.0, 8.0, 16.0), lo=0.02, hi=0.25):
    """多尺度归一化卷积补洞：粗尺度打底，细尺度在权重够的地方逐级覆盖。val 为 2D 或 HxWxC。"""
    ww = wgt.astype(np.float32)
    chan = val.ndim == 3
    wv = ww[..., None] if chan else ww
    out = None
    for s in sorted(scales, reverse=True):
        den = blur(ww, s)
        dd = den[..., None] if chan else den
        est = blur(val * wv, s) / np.maximum(dd, 1e-6)
        if out is None:
            gm = (val * wv).sum(axis=(0, 1)) / max(float(ww.sum()), 1e-6)
            c0 = smoothstep(0.0, 1e-3, dd)
            out = est * c0 + gm * (1 - c0)
            continue
        c = smoothstep(lo, hi, dd)
        out = c * est + (1 - c) * out
    return out


def envelope(Y, v):
    """局部白地包络：mask 内局部高分位（白地才反映受光，青花是暗的），再 mask 内归一化模糊。"""
    m = v.M
    E = local_pct(Y, m, v.cfg["env_r"], v.cfg["env_q"])
    return np.maximum(nblur(E, m.astype(np.float32), v.cfg["env_s"]), 1.0)


def deco_map(w, Y, v):
    """纹饰 D∈[0,1]：比局部白地暗一截，或偏暗且比周围白地偏冷（白平衡后发蓝）。返回 (D, E0, q, cool)。"""
    cfg = v.cfg
    M = v.M
    body = v.zone("deco_y")
    E0 = envelope(Y, v)
    q = Y / E0
    br = blur(w[..., 2] - w[..., 0], 0.8) / np.maximum(blur(Y, 0.8), 6.0)
    g0 = M & (body > 0.5) & (q > 0.88)
    cool = br - fill(br, g0, (2.0, 4.0, 8.0))
    qh, ql = cfg.get("dq", (0.82, 0.62))
    c0, c1 = cfg.get("dcool", (0.10, 0.22))
    D = np.maximum(smoothstep(qh, ql, q), smoothstep(c0, c1, cool) * smoothstep(0.97, 0.82, q))
    return D * body * M, E0, q, cool


def signature(img, v):
    """幂等特征 (纹饰特征, 钴蓝占比)：纹饰带（内缩 1px）里「比白地暗 ≥25% 且偏冷 ≥0.10」的像素占比；
    钴蓝占比 HSV 190–250°、S>0.18、V≥0.10（mask 内）。"""
    w = v.win(img).astype(np.float32)
    Y = luma(w)
    D, E0, q, cool = deco_map(w, Y, v)
    dz = (v.zone("deco_y", 0.0) > 0.5) & _erode_edge(v.M, 1)
    feat = float(((q < 0.75) & (cool > 0.10))[dz].mean())
    blue = float(hsv_blue(v.win(img), BLUE_VMIN)[v.M].mean())
    return feat, blue


def smooth_model(Y, G, v):
    """白地受光：log 亮度对回转体坐标 (u, t) 的 3×2 阶多项式（只拟合白地像素，Huber 重加权），
    再按 beta 叠回白地多尺度补齐后的大尺度残差（σ4）。"""
    M = v.M
    terms = [v.u ** i * v.t ** j for i in range(4) for j in range(3)]
    B = np.stack(terms, -1).astype(np.float64)
    y = np.log(np.maximum(Y, 1.0)).astype(np.float64)
    Bm, ym = B[G], y[G]
    wt = np.ones(len(ym))
    c = np.zeros(B.shape[-1])
    for _ in range(8):
        sw = np.sqrt(wt)
        c, *_ = np.linalg.lstsq(Bm * sw[:, None], ym * sw, rcond=None)
        wt = 1.0 / np.maximum(np.abs(ym - Bm @ c) / 0.08, 1.0)
    lo, hi = np.percentile(Y[G], [2, 99])
    Pm = np.clip(np.exp(B @ c), lo, hi).astype(np.float32)
    R = nblur(np.log(np.maximum(fill(Y, G), 1.0)) - np.log(Pm), M.astype(np.float32), 4.0)
    return nblur(Pm * np.exp(v.cfg.get("beta", 0.6) * R), M.astype(np.float32), 1.0)


# ---------- 渲染 ----------
def render(src, v, seed):
    cfg = v.cfg
    gz = GLAZES[cfg["glaze"]]
    w = v.win(src).astype(np.float32)
    Y = luma(w)
    M = v.M
    Mf = M.astype(np.float32)
    body = v.zone("deco_y")
    rimz = v.zone("rim_y", 1.0)
    rng = np.random.default_rng(seed)
    # 1) 纹饰：往外扩 1px 吃掉笔触的抗锯齿边；白地 = 纹饰带里远离纹饰的像素
    D0, E0, q, _ = deco_map(w, Y, v)
    D = np.clip(np.maximum(D0, 0.6 * _dilate(D0, 1)), 0, 1)
    Dh = D > 0.6
    G = M & (body > 0.5) & (D < 0.08)
    # 2) 受光：白地先补齐一遍找镜面点，去掉镜面点后拟合光滑受光（门槛 h_knee：大片受光带不算镜面，留在漫射里）
    S1 = nblur(fill(Y, G), Mf, 1.5)
    G = G & ~_dilate(G & (Y > cfg.get("h_knee", KNEE) * S1), 1)
    S = smooth_model(Y, G, v)
    gam = cfg.get("gamma", 1.0)
    if gam != 1.0:
        m0 = float(np.exp(np.log(np.maximum(S[G], 1.0)).mean()))
        S = m0 * np.power(np.maximum(S, 1.0) / m0, gam)
    # 3) 釉面起伏：白地按白地局部均值归一、纹饰按纹饰局部均值归一（同一支笔），纹饰内起伏缩到白地同幅度
    Eg = nblur(Y, G.astype(np.float32), cfg.get("tex_s", 1.5))
    Ed = nblur(Y, Dh.astype(np.float32), cfg.get("tex_s", 1.5))
    tg = np.clip(Y / np.maximum(Eg, 1.0) - 1, -0.25, 0.25)
    tdb = cfg.get("td_blur", 0.5)
    tdb = tdb if isinstance(tdb, (tuple, list)) else (tdb, tdb)
    td = blur_xy(np.clip(Y / np.maximum(Ed, 1.0) - 1, -0.6, 0.6), *tdb)
    core = Dh & (D > 0.9)
    sg = float(tg[G].std()) if G.sum() > 20 else 0.05
    sd = float(td[core].std()) if core.sum() > 20 else sg
    gain = float(np.clip(sg / max(sd, 1e-3), 0.25, 1.2)) * cfg.get("td_gain", 1.0)
    valid = G | core
    tex = np.where(G, tg, 0.0) + np.where(core & ~G, td * gain, 0.0)
    band = fill(tex, valid, (0.8, 1.6, 3.2), lo=0.05, hi=0.35)
    tn = cfg.get("tex_noise", 0.0)
    if tn > 0:
        # 白地与纹饰的交界带（两类都不算的 1–3px）：补齐只给出平滑值，纹饰占七成的罐上会留成一圈圈「没笔触的沟」
        # （高通图里的纹饰残影）。按邻近有效像素的起伏幅度补一层同尺度的颗粒（独立固定种子，不平铺、不搬运）。
        rng_t = np.random.default_rng(seed + 7919)
        nsx, nsy = cfg.get("tex_noise_s", (0.7, 0.7))
        nz = blur_xy(rng_t.normal(0, 1, Y.shape).astype(np.float32), nsx, nsy)
        nz /= nz.std() + 1e-6
        amp = np.sqrt(nblur(tex ** 2, valid.astype(np.float32), 3.0))
        band = band + tn * amp * nz
    tex = np.where(valid, tex, band)
    tc = cfg.get("tex_clip", 0.2)
    tc = tc if isinstance(tc, (tuple, list)) else (-tc, tc)
    tex = np.clip(tex, *tc)
    # 4) 口沿颈部照原样（无纹饰），纹饰带用新受光 × 起伏；镜面：明显高出受光的原图高光点带原色叠回
    #    受光参考：纹饰带用 S，口沿用口沿局部均值（唇口的亮点才算得出是高光）
    tex = cfg.get("tex_keep", 1.0) * tex
    st = cfg.get("strokes")
    if st:
        # 笔触（strokes）：纹饰占七成的器上，原白地的起伏只剩一张网，放大它就把纹饰的网格形状放大出来（残影）。
        # 改为整只器铺一层与同画笔法同向的横向短笔触（经向拉长 sx、纬向 sy，固定种子、逐像素独立，不平铺、不搬运），
        # 再加一层细颗粒；原白地自己的起伏（上面的 tex）照 r1 的幅度留在底下。
        amp, ssx, ssy, famp = st[:4]
        thr = st[4] if len(st) > 4 else 0.0
        bend = st[5] if len(st) > 5 else 0.0
        neg = st[6] if len(st) > 6 else 1.0
        rng_s = np.random.default_rng(seed + 104729)
        n1 = blur_xy(rng_s.normal(0, 1, Y.shape).astype(np.float32), ssx, ssy)
        n2 = blur(rng_s.normal(0, 1, Y.shape).astype(np.float32), 0.6)
        n1 /= float(n1.std()) + 1e-6
        if thr > 0:                          # 稀疏：只留一笔一笔的，笔与笔之间是底色；neg<1 时暗笔减弱（亮釉上的笔触多是亮的反光）
            n1 = np.maximum(n1 - thr, 0.0) - neg * np.maximum(-n1 - thr, 0.0)
        if bend:                             # 顺纬线弯：俯视下纬线是两端上翘的弧 y = y0 − bend·u²
            hh = Y.shape[0]
            yy = np.clip(np.arange(hh, dtype=np.float32)[:, None] + bend * v.u ** 2, 0, hh - 1.001)
            y0i = np.floor(yy).astype(int)
            fy = yy - y0i
            xi = np.broadcast_to(np.arange(Y.shape[1]), Y.shape)
            n1 = n1[y0i, xi] * (1 - fy) + n1[y0i + 1, xi] * fy
        n1 = (n1 - float(n1[M].mean())) / (float(n1[M].std()) + 1e-6)
        n2 /= float(n2[M].std()) + 1e-6
        tex = tex + amp * (n1 + famp * n2) / np.sqrt(1 + famp ** 2)
    pt = cfg.get("patches")
    if pt:
        # 色块（patches）：画里亮面不是一整片平滑渐变，而是一块块边缘利落的笔触面。低频噪声（sx, sy）经 tanh 软量化成
        # 平台 + 窄过渡，幅度 amp（相对亮度）；固定种子，不平铺。
        pamp, psx, psy, sharp = pt
        rng_p = np.random.default_rng(seed + 15485863)
        n3 = blur_xy(rng_p.normal(0, 1, Y.shape).astype(np.float32), psx, psy)
        n3 /= float(n3[M].std()) + 1e-6
        n3 = np.tanh(sharp * n3)
        n3 = (n3 - float(n3[M].mean())) / (float(n3[M].std()) + 1e-6)
        tex = tex + pamp * n3
    Lfull = Y * (1 - body) + S * (1 + tex) * body
    Er = nblur(Y, (M & (rimz > 0.5)).astype(np.float32), 2.0)
    ref = S * body + Er * (1 - body)
    over = np.clip(Lfull - ref * KNEE, 0, None) * Mf
    sp0, sp1 = cfg.get("spec_gate", (1.18, 1.45))
    hl = smoothstep(sp0, sp1, Y / np.maximum(ref, 1.0)) * Mf
    spec = np.where(body > 0.5, np.clip(Y - S * KNEE, 0, None) * hl, over) * Mf
    diff = Lfull - over
    # 5) 釉层厚薄：下腹积釉、口沿釉薄、低频不匀（固定种子）
    n = blur_xy(rng.normal(0, 1, Y.shape).astype(np.float32), 2.5, 4.0)
    n /= n.std() + 1e-6
    T = 1.0 * v.zone("pool_y", 3.0) - 0.8 * rimz + 0.35 * n * (1 - rimz)
    # 亮釉的镜面反射与釉色无关：高光处 k 回到 1；口沿釉薄只压一部分
    kk = gz["k"] + (1 - gz["k"]) * np.maximum(hl, 0.35 * rimz)
    Vd = diff * kk * (1 - gz["dark_t"] * T)
    # 柔光（窗光在釉面上的宽反射，光源色）按受光强度加
    sheen = np.zeros_like(Y)
    for cx, cy, sx, sy, amt in cfg.get("sheen", []):
        sheen += amt * np.exp(-0.5 * (((v.X - cx) / sx) ** 2 + ((v.Y - cy) / sy) ** 2)) * S * Mf
    # 亮度标定：白地同批像素上（漫射 + 柔光）的均亮不超过 k × 原白地——新釉不比它换掉的白瓷亮
    r_g = float((Vd + sheen)[G].mean() / max(float(Y[G].mean()), 1e-3))
    if r_g > gz["k"]:
        Vd *= gz["k"] / r_g
        sheen *= gz["k"] / r_g
    # 受光带（lit）：夕照直射的一大片主光——亮度回到原白地漫射（k→1、积釉压暗减半），色度减淡一截留住光源的暖色。
    # 在亮度标定之后做：标定管的是整只器的釉色明度，受光带是光，不是釉。
    Wl = np.zeros_like(Y)
    Cl = np.zeros_like(Y)
    for cx, cy, sx, sy, amt, cdrop in cfg.get("lit", []):
        wl = np.clip(amt * np.exp(-0.5 * (((v.X - cx) / sx) ** 2 + ((v.Y - cy) / sy) ** 2)), 0, 1) * Mf
        Wl = np.maximum(Wl, wl)
        Cl = np.maximum(Cl, cdrop * wl)
    if Wl.any():
        Vd = Vd * (1 - Wl) + Wl * diff * (1 - 0.5 * gz["dark_t"] * T)
    # 照原画明暗（lumkeep）：被遮挡的暗楔、圈足足沿这类「形体光影」按原图亮度来（只换釉色）。
    #   ("rows", y0, y1, ramp, 强度, 亮度倍数)：整行带直接用原图亮度（足沿无纹饰）；
    #   ("dark", (x0, y0, x1, y1), 亮, 暗, 强度, 亮度倍数)：框内按原图白地包络 E0（局部 85 分位，纹饰笔画是暗的、不进包络）
    #   从「亮」到「暗」渐入，把新受光按比例压到 E0——暗楔回到原画的暗，但不把阴影里的纹饰笔画带回来（直接用原图亮度试过，有叶纹残影）。
    Wk = np.zeros_like(Y)
    Yk = np.zeros_like(Y)
    for e in cfg.get("lumkeep", []):
        if e[0] == "rows":
            _, a0, a1, rp, amt, kf = e
            wk = amt * smoothstep(a0 - rp, a0 + rp, v.Y) * (1 - smoothstep(a1 - rp, a1 + rp, v.Y))
            tgt = Y * kf
        else:
            _, (bx0, by0, bx1, by1), lhi, llo, amt, kf = e
            reg = (smoothstep(bx0 - 2, bx0 + 2, v.X) * (1 - smoothstep(bx1 - 2, bx1 + 2, v.X))
                   * smoothstep(by0 - 2, by0 + 2, v.Y) * (1 - smoothstep(by1 - 2, by1 + 2, v.Y)))
            Eb = nblur(E0, Mf, 1.5)
            wk = amt * reg * smoothstep(lhi, llo, Eb)
            tgt = Vd * np.minimum(1.0, Eb * kf / np.maximum(S, 1.0))
        wk = np.clip(wk, 0, 1) * Mf
        Yk = np.where(wk > Wk, tgt, Yk)
        Wk = np.maximum(Wk, wk)
    if Wk.any():
        Vd = Vd * (1 - Wk) + Wk * Yk
        spec = spec * (1 - Wk)              # 原图亮度里已含高光，不重复叠
    # 6) 着色：场景白点（白地色比，逐点 σ5 摊开，与平均白点对半混）× 釉本色
    rat = w / np.maximum(Y, 4.0)[..., None]
    gw = G | (M & (rimz > 0.5) & (q > 0.85) & (q < 1.1))
    wm = rat[G].mean(0)
    wm = wm / luma(wm)
    wloc = nblur(fill(rat, gw, (2.0, 4.0, 8.0, 16.0)), Mf, 5.0)
    white = 0.5 * wloc + 0.5 * wm
    if Wl.any():                            # 受光带里白点取当地的（夕照的暖色），不与整只器的平均白点对半混
        white = white * (1 - Wl[..., None]) + wloc * Wl[..., None]
    white = white / np.maximum(luma(white), 1e-3)[..., None]
    glaze = white * np.array(gz["albedo"], np.float32)
    glaze = glaze / np.maximum(luma(glaze), 1e-3)[..., None]
    lo, hi = np.percentile(Vd[M], [5, 97])
    s = np.clip((Vd - lo) / max(hi - lo, 1e-3), 0, 1)
    f = 1 + gz["chroma_t"] * np.clip(T, -1, 1.5) - gz["hi_drop"] * smoothstep(0.7, 1.0, s)
    if "rim_tint" in cfg:
        # 口沿颈部统一乘一层薄釉的本色（强度 rim_tint），和腹部同一个色相，不再读成没上釉的灰口
        f = f * (1 - rimz) + cfg["rim_tint"] * rimz
    else:
        f = f - gz["rim_thin"] * rimz
    f = f * (1 - Cl)
    f = np.clip(f, 0.15, 1.8)[..., None]
    ratio = white + f * (glaze - white)
    ratio = ratio / np.maximum(luma(ratio), 1e-3)[..., None]
    Dm = D[..., None]
    col = Vd[..., None] * ratio + spec[..., None] * (rat * (1 - Dm) + white * Dm)   # 纹饰上的高光点取白点色
    col = col + sheen[..., None] * white
    # 环境反光（refl）：亮釉两侧轮廓内映出周围的暖色货物（经向 u 处一条竖带），色为本画周围物的色比，按受光强度加
    for uc, ya, yb, hw, amt, rgb in cfg.get("refl", []):
        wv = (amt * np.exp(-0.5 * ((v.u - uc) / hw) ** 2) * smoothstep(ya - 2, ya + 2, v.Y)
              * (1 - smoothstep(yb - 2, yb + 2, v.Y)) * Mf)
        col = col + (wv * S)[..., None] * np.array(rgb, np.float32)
    # 7) 镜面点：窗光的小块亮反射，向「光源色 × 目标亮度」混
    for sp in cfg.get("specs", []):
        cx, cy, sx, sy, amt, lum = sp[:6]
        a = (amt * np.exp(-0.5 * (((v.X - cx) / sx) ** 2 + ((v.Y - cy) / sy) ** 2)) * Mf)[..., None]
        if len(sp) > 6:                     # 指定光源色（色比，按亮度归一）：窗外日光比室内暖光白
            c3 = np.array(sp[6], np.float32)
            src_c = lum * c3 / float(luma(c3))
        else:
            src_c = lum * white
        col = col * (1 - a) + src_c * a
    # 8) 原画亮点带原色叠回（keep）：落在纹饰旁、被柔光吞掉的那种奶白小亮点
    for cx, cy, sg, amt in cfg.get("keep", []):
        a = np.clip(amt * np.exp(-0.5 * (((v.X - cx) ** 2 + (v.Y - cy) ** 2) / sg ** 2)), 0, 1)[..., None] * Mf[..., None]
        col = col * (1 - a) + w * a
    A = v.A[..., None]
    out = w * (1 - A) + col * A
    return np.clip(out + 0.5, 0, 255).astype(np.uint8), dict(D=D, G=G, S=S, gain=gain)


# ---------- 自检 ----------
def _ring(m, k):
    r = m.copy()
    for _ in range(k):
        p = np.pad(r, 1, mode="constant")
        r = p[1:-1, 1:-1] | p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:]
    return r


def texture_stat(Y, m):
    """评审口径的肌理：亮度减 3×3 / 9×9 盒均值后的标准差 ÷ 区内均亮（与市舶司罐同口径）。"""
    Y = Y.astype(np.float64)
    mu = Y[m].mean()
    return float(mu), float((Y - box_mean(Y, 1))[m].std() / mu), float((Y - box_mean(Y, 4))[m].std() / mu)


def check_vessel(before, after, v, info, union):
    wb, wa = v.win(before), v.win(after)
    rep = {"sig_b": signature(before, v), "sig_a": signature(after, v)}
    ad = np.abs(wa.astype(np.int16) - wb.astype(np.int16))
    out = v.win(union) == 0          # 本器与同图其他器的 alpha 都为 0
    rep["out_mad"] = float(ad[out].mean())
    rep["out_changed"] = int((ad.max(-1)[out] > 0).sum())
    labb, laba = srgb_to_lab(wb), srgb_to_lab(wa)
    dE = np.sqrt(((laba - labb) ** 2).sum(-1))
    c0 = v.C > 0
    ring_out = _ring(c0, 3) & ~c0
    ring_edge = (v.C > 0) & (v.C < 1)
    full = v.C >= 1
    ring_in = full & ~_erode_edge(full, 2)
    rep["dE"] = (float(dE[ring_out].mean()), float(dE[ring_edge].mean()), float(dE[ring_in].mean()))
    rep["step"] = (float(labb[..., 0][ring_in].mean() - labb[..., 0][ring_out].mean()),
                   float(laba[..., 0][ring_in].mean() - laba[..., 0][ring_out].mean()))
    M = v.M
    rep["mean_b"], rep["mean_a"] = wb[M].mean(0), wa[M].mean(0)
    Yb, Ya = luma(wb.astype(np.float32)), luma(wa.astype(np.float32))
    rep["luma"] = (float(Yb[M].mean()), float(Ya[M].mean()))
    # 白地同批像素（渲染用的白地 G）：改前改后亮度比与色比——新釉不应比它换掉的白瓷亮
    g = info["G"]
    gb, ga = wb[g].astype(np.float64).mean(0), wa[g].astype(np.float64).mean(0)
    rep["wg"] = dict(n=int(g.sum()), lb=float(luma(gb)), la=float(luma(ga)), gr_b=gb[1] / gb[0], br_b=gb[2] / gb[0],
                     gr_a=ga[1] / ga[0], br_a=ga[2] / ga[0])
    rep["p99"] = (float(np.percentile(Yb[M], 99)), float(np.percentile(Ya[M], 99)))
    rep["Lmax"] = (float(labb[..., 0][M].max()), float(laba[..., 0][M].max()))
    core = _erode_edge(M, 2) & (v.zone("deco_y", 0.0) > 0.5)
    rep["tex"] = (texture_stat(Yb, core), texture_stat(Ya, core))
    # 评审 r1 口径的高通：L* − σ1.5 模糊 的标准差，取窗内改动像素（|Δ|>3）方形内缩 3px
    m = ad.max(-1) > 3
    for _ in range(3):
        p = np.pad(m, 1)
        m = (p[1:-1, 1:-1] & p[:-2, 1:-1] & p[2:, 1:-1] & p[1:-1, :-2] & p[1:-1, 2:]
             & p[:-2, :-2] & p[2:, 2:] & p[:-2, 2:] & p[2:, :-2])
    Lb_, La_ = labb[..., 0].astype(np.float32), laba[..., 0].astype(np.float32)
    rep["hp"] = (float((Lb_ - blur(Lb_, 1.5))[m].std()) if m.any() else 0.0,
                 float((La_ - blur(La_, 1.5))[m].std()) if m.any() else 0.0, int(m.sum()))
    return rep


def anchors_ok(img, spec):
    bad = []
    for (x0, y0, x1, y1), want in spec["anchors"]:
        m = img[y0:y1, x0:x1].reshape(-1, 3).astype(np.float64).mean(0)
        if want is not None and np.abs(m - np.array(want)).max() > 3.0:
            bad.append("锚点 (%d,%d) 均色 (%.1f,%.1f,%.1f) ≠ 记录 %s" % (x0, y0, *m, want))
    return bad


# ---------- 主流程 ----------
def process(spec, src_path, out_path, force=False):
    im = Image.open(src_path)
    if im.format != "JPEG" or im.size != tuple(spec["size"]):
        print("  %s：不是 %dx%d JPEG（%s %s），不是这张图，跳过，未写文件。" % (src_path, *spec["size"], im.format, im.size))
        return 2
    src = np.asarray(im.convert("RGB"))
    bad = anchors_ok(src, spec)
    if bad and not force:
        print("  " + "；".join(bad) + "——不是预期的那张画（重导入换了源图 / 裁切？），未写文件。")
        return 2
    vessels = [Vessel(c, spec["size"]) for c in spec["vessels"]]
    todo = []
    for v in vessels:
        feat, blue = signature(src, v)
        th_f, th_b = v.cfg.get("skip", (0.02, 0.003))
        done = feat < th_f and blue < th_b
        print("  %-10s %s：纹饰特征 %.2f%%、钴蓝 %.2f%%（门槛 <%.1f%% 且 <%.1f%%）→ %s"
              % (v.cfg["name"], v.cfg["label"], 100 * feat, 100 * blue, 100 * th_f, 100 * th_b,
                 "已处理，跳过" if done and not force else "处理"))
        if not done or force:
            todo.append(v)
    if not todo:
        print("  全部器物判定已处理过（纹饰特征与钴蓝占比都在门槛下），跳过，未写文件。")
        return 0
    new = src.copy()
    infos = {}
    union = np.zeros(src.shape[:2], np.float32)
    for i, v in enumerate(todo):
        x0, y0, x1, y1 = v.box
        win_new, info = render(src, v, SEED + i)
        cur = new[y0:y1, x0:x1]
        cur[v.A > 0] = win_new[v.A > 0]          # 只写 A>0 的像素：与别的器的处理窗重叠时互不覆盖
        u = union[y0:y1, x0:x1]
        u[:] = np.maximum(u, v.A)
        infos[v.cfg["name"]] = info
    boxes, nblk = change_boxes(union)
    with tempfile.TemporaryDirectory() as td:
        cur_path, cur_img = src_path, im
        for i, b in enumerate(boxes):
            nxt = os.path.join(td, "step%03d.jpg" % i)
            how = write_jpeg(cur_path, cur_img, new, b, nxt)
            if not how.startswith("jpegtran"):
                print("  jpegtran -drop 未通过（块段 %s），中止，未写文件。" % (b,))
                return 1
            cur_path, cur_img = nxt, Image.open(nxt)
        after = np.asarray(Image.open(cur_path).convert("RGB"))
        inblk = np.zeros(src.shape[:2], bool)
        for x0, y0, x1, y1 in boxes:
            inblk[y0:y1, x0:x1] = True
        outside_changed = int((np.abs(after.astype(np.int16) - src.astype(np.int16)).max(-1)[~inblk] > 0).sum())
        if outside_changed:
            print("  改动块外有 %d 个像素变了，中止，未写文件。" % outside_changed)
            return 1
        os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
        shutil.copyfile(cur_path, out_path)
    print("  写出 %s（%d 字节；jpegtran -drop %d 段、共 %d 块，每块一次；改动块外变动像素 %d）"
          % (out_path, os.path.getsize(out_path), len(boxes), nblk, outside_changed))
    rname, (rx0, ry0, rx1, ry1) = spec["tex_ref"]
    ref_t = texture_stat(luma(src[ry0:ry1, rx0:rx1].astype(np.float32)), np.ones((ry1 - ry0, rx1 - rx0), bool))
    for v in todo:
        r = check_vessel(src, after, v, infos[v.cfg["name"]], union)
        w = r["wg"]
        tb, ta = r["tex"]
        print("  [%s → %s]" % (v.cfg["label"], GLAZES[v.cfg["glaze"]]["label"]))
        print("    钴蓝占比（HSV 190–250°、S>0.18、V≥0.10）%.2f%% → %.2f%%；纹饰特征 %.2f%% → %.2f%%"
              % (100 * r["sig_b"][1], 100 * r["sig_a"][1], 100 * r["sig_b"][0], 100 * r["sig_a"][0]))
        print("    mask 外（alpha=0）平均绝对差 %.4f、变动像素 %d（同块重编码）；边界 ΔE76 外 1–3px %.2f / 混色圈 %.2f / 内 1–2px %.2f；"
              "跨轮廓 L* 台阶 %.1f → %.1f" % (r["out_mad"], r["out_changed"], *r["dE"], *r["step"]))
        print("    器身均色 (%.0f,%.0f,%.0f) → (%.0f,%.0f,%.0f)；亮度 %.1f → %.1f；亮度 p99 %.0f → %.0f；L* 峰值 %.1f → %.1f"
              % (*r["mean_b"], *r["mean_a"], *r["luma"], *r["p99"], *r["Lmax"]))
        print("    白地同批像素 n=%d：亮度 %.1f → %.1f（×%.3f）；G/R %.3f → %.3f、B/R %.3f → %.3f"
              % (w["n"], w["lb"], w["la"], w["la"] / max(w["lb"], 1e-6), w["gr_b"], w["gr_a"], w["br_b"], w["br_a"]))
        print("    肌理（纹饰带内缩 2px，均亮/HF3/MF9）：%.1f/%.1f%%/%.1f%% → %.1f/%.1f%%/%.1f%%；同画%s %.1f/%.1f%%/%.1f%%"
              % (tb[0], 100 * tb[1], 100 * tb[2], ta[0], 100 * ta[1], 100 * ta[2], rname, ref_t[0], 100 * ref_t[1],
                 100 * ref_t[2]))
        print("    高通 std（L*−σ1.5，改动像素内缩 3px，n=%d）：%.2f → %.2f" % (r["hp"][2], r["hp"][0], r["hp"][1]))
    return 0


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--only", choices=[s["key"] for s in IMAGES], help="只处理一张")
    ap.add_argument("--src", help="输入（需配 --only；缺省为仓库文件）")
    ap.add_argument("--out", help="输出（需配 --only）")
    ap.add_argument("--out-dir", help="两张都输出到这个目录（文件名同仓库）")
    ap.add_argument("--in-place", action="store_true", help="允许输出覆盖输入文件")
    ap.add_argument("--force", action="store_true", help="跳过幂等与锚点检查（调试用）")
    args = ap.parse_args(argv)
    if (args.src or args.out) and not args.only:
        print("--src / --out 需配 --only 指定是哪张图。")
        return 2
    rc = 0
    for spec in IMAGES:
        if args.only and spec["key"] != args.only:
            continue
        src = args.src or os.path.join(ROOT, spec["file"])
        if args.out:
            out = args.out
        elif args.out_dir:
            out = os.path.join(args.out_dir, os.path.basename(spec["file"]))
        else:
            out = src
        if os.path.abspath(src) == os.path.abspath(out) and not args.in_place:
            print("%s：输出与输入同一路径，需加 --in-place 才写；未写任何文件。" % spec["file"])
            rc = max(rc, 2)
            continue
        print("%s（输入 %s，%d 字节）" % (spec["file"], src, os.path.getsize(src)))
        rc = max(rc, process(spec, src, out, force=args.force))
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
