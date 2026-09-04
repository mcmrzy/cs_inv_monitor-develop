# -*- coding: utf-8 -*-
"""输出截图色块缩略矩阵，人工判断布局。"""
import sys
from PIL import Image

img = Image.open(sys.argv[1]).convert("RGB")
w, h = img.size
cw, ch = 36, 60  # 色块列数、行数
sw, sh = w // cw, h // ch

def brief(rgb):
    r, g, b = rgb
    if b > 140 and b - r > 50:
        return "B"  # 蓝色系
    if r > 235 and g > 235 and b > 235:
        return "."  # 白
    if r > 200 and g > 200:
        return ":"  # 浅灰白
    if r > 100 and g > 100 and b > 100:
        return "="  # 中灰
    if r > 150 and g < 100 and b < 100:
        return "R"  # 红
    if r < 90 and g < 90 and b < 90:
        return "#"  # 深色
    return "?"  # 其他

for row in range(ch):
    line = []
    for col in range(cw):
        # 采样块中心
        x = col * sw + sw // 2
        y = row * sh + sh // 2
        line.append(brief(img.getpixel((x, y))))
    print("".join(line))
