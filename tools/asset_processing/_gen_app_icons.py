# -*- coding: utf-8 -*-
"""生成 CSERGY 品牌 App 图标（渐变蓝底 + 太阳 + 光伏板）
输出: Android mipmap 全套 / iOS AppIcon 全套 / web favicon+icons / web 图标
设计: 135° 对角渐变 #0D47A1 -> #1565C0 -> #42A5F5，白色太阳（左上）+ 白色光伏板（右下网格）
"""
import os
import sys

sys.stdout.reconfigure(encoding="utf-8")

from PIL import Image, ImageDraw
import numpy as np

WT = r"C:\Users\29538\.qoder\worktree\cs_inv_monitor-develop\dpcN3z\inv_app"

# ---------- 品牌渐变（135°：左上深蓝 -> 右下浅蓝） ----------
C_TOP = np.array([13, 71, 161])    # #0D47A1
C_MID = np.array([21, 101, 192])   # #1565C0
C_BOT = np.array([66, 165, 245])   # #42A5F5


def gradient_bg(size):
    """135° 对角渐变背景（numpy 向量化）"""
    w, h = size
    y, x = np.mgrid[0:h, 0:w]
    # 沿主对角线归一化坐标 t（左上 0 -> 右下 1）
    t = (x / max(w - 1, 1) + y / max(h - 1, 1)) / 2.0
    t = np.clip(t, 0, 1)
    # 分段: [0,0.5] top->mid, [0.5,1] mid->bot
    c = np.zeros((h, w, 3), np.float32)
    lo = t <= 0.5
    hi = ~lo
    c[lo] = C_TOP + (C_MID - C_TOP) * (t[lo] * 2)[:, None]
    c[hi] = C_MID + (C_BOT - C_MID) * ((t[hi] - 0.5) * 2)[:, None]
    return np.clip(c, 0, 255).astype(np.uint8)


def draw_brand_canvas(size=2048, maskable=False, padding=0.08):
    """绘制品牌图标画布，返回 RGBA"""
    w = h = size
    img = Image.fromarray(gradient_bg((w, h)), "RGB")
    d = ImageDraw.Draw(img)
    # 图形整体缩放（maskable 需留 20% 安全区）
    s = 1.0 - padding if maskable else 1.0
    cx = cy = size / 2
    # 太阳（左上偏中，留边距避免光芒溢出）
    sun_c = (cx - 0.18 * size * s, cy - 0.22 * size * s)
    sun_r = 0.17 * size * s
    d.ellipse([sun_c[0] - sun_r, sun_c[1] - sun_r, sun_c[0] + sun_r, sun_c[1] + sun_r], fill="white")
    # 太阳光芒（8 条）
    import math
    for i in range(8):
        ang = math.pi / 4 * i + math.pi / 8
        r0 = sun_r * 1.28
        r1 = sun_r * 1.45
        x0 = sun_c[0] + r0 * math.cos(ang)
        y0 = sun_c[1] + r0 * math.sin(ang)
        x1 = sun_c[0] + r1 * math.cos(ang)
        y1 = sun_c[1] + r1 * math.sin(ang)
        d.line([x0, y0, x1, y1], fill="white", width=int(size * 0.018))
    # 光伏板（右下偏中）：白色圆角矩形 + 蓝色网格线
    pw = 0.46 * size * s
    ph = 0.26 * size * s
    px0 = cx - 0.10 * size * s - pw / 2
    py0 = cy + 0.16 * size * s - ph / 2
    px1 = px0 + pw
    py1 = py0 + ph
    r = int(size * 0.018)
    d.rounded_rectangle([px0, py0, px1, py1], radius=r, fill="white")
    # 网格线（蓝色 #1565C0）
    grid = (13, 71, 161, 255)
    lw = max(2, int(size * 0.008))
    # 中横线
    d.line([px0, (py0 + py1) / 2, px1, (py0 + py1) / 2], fill=grid, width=lw)
    # 两条竖线
    for k in (1, 2):
        x = px0 + pw * k / 3
        d.line([x, py0, x, py1], fill=grid, width=lw)
    return img.convert("RGBA")


def save_sizes(img, out_dir, sizes, name_tpl, pad=True):
    """从 2048 画布缩放到多个尺寸保存"""
    os.makedirs(out_dir, exist_ok=True)
    for s in sizes:
        im = img.resize((s, s), Image.LANCZOS)
        p = os.path.join(out_dir, name_tpl.format(s))
        im.save(p, "PNG")
        print(f"[OK] {p} {s}x{s} {os.path.getsize(p)} bytes")


def main():
    base = draw_brand_canvas(2048, maskable=False)
    base_mask = draw_brand_canvas(2048, maskable=True)

    # ---------- Android mipmap ----------
    mip = {
        "mipmap-mdpi": 48, "mipmap-hdpi": 72, "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144, "mipmap-xxxhdpi": 192,
    }
    for d, s in mip.items():
        out = os.path.join(WT, "android", "app", "src", "main", "res", d, "ic_launcher.png")
        base.resize((s, s), Image.LANCZOS).save(out, "PNG")
        print(f"[OK] {out}")

    # ---------- iOS AppIcon ----------
    ios = {
        "Icon-App-20x20@1x.png": 20, "Icon-App-20x20@2x.png": 40, "Icon-App-20x20@3x.png": 60,
        "Icon-App-29x29@1x.png": 29, "Icon-App-29x29@2x.png": 58, "Icon-App-29x29@3x.png": 87,
        "Icon-App-40x40@1x.png": 40, "Icon-App-40x40@2x.png": 80, "Icon-App-40x40@3x.png": 120,
        "Icon-App-60x60@2x.png": 120, "Icon-App-60x60@3x.png": 180,
        "Icon-App-76x76@1x.png": 76, "Icon-App-76x76@2x.png": 152,
        "Icon-App-83.5x83.5@2x.png": 167,
        "Icon-App-1024x1024@1x.png": 1024,
    }
    ios_dir = os.path.join(WT, "ios", "Runner", "Assets.xcassets", "AppIcon.appiconset")
    for name, s in ios.items():
        base.resize((s, s), Image.LANCZOS).save(os.path.join(ios_dir, name), "PNG")
    print("[OK] iOS AppIcon 全套")

    # ---------- web ----------
    web = os.path.join(WT, "web", "icons")
    save_sizes(base, web, [192, 512], "Icon-{}.png")
    save_sizes(base_mask, web, [192, 512], "Icon-maskable-{}.png")
    # favicon（64 透明底圆角图标）
    fv = base.resize((64, 64), Image.LANCZOS)
    fv.save(os.path.join(WT, "web", "favicon.png"), "PNG")
    print(f"[OK] favicon.png")

    print("done")


if __name__ == "__main__":
    main()
