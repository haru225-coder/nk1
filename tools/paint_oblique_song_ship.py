#!/usr/bin/env python3
"""海战船图：泉州湾宋代海船型，船体坐标系里的斜俯 3/4 视（不是正俯视、不是明代多层福船）。

一条船壳画一次，两张图共用同一船壳像素；阵营只差帆色与桅顶小旗：
  assets/ship_fu.png     己方：牙白竹席硬篷 + 暗赭小旗
  assets/ship_falcon.png 敌船：同一船壳，绛红帆 + 绛红小旗

做法：在船体局部三维里搭一条船（x 右舷 / y 艉向 / z 向上，船首朝 -y 即贴图上方），
用斜投影（镜头在右舷偏后上方）投到贴图：高处往左上（左舷）偏，右舷干舷落在船身右侧一条带。
所有面按参数网格密采样，3× 超采样画布上做 z-buffer，再 3×3 方盒降采样出 512² RGBA。
不烤投影、不烤白沫（ShipLook 实时画），只在船壳上画一道 2px 湿水线。

帆色要配 assets/shaders/ship_seagoing.gdshader 的抖帆遮罩：
  cream = smoothstep(0.66, 0.84, max) * (1 - smoothstep(0.16, 0.30, max - min))
  red   = smoothstep(0.16, 0.30, r - max(g, b))
木、甲板、绳、帆骨 max ≤ 0.62 且 r-max(g,b) < 0.16，不抖。

用法：python3 tools/paint_oblique_song_ship.py   （需 numpy / Pillow / scipy；仅美术管线）
预览：/tmp/nk1-combat-wave3/oblique-ship/preview_{sheet,own,enemy}.png
自检不过 exit 1。
"""
from __future__ import annotations

import math
import os
import sys

import numpy as np
from PIL import Image
from scipy.ndimage import binary_dilation

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets")
PREVIEW_DIR = "/tmp/nk1-combat-wave3/oblique-ship"

CANVAS = 512
SS = 3  # 超采样倍数

# 斜投影：屏 X = sx·x + hx·z，屏 Y = y + hy·z（z 往左上偏 = 镜头在右舷偏后上方）
SX, HX, HY = 0.80, -0.56, -0.30
# 视线方向（从镜头射入场景）：沿它移动投影不变；depth = P·VIEW，越大越远
VIEW = np.array([HX / SX, HY, -1.0])
TO_CAM = -VIEW / np.linalg.norm(VIEW)
# 光从贴图左上（船体里 = 左舷偏前上方）
LIGHT = np.array([-0.55, -0.45, 0.70])
LIGHT = LIGHT / np.linalg.norm(LIGHT)

# 标签
T_DECK, T_SIDE, T_TRANSOM, T_SHELTER, T_MAST, T_CLOTH, T_BATTEN, T_PENNANT, T_LINE, T_RUDDER = range(1, 11)
HULL_TAGS = (T_DECK, T_SIDE, T_TRANSOM, T_SHELTER, T_RUDDER)
N_TAGS = 11

# 阵营色：只有帆布与小旗不同
PALETTE = {
    "own": {"cloth": (0.935, 0.872, 0.800), "pennant": (0.56, 0.42, 0.22)},
    "enemy": {"cloth": (0.690, 0.150, 0.128), "pennant": (0.66, 0.13, 0.11)},
}
WOOD_MAX = 0.62


# ---------------------------------------------------------------- 噪声
def _hash(ix: np.ndarray, iy: np.ndarray, seed: int) -> np.ndarray:
    h = (ix.astype(np.int64) * 374761393 + iy.astype(np.int64) * 668265263 + seed * 1442695041) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((h ^ (h >> 16)) & 0xFFFFFF).astype(np.float64) / 16777216.0


def vnoise(x: np.ndarray, y: np.ndarray, seed: int) -> np.ndarray:
    ix, iy = np.floor(x), np.floor(y)
    fx, fy = x - ix, y - iy
    ux, uy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    ix, iy = ix.astype(np.int64), iy.astype(np.int64)
    a = _hash(ix, iy, seed)
    b = _hash(ix + 1, iy, seed)
    c = _hash(ix, iy + 1, seed)
    d = _hash(ix + 1, iy + 1, seed)
    return (a + (b - a) * ux) + ((c + (d - c) * ux) - (a + (b - a) * ux)) * uy


def fbm(x: np.ndarray, y: np.ndarray, seed: int, octaves: int = 3) -> np.ndarray:
    tot, amp, norm = np.zeros_like(x, dtype=np.float64), 1.0, 0.0
    for o in range(octaves):
        tot += amp * vnoise(x * (2 ** o), y * (2 ** o), seed + o * 17)
        norm += amp
        amp *= 0.5
    return tot / norm


def hash1(i: np.ndarray, seed: int) -> np.ndarray:
    return _hash(np.asarray(i), np.zeros_like(np.asarray(i)), seed)


def smooth(e0: float, e1: float, x: np.ndarray) -> np.ndarray:
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


# ---------------------------------------------------------------- 船壳站位（t=0 艏 .. 1 艉）
B_DECK = 84.0   # 甲板半宽
B_WL = 76.0     # 水线半宽（上宽下窄 = V 底往水线收）


def deck_half(t):
    t = np.asarray(t, dtype=np.float64)
    bow = 1.0 - (1.0 - np.clip(t / 0.46, 0, 1)) ** 1.45  # 尖艏：近艏尖两舷近直线收拢
    stern = 1.0 - 0.36 * np.clip((t - 0.66) / 0.34, 0, 1) ** 1.5
    return B_DECK * np.where(t < 0.46, bow, np.where(t > 0.66, stern, 1.0))


def wl_half(t):
    t = np.asarray(t, dtype=np.float64)
    bow = 1.0 - (1.0 - np.clip((t - 0.02) / 0.46, 0, 1)) ** 1.35
    stern = 1.0 - 0.45 * np.clip((t - 0.64) / 0.36, 0, 1) ** 1.4
    return B_WL * np.where(t < 0.48, bow, np.where(t > 0.64, stern, 1.0))


def y_deck(t):
    return -200.0 + 404.0 * np.asarray(t, dtype=np.float64)


def y_wl(t):
    return -168.0 + 360.0 * np.asarray(t, dtype=np.float64)


def sheer(t):
    """甲板边高（干舷）：艏艉翘、舯部低。"""
    t = np.asarray(t, dtype=np.float64)
    return 62.0 + 46.0 * np.clip((0.46 - t) / 0.46, 0, 1) ** 2 + 38.0 * np.clip((t - 0.56) / 0.44, 0, 1) ** 1.8


def deck_z(t, s):
    return sheer(t) + 4.0 * (1.0 - np.asarray(s) ** 2)


