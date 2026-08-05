# -*- coding: utf-8 -*-
"""定位登录页登录按钮（蓝色渐变块）与一键登录文字链（蓝色文本）。"""
import sys
from PIL import Image

img = Image.open(sys.argv[1]).convert("RGB")
w, h = img.size

# 在卡片区找蓝色渐变按钮: 色值接近 1565C0(21,101,192)~2196F3(33,150,243)
def is_btn_blue(r, g, b):
    return (b > 150 and 60 < r < 120 and 80 < g < 170 and b - r > 50)

# 按行统计按钮蓝像素，找密集横条
rows = []
for y in range(700, 1800, 4):
    cnt = 0
    for x in range(100, w - 100, 6):
        r, g, b = img.getpixel((x, y))
        if is_btn_blue(r, g, b):
            cnt += 1
    rows.append((y, cnt))

# 聚类横条
segments = []
cur = None
for y, cnt in rows:
    if cnt > 8:
        if cur is None:
            cur = [y, y, cnt]
        else:
            cur[1] = y
            cur[2] += cnt
    else:
        if cur is not None and cur[1] - cur[0] > 20:
            segments.append(cur)
        cur = None
if cur is not None and cur[1] - cur[0] > 20:
    segments.append(cur)

print("蓝色按钮横条(起始y, 结束y, 强度):")
for s in segments:
    print(f"  y: {s[0]}-{s[1]} 强度={s[2]}")

if segments:
    # 登录按钮 = 强度最大的横条
    btn = max(segments, key=lambda s: s[2])
    btn_center_y = (btn[0] + btn[1]) // 2
    # 一键登录文字链在按钮下方 12h=12*2.88≈35px + 文字链高约 48px
    y_entry = btn[1] + 35 + 24
    print(f"登录按钮中心 y={btn_center_y}, 底部 y={btn[1]}")
    print(f">>> 一键登录入口建议点击坐标: ({w//2}, {y_entry})")
