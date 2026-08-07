# -*- coding: utf-8 -*-
"""列出 processed 目录成品清单"""
import os
from PIL import Image

D = r"C:\Users\29538\Pictures\csinv_app美术素材\processed"


def main():
    items = []
    for f in sorted(os.listdir(D)):
        p = os.path.join(D, f)
        if os.path.isdir(p):
            continue
        with Image.open(p) as im:
            items.append(
                (f, f"{im.size[0]}x{im.size[1]}", im.mode, f"{os.path.getsize(p)/1024:.0f}KB")
            )
    print(f"{'文件':38s} {'尺寸':12s} {'模式':5s} 体积")
    for name, size, mode, kb in items:
        print(f"{name:38s} {size:12s} {mode:5s} {kb}")
    print()
    print("共", len(items), "个文件")


if __name__ == "__main__":
    main()