def t_of_y_deck(y):
    return (np.asarray(y) + 200.0) / 404.0


# ---------------------------------------------------------------- 采样器
class Scene:
    def __init__(self):
        self.parts = []  # (sx, sy, depth, rgb, tag, hz)

    @staticmethod
    def project(P: np.ndarray):
        x, y, z = P[..., 0], P[..., 1], P[..., 2]
        return SX * x + HX * z, y + HY * z, P @ VIEW

    def add(self, P, rgb, tag, hz=None):
        P = P.reshape(-1, 3)
        rgb = np.asarray(rgb, dtype=np.float32).reshape(-1, 3)
        tag = np.asarray(tag, dtype=np.int8)
        tag = tag.reshape(-1).copy() if tag.ndim else np.full(P.shape[0], tag, np.int8)
        hz = np.full(P.shape[0], -1.0, np.float32) if hz is None else np.asarray(hz, np.float32).reshape(-1)
        X, Y, D = self.project(P)
        self.parts.append((X.astype(np.float32), Y.astype(np.float32), D.astype(np.float32), rgb, tag, hz))


def grid(f, nu: int, nv: int, u0=0.0, u1=1.0, v0=0.0, v1=1.0):
    u = np.linspace(u0, u1, nu)
    v = np.linspace(v0, v1, nv)
    U, V = np.meshgrid(u, v, indexing="ij")
    return U, V, f(U, V)


def normals(f, U, V, eps=1e-4):
    Pu = (f(U + eps, V) - f(U - eps, V)) / (2 * eps)
    Pv = (f(U, V + eps) - f(U, V - eps)) / (2 * eps)
    n = np.cross(Pu, Pv)
    n /= np.linalg.norm(n, axis=-1, keepdims=True) + 1e-12
    flip = (n @ TO_CAM) < 0
    n[flip] *= -1
    return n


def auto_n(f, u0, u1, v0, v1, density=2.2):
    """按投影长度定采样数：每个超采样像素约 density 个样本。"""
    U, V, P = grid(f, 24, 24, u0, u1, v0, v1)
    X, Y, _ = Scene.project(P)
    du = np.hypot(np.diff(X, axis=0), np.diff(Y, axis=0)).sum(axis=0).max()
    dv = np.hypot(np.diff(X, axis=1), np.diff(Y, axis=1)).sum(axis=1).max()
    return max(8, int(du * SS * density)), max(8, int(dv * SS * density))


def lambert(n, amb=0.52, k=0.55, sky=0.10):
    return amb + k * np.clip(n @ LIGHT, 0, 1) + sky * np.clip(n[..., 2], 0, 1)


