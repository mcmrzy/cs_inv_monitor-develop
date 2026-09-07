# -*- coding: utf-8 -*-
"""背景图与抠图质量分析"""
import os
import sys
from PIL import Image

sys.stdout.reconfigure(encoding="utf-8")

APP = r"C:\Users\29538\.qoder\worktree\cs_inv_monitor-develop\dpcN3z\inv_app"

print("=== 背景图 ===")
bgdir = os.path.join(APP, "assets", "images", "backgrounds")
for f in sorted(os.listdir(bgdir)):
    p = os.path.join(bgdir, f)
    im = Image.open(p)
    print(f"{f}: {im.size} {im.mode} {os.path.getsize(p)} bytes")

print()
print("=== 小烁抠图（检查透明边缘质量）===")
chdir = os.path.join(APP, "assets", "character", "xiaoshuo")
for f in sorted(os.listdir(chdir)):
    p = os.path.join(chdir, f)
    im = Image.open(p)
    rgba = im.convert("RGBA")
    w, h = rgba.size
    alpha = rgba.getchannel("A")
    # 统计 alpha 分布
    hist = alpha.histogram()
    opaque = sum(hist[250:])
    transparent = sum(hist[:5])
    partial = sum(hist[5:250])
    total = w * h
    # 边缘白边检测：半透明像素中 RGB 接近白色（>230）的比例
    px = rgba.load()
    edge_white = 0
    edge_total = 0
    for y in range(0, h, 2):
        for x in range(0, w, 2):
            r, g, b, a = px[x, y]
            if 0 < a < 250:
                edge_total += 1
                if r > 230 and g > 230 and b > 230:
                    edge_white += 1
    print(
        f"{f}: {im.size} {os.path.getsize(p)}B "
        f"不透明{opaque/total*100:.1f}% 全透{transparent/total*100:.1f}% "
        f"半透{partial/total*100:.2f}% | 半透中白边 {edge_white}/{edge_total} "
        f"({edge_white/max(edge_total,1)*100:.1f}%)"
    )
