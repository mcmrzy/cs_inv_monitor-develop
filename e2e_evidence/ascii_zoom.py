# -*- coding: utf-8 -*-
"""高精度 ASCII 渲染指定区域，识别文字形状。"""
import sys
from PIL import Image

img = Image.open(sys.argv[1]).convert("RGB")
x0, y0, x1, y1 = int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5])

# 蓝色系 → B, 深色 → #, 其他深 → ., 白 → 空格
for y in range(y0, y1, 2):
    line = []
    for x in range(x0, x1, 2):
        r, g, b = img.getpixel((x, y))
        lum = 0.3*r + 0.6*g + 0.1*b
        if b > 140 and b - r > 50:
            line.append("B")
        elif lum < 130:
            line.append("#")
        elif lum < 200:
            line.append(".")
        else:
            line.append(" ")
    print(f"{y:4d}|{''.join(line)}")