# ---------------------------------------------------------------- 船壳
def build_hull(sc: Scene):
    # --- 右舷舷侧（近侧干舷）：u=t，v=0 甲板边 .. 1 水线；上段近直、往下收进水线
    def side(U, V):
        b, w = deck_half(U), wl_half(U)
        vx = np.clip(V, 0, 1) ** 1.35
        x = b + (w - b) * vx
        y = y_deck(U) + (y_wl(U) - y_deck(U)) * V
        z = sheer(U) * (1 - V)
        return np.stack([x, y, z], -1)

    nu, nv = auto_n(side, 0, 1, 0, 1)
    U, V, P = grid(side, nu, nv)
    n = normals(side, U, V)
    F = sheer(U)
    z = P[..., 2]
    along = y_deck(U)
    sh = lambert(n, amb=0.74, k=0.60, sky=0.16)
    sh *= 0.90 + 0.10 * (1 - V)  # 往水线收，越往下越暗
    base = np.array([0.42, 0.30, 0.20])
    # 列板：沿船身走；板缝深线
    strake_h = 12.5
    zz = z + 0.02 * along  # 板缝随舷弧微斜
    sp = zz / strake_h
    fr = sp - np.floor(sp)
    seam = smooth(0.0, 0.10, np.minimum(fr, 1 - fr) * strake_h / 1.0)
    tone = 0.90 + 0.14 * hash1(np.floor(sp).astype(np.int64), 3)
    grain = fbm(along / 26.0, zz / 1.4, 11) * 0.26 + 0.86 + 0.06 * vnoise(along / 2.5, zz * 1.2, 12)
    col = base * (tone * grain * (0.72 + 0.28 * seam))[..., None]
    # 大腊（护舷厚木）：甲板下 14–24，深色、上沿一线亮
    depth_from_top = F - z
    wale = (depth_from_top > 13) & (depth_from_top < 24)
    col = np.where(wale[..., None], np.array([0.27, 0.19, 0.13]) * (0.9 + 0.2 * fbm(along / 18, depth_from_top / 3, 5))[..., None], col)
    wale_top = (depth_from_top > 12.4) & (depth_from_top < 14.2)
    col = np.where(wale_top[..., None], np.array([0.50, 0.39, 0.27]), col)
    # 舷缘盖板外沿：顶端 3px 略亮
    cap = depth_from_top < 3.2
    col = np.where(cap[..., None], np.array([0.46, 0.35, 0.24]) * (0.95 + 0.1 * fbm(along / 10, z, 8))[..., None], col)
    # 水密隔舱钉线：隔舱位置舷侧一列暗钉
    for tb in bulkheads():
        yb = y_deck(tb)
        d = np.abs(along - yb)
        nail = (d < 1.2) & (depth_from_top > 4) & (depth_from_top < F - 8) & (np.mod(z, 6.0) < 1.6)
        col = np.where(nail[..., None], col * 0.62, col)
    rgb = col * (sh * (0.94 + 0.12 * vnoise(along / 1.6, zz * 1.3, 17)))[..., None]
    # 湿水线：最下 ~2px（z < 4.5）深湿木，上沿一丝水光
    wet = z < 4.6
    rgb = np.where(wet[..., None], np.array([0.12, 0.10, 0.085]) * (0.9 + 0.2 * fbm(along / 9, z, 21))[..., None], rgb)
    sheen = (z >= 4.6) & (z < 5.6)
    rgb = np.where(sheen[..., None], rgb * 0.7 + 0.03, rgb)
    sc.add(P, rgb, T_SIDE, hz=1 - V)

    # --- 甲板：u=t，v=s（-1 左舷 .. 1 右舷）
    def deck(U, V):
        b = deck_half(U)
        return np.stack([V * b, y_deck(U), deck_z(U, V)], -1)

    nu, nv = auto_n(deck, 0, 1, -1, 1)
    U, V, P = grid(deck, nu, nv, 0, 1, -1, 1)
    x, y = P[..., 0], P[..., 1]
    b = deck_half(U)
    n = normals(deck, U, V)
    sh = lambert(n, amb=0.58, k=0.46, sky=0.0)
    sh *= 1.0 + 0.05 * (-V) + 0.05 * (0.5 - U)  # 往左上（受光）略亮
    # 船板：沿艏艉走，往艏略收拢
    conv = 0.62 + 0.38 * np.clip(b / B_DECK, 0, 1)
    up = x / conv / 7.4
    pid = np.floor(up + 0.5).astype(np.int64)
    fr = up + 0.5 - np.floor(up + 0.5)
    seam = smooth(0.0, 0.14, np.minimum(fr, 1 - fr) * 7.4 / 1.0)
    # 板端接缝，逐板错开
    butt_len = 62.0
    bp = (y + hash1(pid, 7) * butt_len) / butt_len
    bfr = bp - np.floor(bp)
    butt = smooth(0.0, 1.0, np.minimum(bfr, 1 - bfr) * butt_len / 0.9)
    seam = seam * (0.55 + 0.45 * butt)
    tone = 0.84 + 0.24 * hash1(pid * 31 + np.floor(bp).astype(np.int64), 9)
    grain = 0.84 + 0.22 * fbm(y / 30.0, up * 4.0, 13) + 0.08 * vnoise(y / 2.2, up * 11.0, 14)
    silver = fbm(x / 40, y / 55, 15)  # 风化发灰
    base = np.array([0.60, 0.51, 0.39]) * (1 - 0.18 * silver[..., None]) + np.array([0.52, 0.50, 0.46]) * (0.18 * silver[..., None])
    col = base * (tone * grain * (0.48 + 0.52 * seam))[..., None]
    # 水密隔舱梁：细横线（梁下暗、前沿一线亮），甲板仍读成纵向船板
    for tb in bulkheads():
        yb = y_deck(tb)
        d = y - yb
        col = np.where(((d > -1.2) & (d < 1.2))[..., None], col * 0.70, col)
        col = np.where(((d > -2.2) & (d <= -1.2))[..., None], col * 1.10, col)
    # 两处平舱口
    for tc, half_l in ((0.305, 13.0), (0.600, 15.0)):
        yc = y_deck(tc)
        hw = 19.0
        ins = (np.abs(x) < hw) & (np.abs(y - yc) < half_l)
        frame = ins & ((np.abs(x) > hw - 2.2) | (np.abs(y - yc) > half_l - 2.2))
        boards = np.mod(y - yc + half_l, 5.2)
        cover = np.array([0.50, 0.41, 0.30]) * (0.9 + 0.14 * fbm(x / 12, y / 2, 31))[..., None] * np.where(boards < 0.8, 0.72, 1.0)[..., None]
        col = np.where(ins[..., None], cover, col)
        col = np.where(frame[..., None], np.array([0.30, 0.22, 0.15]), col)
    # 缆绳盘：前桅后右侧
    cx, cy, rr = 26.0, y_deck(0.225), 9.5
    rd = np.hypot(x - cx, (y - cy))
    coil = rd < rr
    ring = np.mod(rd + 0.35 * np.arctan2(y - cy, x - cx), 2.1)
    rope = np.array([0.50, 0.42, 0.28]) * np.where(ring < 0.7, 0.55, 1.0)[..., None] * (0.92 + 0.12 * np.clip((cx - x) / rr, -1, 1))[..., None]
    col = np.where(coil[..., None], rope, col)
    col = np.where((coil & (rd < 2.2))[..., None], col * 0.5, col)
    rgb = col * (sh * (0.94 + 0.12 * vnoise(y / 1.8, up * 7.4 * 1.1, 19)))[..., None]
    # 舷缘：右舷盖板（近侧，暗一线再亮一线），左舷细亮边
    edge_px = (1 - np.abs(V)) * b  # 距舷边
    star = (V > 0) & (edge_px < 3.0)
    rgb = np.where(star[..., None], np.array([0.44, 0.34, 0.23]), rgb)
    rgb = np.where(((V > 0) & (edge_px >= 3.0) & (edge_px < 4.0))[..., None], rgb * 0.70, rgb)
    port = (V < 0) & (edge_px < 2.2)
    rgb = np.where(port[..., None], np.array([0.62, 0.55, 0.43]), rgb)
    rgb = np.where(((V < 0) & (edge_px >= 2.2) & (edge_px < 3.2))[..., None], rgb * 0.78, rgb)
    sc.add(P, rgb, T_DECK, hz=np.ones_like(U))

    # --- 艉封板（小方艉）：u=s，v=0 甲板边 .. 1 水线
    def transom(U, V):
        b1, w1 = float(deck_half(1.0)), float(wl_half(1.0))
        x = U * (b1 + (w1 - b1) * np.clip(V, 0, 1) ** 1.35)
        y = float(y_deck(1.0)) + (float(y_wl(1.0)) - float(y_deck(1.0))) * V
        z = float(sheer(1.0)) * (1 - V) + 4.0 * (1 - U ** 2) * (1 - V)
        return np.stack([x, np.broadcast_to(y, x.shape), z], -1)

    nu, nv = auto_n(transom, -1, 1, 0, 1)
    U, V, P = grid(transom, nu, nv, -1, 1, 0, 1)
    n = normals(transom, U, V)
    z = P[..., 2]
    sh = lambert(n, amb=0.44, k=0.5, sky=0.12)
    pl = np.mod(z, 11.0)
    col = np.array([0.36, 0.26, 0.18]) * (0.9 + 0.18 * fbm(P[..., 0] / 20, z / 1.5, 41))[..., None] * np.where(pl < 1.0, 0.7, 1.0)[..., None]
    rgb = col * (sh * (0.94 + 0.12 * vnoise(P[..., 0] / 1.6, z * 1.3, 43)))[..., None]
    rgb = np.where((z < 4.6)[..., None], np.array([0.12, 0.10, 0.085]), rgb)
    rgb = np.where((float(sheer(1.0)) - z < 3.0)[..., None], np.array([0.46, 0.35, 0.24]), rgb)
    sc.add(P, rgb, T_TRANSOM, hz=1 - V)


def bulkheads():
    return [0.07 + k * (0.86 / 12) for k in range(13)]


