# -*- coding: utf-8 -*-
"""对比两张登录页截图，定位呼吸动画差异区域（右上圆环/左下光斑）。"""
import sys
from PIL import Image

p1, p2 = sys.argv[1], sys.argv[2]
a = Image.open(p1).convert("RGB")
b = Image.open(p2).convert("RGB")
w, h = a.size
print(f"尺寸: {w}x{h}")

# 缩小采样，逐像素差异
sa = a.resize((w // 4, h // 4))
sb = b.resize((w // 4, h // 4))
sw, sh = sa.size
diffs = []
for y in range(sh):
    for x in range(sw):
        pa, pb = sa.getpixel((x, y)), sb.getpixel((x, y))
        d = sum(abs(c1 - c2) for c1, c2 in zip(pa, pb))
        if d > 30:
            diffs.append((x, y, d))

total = sw * sh
print(f"差异像素: {len(diffs)}/{total} ({len(diffs)/total*100:.1f}%)")
if not diffs:
    print(">>> 无显著差异：动画未运行或页面未刷新")
    sys.exit(0)

# 差异区域聚类（简化：按行/列分布）
xs = [d[0] for d in diffs]
ys = [d[1] for d in diffs]
print(f"差异 x 范围: {min(xs)}-{max(xs)} (窗口左 {min(xs)*4}px, 右 {max(xs)*4}px)")
print(f"差异 y 范围: {min(ys)}-{max(ys)} (顶部 {min(ys)*4}px, 底部 {max(ys)*4}px)")

# 统计差异像素的列分布（找集中区域）
from collections import Counter
col_hist = Counter(x // 8 for x in xs)  # 每 8 采样列一组
row_hist = Counter(y // 8 for y in ys)
top_cols = col_hist.most_common(6)
top_rows = row_hist.most_common(6)
print("差异集中的列区块(采样列/8):", sorted(top_cols))
print("差异集中的行区块(采样行/8):", sorted(top_rows))

# 计算最大差异区域中心（加权）
cx = sum(x * d for x, y, d in diffs) / sum(d for _, _, d in diffs)
cy = sum(y * d for x, y, d in diffs) / sum(d for _, _, d in diffs)
print(f"差异重心: ({cx*4:.0f}, {cy*4:.0f})")

# 判断：品牌区在屏幕上半部（圆环右上、光斑左下）
if cy * 4 < h * 0.5:
    print(">>> 差异集中在屏幕上半部（品牌渐变区）=> 呼吸动画运行中")
else:
    print(">>> 差异不在品牌区，需人工确认")
