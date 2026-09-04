# -*- coding: utf-8 -*-
"""分析真机截图：判断页面结构（登录页品牌区/表单卡片），估算一键登录按钮位置。"""
import sys
from PIL import Image

img = Image.open(sys.argv[1]).convert("RGB")
w, h = img.size
print(f"尺寸: {w}x{h}")

# 1. 顶部蓝色渐变检测：统计每行的"蓝色系"像素占比（B 显著大于 R 且 B>150）
blue_rows = []
for y in range(0, h, 8):
    cnt = 0
    for x in range(0, w, 8):
        r, g, b = img.getpixel((x, y))
        if b > 150 and b - r > 40:
            cnt += 1
    ratio = cnt / (w / 8)
    blue_rows.append((y, ratio))

# 找连续蓝色区域（品牌头）
in_blue = False
segments = []
seg_start = 0
for y, ratio in blue_rows:
    is_blue = ratio > 0.6
    if is_blue and not in_blue:
        in_blue = True
        seg_start = y
    elif not is_blue and in_blue:
        in_blue = False
        segments.append((seg_start, y))
if in_blue:
    segments.append((seg_start, h))
print("蓝色渐变区段(顶部品牌头):", segments)

# 2. 白色卡片区：品牌头下方大块白色
if segments:
    header_bottom = segments[0][1]
    print(f"品牌头底部估计: y={header_bottom}")
    # 登录页布局(设计稿 375x812, 等比缩放): 品牌头 260h + 卡片(-30h 上移) + 切换行
    # 表单内: 输入框x2 + 记住行 + 登录按钮(50h) + 12h + 一键登录文字链
    scale = w / 375
    # 一键登录入口大约在: 品牌头底 260*scale 下方 卡片 padding 32 + 输入1(56+16) + 输入2(56+8+24) + 登录按钮50 + 12
    y_entry = (260 + 32 + 56 + 16 + 56 + 8 + 24 + 50 + 12) * scale
    print(f"估算一键登录入口 y ≈ {y_entry:.0f} (x 居中 {w/2:.0f})")

# 3. 全屏亮度分布（判断是否登录页：顶部蓝+中部白+底部浅色）
print(f"页面顶部中央像素: {img.getpixel((w//2, 100))}")
print(f"页面中部像素: {img.getpixel((w//2, h//2))}")
print(f"页面底部像素: {img.getpixel((w//2, h - 100))}")