# ---------------------------------------------------------------- 舵 / 舵柄 / 艉棚
def build_stern(sc: Scene):
    y_st = float(y_wl(1.0))
    # 开孔舵：艉中线轴向舵，只画水线上一截，几个菱形透孔贴在水线
    y0, y1, ztop = y_st + 1.0, y_st + 17.0, 26.0

    def blade(U, V):
        return np.stack([np.full_like(U, 2.0), y0 + (y1 - y0) * U, ztop * V], -1)

    nu, nv = auto_n(blade, 0, 1, 0, 1)
    U, V, P = grid(blade, nu, nv)
    y, z = P[..., 1], P[..., 2]
    keep = ~((z > 16) & (U > 0.55))  # 舵叶上沿收成舵杆
    holes = np.zeros_like(keep)
    for hy_, hz_ in ((y0 + 5.0, 6.0), (y0 + 11.0, 6.0), (y0 + 8.0, 12.0)):
        holes |= (np.abs(y - hy_) / 2.4 + np.abs(z - hz_) / 2.4) < 1.0
    keep &= ~holes
    col = np.array([0.30, 0.21, 0.14]) * (0.9 + 0.2 * fbm(y / 4, z / 9, 51))[..., None] * 0.8
    col = np.where((z < 4.6)[..., None], np.array([0.11, 0.09, 0.08]), col)
    sc.add(P[keep], col[keep], T_RUDDER, hz=(z / float(sheer(1.0)))[keep])
    # 舵杆到甲板
    zs = float(sheer(1.0)) + 10.0
    add_cylinder(sc, np.array([0.0, y0 + 3.0, 16.0]), np.array([0.0, y0 + 2.0, zs]), 2.2, 2.0, (0.30, 0.22, 0.15), T_RUDDER)
    # 舵柄：往前横过艉甲板
    add_cylinder(sc, np.array([0.0, y0 + 2.0, zs]), np.array([0.0, float(y_deck(0.885)), float(deck_z(0.885, 0.0)) + 9.0]), 1.8, 1.4, (0.40, 0.30, 0.20), T_RUDDER)

    # 艉棚：一层低矮席篷（明显低于主桅，不是楼）
    t0, t1 = 0.695, 0.855
    wall_h = 23.0

    def hw(t):
        return 0.60 * deck_half(t)

    # 右舷墙
    def swall(U, V):
        t = t0 + (t1 - t0) * U
        return np.stack([hw(t), y_deck(t), deck_z(t, 0.6) + wall_h * V], -1)

    nu, nv = auto_n(swall, 0, 1, 0, 1)
    U, V, P = grid(swall, nu, nv)
    n = normals(swall, U, V)
    y, z = P[..., 1], P[..., 2]
    pan = np.mod(y, 14.0)
    col = np.array([0.36, 0.26, 0.17]) * (0.9 + 0.2 * fbm(y / 3, z / 14, 61))[..., None] * np.where(pan < 1.2, 0.68, 1.0)[..., None]
    win = (np.mod(y + 7, 28.0) < 7) & (V > 0.35) & (V < 0.7)
    col = np.where(win[..., None], np.array([0.12, 0.09, 0.07]), col)
    sc.add(P, col * lambert(n, amb=0.50, k=0.55, sky=0.14)[..., None], T_SHELTER, hz=np.ones_like(U))
    # 艉墙
    def awall(U, V):
        t = np.full_like(U, t1)
        return np.stack([U * hw(t), y_deck(t), deck_z(t, U * 0.6) + wall_h * V], -1)

    nu, nv = auto_n(awall, -1, 1, 0, 1)
    U, V, P = grid(awall, nu, nv, -1, 1, 0, 1)
    n = normals(awall, U, V)
    x = P[..., 0]
    col = np.array([0.33, 0.24, 0.16]) * (0.9 + 0.2 * fbm(x / 3, V * 5, 62))[..., None]
    door = (np.abs(x - 6) < 7) & (V < 0.78)
    col = np.where(door[..., None], np.array([0.10, 0.08, 0.06]), col)
    sc.add(P, col * lambert(n, amb=0.46, k=0.5, sky=0.12)[..., None], T_SHELTER, hz=np.ones_like(U))
    # 席篷顶：拱形，四面略出檐
    def roof(U, V):
        t = (t0 - 0.012) + (t1 - t0 + 0.024) * U
        h = hw(t) + 3.5
        x = V * h
        z = deck_z(t, 0.6) + wall_h + 10.0 * (1 - V ** 2) - 1.0
        return np.stack([x, y_deck(t), z], -1)

    nu, nv = auto_n(roof, 0, 1, -1, 1)
    U, V, P = grid(roof, nu, nv, 0, 1, -1, 1)
    n = normals(roof, U, V)
    x, y = P[..., 0], P[..., 1]
    wa = np.sin((x + y) * 1.25) * np.sin((x - y) * 1.25)  # 竹席斜纹
    col = np.array([0.56, 0.47, 0.31]) * (0.88 + 0.08 * wa + 0.12 * fbm(x / 9, y / 9, 71))[..., None]
    rib = np.mod(y, 10.0) < 1.3
    col = np.where(rib[..., None], col * 0.72, col)
    eave = (np.abs(V) > 0.955) | (U < 0.03) | (U > 0.97)
    col = np.where(eave[..., None], col * 0.66, col)
    sc.add(P, col * lambert(n, amb=0.58, k=0.46, sky=0.0)[..., None], T_SHELTER, hz=np.ones_like(U))


def add_cylinder(sc: Scene, a: np.ndarray, b: np.ndarray, r0: float, r1: float, rgb, tag, grain_seed=81):
    axis = b - a
    L = float(np.linalg.norm(axis))
    ax = axis / L
    e1 = np.cross(ax, np.array([0.0, 0.0, 1.0]) if abs(ax[2]) < 0.9 else np.array([1.0, 0.0, 0.0]))
    e1 /= np.linalg.norm(e1)
    e2 = np.cross(ax, e1)
    nu = max(16, int(L * SS * 2.6))
    nv = max(16, int(2 * np.pi * max(r0, r1) * SS * 2.2))
    h = np.linspace(0, 1, nu)[:, None]
    ph = np.linspace(0, 2 * np.pi, nv, endpoint=False)[None, :]
    r = r0 + (r1 - r0) * h
    nrm = np.cos(ph)[..., None] * e1 + np.sin(ph)[..., None] * e2
    nrm = np.broadcast_to(nrm, (nu, nv, 3))
    P = a + (h * L)[..., None] * ax + r[..., None] * nrm
    vis = (nrm @ TO_CAM) > -0.05
    sh = 0.42 + 0.72 * np.clip(nrm @ LIGHT, 0, 1)
    g = 0.9 + 0.2 * fbm(np.broadcast_to(h * L / 20, (nu, nv)), np.broadcast_to(ph * 1.5, (nu, nv)), grain_seed)
    col = np.array(rgb) * (sh * g)[..., None]
    sc.add(P[vis], col[vis], tag)


# ---------------------------------------------------------------- 桅 / 竹席硬篷 / 小旗 / 索具
RAKE = 0.07  # 桅往艉倾


class Mast:
    def __init__(self, t, height, r, sail):
        self.t = t
        self.foot = np.array([0.0, float(y_deck(t)), float(deck_z(t, 0.0))])
        self.height = height
        self.r = r
        self.sail = sail  # dict(W, H, h0, theta, n_battens)

    def at(self, h):
        return self.foot + np.array([0.0, RAKE * h, h])

    @property
    def top(self):
        return self.at(self.height)


