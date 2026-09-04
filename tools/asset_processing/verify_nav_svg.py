# -*- coding: utf-8 -*-
"""验证修复后的导航 SVG"""
import os
import re

D = r"C:\Users\29538\Pictures\csinv_app美术素材\processed\nav_icons"


def main():
    for f in sorted(os.listdir(D)):
        if not f.endswith(".svg"):
            continue
        txt = open(os.path.join(D, f), encoding="utf-8").read()
        m = re.search(r'viewBox="([^"]+)"', txt)
        vb = m.group(1) if m else "MISSING"
        # 背景矩形：第一个 path 以 M0 0 开头且 translate(0,0)
        first_path = re.search(r"<path[^>]*>", txt)
        is_bg = False
        if first_path:
            seg = first_path.group(0)
            is_bg = 'd="M0 0' in seg and "translate(0,0)" in seg
        npath = txt.count("<path")
        print(f"{f:32s} viewBox={vb:14s} 首个path是背景矩形={is_bg} path总数={npath}")


if __name__ == "__main__":
    main()
