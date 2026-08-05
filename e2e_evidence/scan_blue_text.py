# -*- coding: utf-8 -*-
"""精确扫描登录按钮下方区域，定位一键登录蓝色文字链的像素分布。"""
import sys
from PIL import Image

img = Image.open(sys.argv[1]).convert("RGB")
w, h = img.size

# 蓝色文字像素判定（AppColors.primary ~ 1565C0 = (21,101,192)）
def is_primary_blue(r, g, b):
    return b > 140 and 0 < r < 90 and 60 < g < 140 and (b - r) > 70

# 扫描 y 1400-1900，输出每行蓝色像素计数 + x 分布
print("y范围 蓝色像素数 (x: 分布段)")
for y in range(1400, 1900, 6):
    xs = []
    for x in range(0, w, 3):
        r, g, b = img.getpixel((x, y))
        if is_primary_blue(r, g, b):
            xs.append(x)
    if len(xs) > 5:
        # 聚类 x
        clusters = []
        cur = [xs[0], xs[0]]
        for x in xs[1:]:
            if x - cur[1] <= 12:
                cur[1] = x
            else:
                clusters.append(tuple(cur))
                cur = [x, x]
        clusters.append(tuple(cur))
        desc = "; ".join(f"[{a}-{b}]" for a, b in clusters)
        print(f"y={y}: {len(xs)}px {desc}")