def build_mast(sc: Scene, m: Mast):
    add_cylinder(sc, m.foot - np.array([0, 0, 1.0]), m.top, m.r, m.r * 0.62, (0.54, 0.42, 0.28), T_MAST)


def sail_fn(m: Mast):
    s = m.sail
    W, H, h0, th = s["W"], s["H"], s["h0"], math.radians(s["theta"])
    da = np.array([math.sin(th), math.cos(th), 0.0])  # 帆面水平向：往艉、偏右舷
    ns = np.array([math.cos(th), -math.sin(th), 0.0])  # 背风（右舷偏前）鼓出
    a0 = -0.17 * W
    n_p = s["n_battens"] + 1

    def f(U, V):  # U = p（前缘 0 .. 后缘 1），V = u（帆脚 0 .. 帆顶 1）
        a1 = 0.83 * W + 0.10 * W * np.sin(np.pi * V)  # 后缘外鼓（扇形）
        a = a0 + U * (a1 - a0)
        h = h0 + V * H * (1.0 + 0.20 * U)  # 帆顶往后翘
        fu = V * n_p - np.floor(V * n_p)
        belly = W * (0.075 * np.abs(np.sin(np.pi * U)) ** 0.9 * (0.75 + 0.25 * np.sin(np.pi * V))
                     + 0.018 * np.sin(np.pi * fu) * np.sin(np.pi * U))
        base = m.foot[None, None, :] + np.stack([np.zeros_like(h), RAKE * h - 6.0, h], -1)  # 帆挂在桅前
        return base + a[..., None] * da + belly[..., None] * ns

    return f, n_p


def build_sail(sc: Scene, m: Mast, faction: str):
    s = m.sail
    W, H = s["W"], s["H"]
    f, n_p = sail_fn(m)
    nu, nv = auto_n(f, 0, 1, 0, 1, density=2.4)
    U, V, P = grid(f, nu, nv)
    n = normals(f, U, V)
    # 亮度只在很窄的档里起伏（牙白帆要稳稳落在抖帆奶油域里）：鼓处迎光略亮，背光透一点
    ndl = n @ LIGHT
    shade = 0.93 + 0.05 * np.clip(ndl, -1, 1) + 0.035 * np.sin(np.pi * U)
    fu = V * n_p - np.floor(V * n_p)
    pidx = np.floor(V * n_p).astype(np.int64)
    panel_h = H / n_p
    d_batten = np.minimum(fu, 1 - fu) * panel_h
    shade = shade - 0.045 * (1 - smooth(0.0, 0.35, fu))  # 帆骨下一线阴影
    shade = shade * (0.985 + 0.03 * hash1(pidx * 7 + s["n_battens"], 91))
    width_a = (0.83 * W + 0.10 * W * np.sin(np.pi * V)) + 0.17 * W
    d_luff = U * width_a
    d_leech = (1 - U) * width_a
    # 竹席编纹
    a_c, h_c = U * width_a, V * H
    weave = np.sin(a_c * 1.9 + h_c * 1.9) * np.sin(a_c * 1.9 - h_c * 1.9)
    weave_n = 0.012 * weave + 0.022 * (fbm(a_c / 5, h_c / 5, 93) - 0.5)
    cloth_rgb = np.array(PALETTE[faction]["cloth"]) * np.clip(shade + weave_n, 0.86, 1.0)[..., None]
    # 帆骨（竹篾）、帆顶桁、帆脚桁、边绳：一律压在抖帆门槛下
    is_spar = (V < 0.02) | (V > 0.98)
    is_batten = (d_batten < 1.35) | is_spar
    bamboo = np.array([0.50, 0.40, 0.25]) * (0.82 + 0.28 * np.clip(0.5 + 0.5 * np.sin((fu - 0.5) * 12.0), 0, 1))[..., None]
    bamboo = np.where(is_spar[..., None], np.array([0.40, 0.31, 0.20]), bamboo)
    is_rope = (d_luff < 1.3) | (d_leech < 1.4)
    rope = np.array([0.36, 0.28, 0.19])
    rgb = np.where(is_batten[..., None], bamboo, cloth_rgb)
    rgb = np.where((is_rope & ~is_batten)[..., None], rope, rgb)
    tag = np.where(is_batten | is_rope, T_BATTEN, T_CLOTH).astype(np.int8)
    sc.add(P, rgb, tag)
    return f


def build_pennant(sc: Scene, m: Mast, faction: str):
    top = m.top + np.array([0.0, 0.0, 3.0])
    add_cylinder(sc, m.top, top + np.array([0, 0, 6.0]), 1.0, 0.8, (0.34, 0.26, 0.18), T_MAST)
    d = np.array([0.45, -0.88, -0.05])  # 风从左舷偏艉来（同 ship_seagoing wind_dir），旗往右舷偏艏飘
    d /= np.linalg.norm(d)
    side = np.array([-d[1], d[0], 0.0])
    L = 54.0

    def f(U, V):  # U 沿旗长，V 旗宽 0..1
        w = 10.0 * (1 - U) + 1.4 * U
        wave = 3.2 * np.sin(U * 7.0 + 0.6) * U
        base = top[None, None, :] + np.array([0, 0, 2.0])
        return base + (U * L)[..., None] * d + (wave)[..., None] * side + (-(V * w))[..., None] * np.array([0, 0, 1.0])

    nu, nv = auto_n(f, 0, 1, 0, 1)
    U, V, P = grid(f, nu, nv)
    keep = ~((U > 0.72) & (np.abs(V - 0.5) < 0.5 * (U - 0.72) / 0.28 * 1.1))  # 燕尾
    n = normals(f, U, V)
    sh = 0.86 + 0.14 * np.clip(n @ LIGHT, 0, 1) + 0.05 * np.sin(U * 7.0 + 0.6)
    rgb = np.array(PALETTE[faction]["pennant"]) * sh[..., None]
    sc.add(P[keep], rgb[keep], T_PENNANT)


def add_line(sc: Scene, a, b, rgb=(0.22, 0.18, 0.14), width=0.85, tag=T_LINE):
    """细索：屏幕空间定宽线，深度沿线插值。"""
    a, b = np.asarray(a, float), np.asarray(b, float)
    Xa, Ya, _ = Scene.project(a)
    Xb, Yb, _ = Scene.project(b)
    L = math.hypot(Xb - Xa, Yb - Ya)
    n = max(8, int(L * SS * 2.5))
    t = np.linspace(0, 1, n)[:, None]
    P = a + (b - a) * t
    # 横向偏移在屏幕上做：沿垂直于线的方向微移 3D 点（x/z 组合换算成屏幕像素）
    nx, ny = -(Yb - Ya) / (L + 1e-9), (Xb - Xa) / (L + 1e-9)
    offs = np.linspace(-width / 2, width / 2, max(2, int(width * SS * 2)))
    pts = []
    for o in offs:
        # 屏幕 (dx,dy) = (SX*px, py)（z 不动）
        pts.append(P + np.array([nx * o / SX, ny * o, 0.0]))
    P = np.concatenate(pts, 0)
    sc.add(P, np.broadcast_to(np.array(rgb), P.shape), tag)


