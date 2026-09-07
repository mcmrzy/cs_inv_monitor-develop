# -*- coding: utf-8 -*-
"""验证集成到 inv_app/assets 的 SVG 完整性"""
import os

D = r"C:\Users\29538\.qoder\worktree\cs_inv_monitor-develop\dpcN3z\inv_app\assets\icons\csergy"

for f in sorted(os.listdir(D)):
    if not f.startswith("nav_") or not f.endswith(".svg"):
        continue
    txt = open(os.path.join(D, f), encoding="utf-8").read()
    vb = "OK" if "viewBox" in txt else "MISSING!"
    bg = "BG!" if "<path" in txt and 'd="M0 0' in txt and "translate(0,0)" in txt else "clean"
    print(f"{f:32s} viewBox={vb:8s} 背景矩形={bg}")