def build_ship(faction: str) -> Scene:
    sc = Scene()
    build_hull(sc)
    build_stern(sc)
    fore = Mast(0.17, 196.0, 2.0, dict(W=80.0, H=122.0, h0=52.0, theta=32.0, n_battens=6))
    main = Mast(0.44, 290.0, 2.5, dict(W=114.0, H=172.0, h0=72.0, theta=28.0, n_battens=7))
    for m in (fore, main):
        build_mast(sc, m)
        f = build_sail(sc, m, faction)
        # 帆顶吊索、两三根帆脚分索汇到甲板
        add_line(sc, m.at(m.height - 4), f(np.array([[0.02]]), np.array([[1.0]]))[0, 0], width=0.7)
        n_p = m.sail["n_battens"] + 1
        tail = np.array([34.0 if m is main else 30.0, m.foot[1] + (128.0 if m is main else 92.0), 0.0])
        tail[2] = float(deck_z(t_of_y_deck(tail[1]), tail[0] / float(deck_half(t_of_y_deck(tail[1]))))) + 1.0
        block = tail + np.array([-10.0, -14.0, 40.0])
        for k in ((2, 5) if m is main else (3,)):
            p = f(np.array([[1.0]]), np.array([[k / n_p]]))[0, 0]
            add_line(sc, p, block, width=0.6, rgb=(0.26, 0.21, 0.16))
        add_line(sc, block, tail, width=0.75, rgb=(0.24, 0.19, 0.14))
    # 桅侧支索：主桅两根（上风左舷）、前桅一根
    def gunwale(t, side):
        return np.array([side * float(deck_half(t)) * 0.98, float(y_deck(t)), float(sheer(t)) + 1.0])

    add_line(sc, main.at(main.height * 0.82), gunwale(0.50, -1), width=0.8)
    add_line(sc, main.at(main.height * 0.82), gunwale(0.40, -1), width=0.8)
    add_line(sc, main.at(main.height * 0.70), gunwale(0.52, 1), width=0.8)
    add_line(sc, fore.at(fore.height * 0.80), gunwale(0.22, -1), width=0.75)
    build_pennant(sc, main, faction)
    return sc, (fore, main)


# ---------------------------------------------------------------- 光栅化
def rasterize(sc: Scene, offset=None):
    X = np.concatenate([p[0] for p in sc.parts])
    Y = np.concatenate([p[1] for p in sc.parts])
    D = np.concatenate([p[2] for p in sc.parts])
    C = np.concatenate([p[3] for p in sc.parts])
    Tg = np.concatenate([p[4] for p in sc.parts])
    Hz = np.concatenate([p[5] for p in sc.parts])
    if offset is None:
        hull = np.isin(Tg, HULL_TAGS)
        ox = CANVAS / 2 - (X[hull].min() + X[hull].max()) / 2
        oy = CANVAS / 2 - (Y[hull].min() + Y[hull].max()) / 2
        offset = (ox, oy)
    ox, oy = offset
    N = CANVAS * SS
    px = np.floor((X + ox) * SS).astype(np.int64)
    py = np.floor((Y + oy) * SS).astype(np.int64)
    ok = (px >= 0) & (px < N) & (py >= 0) & (py < N)
    px, py, D, C, Tg, Hz = px[ok], py[ok], D[ok], C[ok], Tg[ok], Hz[ok]
    order = np.argsort(-D, kind="stable")  # 远 → 近，近的最后写
    idx = py[order] * N + px[order]
    rgb = np.zeros((N * N, 3), np.float32)
    cov = np.zeros(N * N, np.float32)
    tag = np.zeros(N * N, np.int8)
    hz = np.full(N * N, -1.0, np.float32)
    rgb[idx] = C[order]
    cov[idx] = 1.0
    tag[idx] = Tg[order]
    hz[idx] = Hz[order]
    return rgb.reshape(N, N, 3), cov.reshape(N, N), tag.reshape(N, N), hz.reshape(N, N), offset


def fill_pinholes(rgb, cov, tag, hz):
    """超采样散点偶有针孔：四邻都有、自己空的像素用邻居补。"""
    for _ in range(2):
        empty = cov == 0
        nb = np.zeros_like(cov)
        acc = np.zeros_like(rgb)
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            c = np.roll(np.roll(cov, dy, 0), dx, 1)
            nb += c
            acc += np.roll(np.roll(rgb, dy, 0), dx, 1) * c[..., None]
        hole = empty & (nb >= 3)
        rgb[hole] = acc[hole] / nb[hole][..., None]
        cov[hole] = 1.0
        t2 = np.roll(tag, 1, 1)
        tag[hole] = t2[hole]
        hz[hole] = np.roll(hz, 1, 1)[hole]
    return rgb, cov, tag, hz


def downsample(rgb, cov, tag, hz):
    n = CANVAS
    c = cov.reshape(n, SS, n, SS)
    a = c.mean(axis=(1, 3))
    prem = (rgb * cov[..., None]).reshape(n, SS, n, SS, 3).sum(axis=(1, 3))
    csum = c.sum(axis=(1, 3))
    col = prem / np.maximum(csum, 1e-6)[..., None]
    tagcov = np.zeros((N_TAGS, n, n), np.float32)
    t = tag.reshape(n, SS, n, SS)
    for k in range(1, N_TAGS):
        tagcov[k] = (t == k).mean(axis=(1, 3))
    hzr = np.where(hz >= 0, hz, 0).reshape(n, SS, n, SS).sum(axis=(1, 3))
    hzc = (hz >= 0).reshape(n, SS, n, SS).sum(axis=(1, 3))
    hz_out = np.where(hzc > 0, hzr / np.maximum(hzc, 1), -1)
    out = np.dstack([np.clip(col, 0, 1), a])
    return out, tagcov, hz_out


def cap_wood(img, tagcov):
    """非帆布、非小旗像素 max 通道压到 WOOD_MAX，r-max(g,b) 压到 0.14：不进抖帆遮罩。"""
    rgb = img[..., :3]
    sailish = (tagcov[T_CLOTH] + tagcov[T_PENNANT]) > 0.0
    mx = rgb.max(axis=-1)
    scale = np.where((~sailish) & (mx > WOOD_MAX), WOOD_MAX / np.maximum(mx, 1e-6), 1.0)
    rgb = rgb * scale[..., None]
    gb = np.maximum(rgb[..., 1], rgb[..., 2])
    over = (~sailish) & (rgb[..., 0] - gb > 0.14)
    rgb[..., 0] = np.where(over, gb + 0.14, rgb[..., 0])
    img[..., :3] = rgb
    return img


def render(faction: str, offset=None):
    sc, masts = build_ship(faction)
    rgb, cov, tag, hz, offset = rasterize(sc, offset)
    rgb, cov, tag, hz = fill_pinholes(rgb, cov, tag, hz)
    img, tagcov, hzm = downsample(rgb, cov, tag, hz)
    img = cap_wood(img, tagcov)
    img[0, 0, 3] = img[0, -1, 3] = img[-1, 0, 3] = img[-1, -1, 3] = 0.0
    return img, tagcov, hzm, offset, masts


def to_u8(img):
    return np.clip(np.round(img * 255), 0, 255).astype(np.uint8)


# ---------------------------------------------------------------- 自检与预览
def masks(rgb):
    mx = rgb.max(axis=-1)
    sat = mx - rgb.min(axis=-1)
    cream = smooth(0.66, 0.84, mx) * (1 - smooth(0.16, 0.30, sat))
    red = smooth(0.16, 0.30, rgb[..., 0] - np.maximum(rgb[..., 1], rgb[..., 2]))
    return cream, red


def lum(rgb):
    return 0.299 * rgb[..., 0] + 0.587 * rgb[..., 1] + 0.114 * rgb[..., 2]


def self_check(paths, own_u8, en_u8, tagcov, hzm, offset, masts):
    fails = []
    stats = {}
    for p in paths:
        im = Image.open(p)
        a = np.array(im)
        size = os.path.getsize(p)
        stats[os.path.basename(p) + "_bytes"] = size
        if im.size != (CANVAS, CANVAS) or im.mode != "RGBA":
            fails.append(f"{p}: {im.size} {im.mode}")
        if any(a[y, x, 3] != 0 for y, x in ((0, 0), (0, -1), (-1, 0), (-1, -1))):
            fails.append(f"{p}: 四角不透明")
        if size < 100 * 1024:
            fails.append(f"{p}: {size}B < 100KB")

    own = own_u8.astype(np.int32)
    en = en_u8.astype(np.int32)
    opaque = (own[..., 3] > 0) | (en[..., 3] > 0)
    diff = (np.abs(own[..., :3].max(-1) - en[..., :3].max(-1)) > 18) & opaque
    frac = diff.sum() / opaque.sum()
    stats["diff_frac"] = round(float(frac), 4)
    if frac >= 0.28:
        fails.append(f"帆色差异像素 {frac:.1%} ≥ 28%")
    sail_zone = binary_dilation((tagcov[T_CLOTH] + tagcov[T_PENNANT]) > 0, iterations=1)
    outside = diff & ~sail_zone
    stats["diff_outside_sail"] = int(outside.sum())
    if outside.sum() > 0:
        fails.append(f"帆 / 旗之外有 {outside.sum()} 个差异像素")
    # 差异不得在龙骨 / 水线带：水线带 = 舷侧低三分之一
    keel = (tagcov[T_SIDE] > 0.5) & (hzm >= 0) & (hzm < 0.34)
    stats["diff_on_keel_band"] = int((diff & keel).sum())
    if (diff & keel).sum() > 0:
        fails.append("龙骨 / 水线带有阵营差异像素")
    # 帆差异应在桅脚右上（高处 = 帆离桅脚往上、帆朝右舷张）
    ys, xs = np.nonzero(diff)
    feet = []
    for m in masts:
        X, Y, _ = Scene.project(m.foot)
        feet.append((X + offset[0], Y + offset[1]))
    stats["diff_centroid"] = (round(float(xs.mean()), 1), round(float(ys.mean()), 1))
    stats["mast_feet"] = [(round(fx, 1), round(fy, 1)) for fx, fy in feet]
    if not ys.mean() < max(fy for _, fy in feet):
        fails.append("帆差异重心不在桅脚上方")
    # 帆朝右舷张：差异像素多数落在所属桅杆投影线的艉 / 右舷一侧（桅线从桅脚往左上，帆脚从桅往右下张）
    side = np.zeros(len(xs), bool)
    best = np.full(len(xs), np.inf)
    for m in masts:
        fx, fy, _ = Scene.project(m.foot)
        tx, ty, _ = Scene.project(m.top)
        fx, fy, tx, ty = fx + offset[0], fy + offset[1], tx + offset[0], ty + offset[1]
        ux, uy = tx - fx, ty - fy
        L2 = ux * ux + uy * uy
        k = np.clip(((xs - fx) * ux + (ys - fy) * uy) / L2, 0, 1)
        d = np.hypot(xs - (fx + k * ux), ys - (fy + k * uy))
        cross = ux * (ys - fy) - uy * (xs - fx)  # 屏幕 y 向下：<0 = 在桅线右下（艉 / 右舷）一侧
        take = d < best
        best[take] = d[take]
        side[take] = cross[take] < 0
    stats["diff_starboard_of_mast"] = round(float(side.mean()), 3)
    if side.mean() < 0.6:
        fails.append(f"帆差异只有 {side.mean():.0%} 在桅线艉 / 右舷一侧（帆没往右舷张）")

    # 斜视检验：舯部扫线，左舷甲板一侧明显亮于右舷干舷带
    rgb = own_u8[..., :3].astype(np.float64) / 255.0
    hull = sum(tagcov[t] for t in HULL_TAGS) > 0.95
    ys_h, xs_h = np.nonzero(hull)
    y0, y1 = ys_h.min(), ys_h.max()
    stats["hull_long_axis_px"] = int(y1 - y0 + 1)
    # 取舯部无帆遮挡的行：主帆脚与艉棚之间
    rows = []
    for y in range(int(y0 + 0.46 * (y1 - y0)), int(y0 + 0.66 * (y1 - y0))):
        occl = (tagcov[T_CLOTH][y] + tagcov[T_BATTEN][y] + tagcov[T_SHELTER][y]).max()
        if occl < 0.05:
            rows.append(y)
    if len(rows) < 8:
        fails.append(f"舯部可扫行太少：{len(rows)}")
    deck_l, star_l, band_w = [], [], []
    for y in rows:
        xs_r = np.nonzero(hull[y])[0]
        x0, x1 = xs_r.min(), xs_r.max()
        span = x1 - x0 + 1
        port = rgb[y, x0 + 3: x0 + int(span * 0.55)]
        star = rgb[y, x1 - int(span * 0.16): x1 - 2]
        deck_l.append(lum(port).mean())
        star_l.append(lum(star).mean())
        band_w.append(int((tagcov[T_SIDE][y] > 0.5).sum()))
    dl, sl = float(np.mean(deck_l)), float(np.mean(star_l))
    stats["mid_deck_lum"], stats["mid_topside_lum"] = round(dl, 3), round(sl, 3)
    stats["mid_topside_band_px"] = (min(band_w), round(float(np.mean(band_w)), 1), max(band_w))
    if dl - sl < 0.08:
        fails.append(f"舯部甲板亮度 {dl:.3f} 不明显高于右舷干舷 {sl:.3f}")
    if not 26 <= np.mean(band_w) <= 38:
        fails.append(f"舯部干舷带 {np.mean(band_w):.1f}px 不在 26–38")
    # 干舷往右舷垂：船体高度的下三分之一（水线一带）重心比上三分之一（甲板 / 舷缘）偏右 ≥ 10px
    alpha = own_u8[..., 3] > 0
    hb = alpha & (sum(tagcov[t] for t in HULL_TAGS) > 0.5) & (hzm >= 0)
    lo = hb & (hzm < 1 / 3)
    hi = hb & (hzm > 2 / 3)
    cl = float(np.nonzero(lo)[1].mean())
    ch = float(np.nonzero(hi)[1].mean())
    stats["centroid_lower_third_x"], stats["centroid_upper_third_x"] = round(cl, 1), round(ch, 1)
    stats["freeboard_shift_px"] = round(cl - ch, 1)
    if cl - ch < 10:
        fails.append(f"干舷未往右舷垂：下 1/3 重心 {cl:.1f} − 上 1/3 {ch:.1f} < 10px（画成俯视了）")
    # 左右对称 = 俯视失败：船体左右镜像差
    hull_a = hull.astype(np.float32)
    cx = int(round((xs_h.min() + xs_h.max()) / 2))
    wmin = min(cx - xs_h.min(), xs_h.max() - cx)
    left = hull_a[:, cx - wmin: cx][:, ::-1]
    right = hull_a[:, cx: cx + wmin]
    stats["hull_mirror_mismatch"] = round(float(np.abs(left - right).mean() / max(hull_a.mean(), 1e-6)), 3)

    # 帆布抖帆遮罩
    cloth = tagcov[T_CLOTH] > 0.99
    stats["cloth_px"] = int(cloth.sum())
    cr_o, rd_o = masks(own_u8[..., :3].astype(np.float64) / 255.0)
    cr_e, rd_e = masks(en_u8[..., :3].astype(np.float64) / 255.0)
    stats["own_cloth_cream"] = round(float(cr_o[cloth].mean()), 3)
    stats["enemy_cloth_red"] = round(float(rd_e[cloth].mean()), 3)
    stats["enemy_cloth_cream"] = round(float(cr_e[cloth].mean()), 3)
    if cr_o[cloth].mean() <= 0.65:
        fails.append(f"己方帆布 cream {cr_o[cloth].mean():.3f} ≤ 0.65")
    if rd_e[cloth].mean() <= 0.65:
        fails.append(f"敌帆布 red {rd_e[cloth].mean():.3f} ≤ 0.65")
    if cr_e[cloth].mean() >= 0.15:
        fails.append(f"敌帆布 cream {cr_e[cloth].mean():.3f} ≥ 0.15")
    wood = (own_u8[..., 3] > 200) & ((tagcov[T_CLOTH] + tagcov[T_PENNANT]) == 0)
    wmask = np.maximum(cr_o, rd_o)[wood]
    stats["wood_flutter_max"] = round(float(wmask.max()), 3)
    if wmask.max() > 0.02:
        fails.append(f"木 / 绳像素进了抖帆遮罩（max {wmask.max():.3f}）")
    return fails, stats


def previews(own_u8, en_u8, tagcov):
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    sea = (0x1A, 0x4C, 0x66, 255)
    own = Image.fromarray(own_u8, "RGBA")
    en = Image.fromarray(en_u8, "RGBA")
    for im, name in ((own, "preview_own.png"), (en, "preview_enemy.png")):
        bg = Image.new("RGBA", im.size, sea)
        bg.alpha_composite(im)
        bg.convert("RGB").save(os.path.join(PREVIEW_DIR, name))
    # 舯部 2× 特写：甲板 + 干舷 + 主帆边
    hull = sum(tagcov[t] for t in HULL_TAGS) > 0.95
    ys, xs = np.nonzero(hull)
    cy = int(ys.min() + 0.52 * (ys.max() - ys.min()))
    cx = int((xs.min() + xs.max()) / 2)
    box = (cx - 110, cy - 100, cx + 90, cy + 100)
    crop = own.crop(box).resize((400, 400), Image.LANCZOS)
    W, H = 512 * 2 + 400 + 80, 512 + 60 + 330
    sheet = Image.new("RGBA", (W, H), sea)
    sheet.alpha_composite(own, (20, 20))
    sheet.alpha_composite(en, (552, 20))
    cbg = Image.new("RGBA", crop.size, sea)
    cbg.alpha_composite(crop)
    sheet.alpha_composite(cbg, (1084, 20))
    # 引擎缩放 0.62 并排（含一条转向 35°）
    y2 = 560
    for i, (im, rot) in enumerate(((own, 0), (en, 0), (own, -35), (en, 50))):
        s = im.resize((317, 317), Image.LANCZOS).rotate(rot, resample=Image.BICUBIC)
        sheet.alpha_composite(s, (20 + i * 330, y2))
    sheet.convert("RGB").save(os.path.join(PREVIEW_DIR, "preview_sheet.png"))


def main() -> int:
    own, tagcov, hzm, offset, masts = render("own")
    en, tagcov_e, _, _, _ = render("enemy", offset)
    own_u8, en_u8 = to_u8(own), to_u8(en)
    p_own = os.path.join(OUT, "ship_fu.png")
    p_en = os.path.join(OUT, "ship_falcon.png")
    Image.fromarray(own_u8, "RGBA").save(p_own, optimize=True)
    Image.fromarray(en_u8, "RGBA").save(p_en, optimize=True)
    previews(own_u8, en_u8, tagcov)
    fails, stats = self_check((p_own, p_en), own_u8, en_u8, tagcov, hzm, offset, masts)
    print(f"  {p_own}  {os.path.getsize(p_own)}B")
    print(f"  {p_en}  {os.path.getsize(p_en)}B")
    for k, v in stats.items():
        print(f"    {k}: {v}")
    print(f"  预览 {PREVIEW_DIR}/preview_sheet.png / preview_own.png / preview_enemy.png")
    if fails:
        for f in fails:
            print(f"  ✗ {f}")
        return 1
    print("  ✓ 自检全过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
