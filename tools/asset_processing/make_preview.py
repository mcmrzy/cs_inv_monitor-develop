# -*- coding: utf-8 -*-
"""生成去底验收对比图（2x2 网格）+ 白边残留检查"""
import os
from PIL import Image

SRC = r"C:\Users\29538\Pictures\csinv_app美术素材"
OUT = os.path.join(SRC, "processed")
PV = os.path.join(OUT, "preview_compare")

FILES = [
    "xiaoshuo_welcome_1024.png",
    "xiaoshuo_device_1024.png",
    "empty_station_720.png",
    "avatar_default_512.png",
]


def check_halo(p):
    """检查半透明边缘像素是否偏白（白边残留）"""
    with Image.open(p) as im:
        rgba = im.convert("RGBA")
        px = rgba.load()
        w, h = im.size
        step = max(1, w // 400)
        white_edge = total_edge = 0
        for x in range(0, w, step):
            for y in range(0, h, step):
                al = px[x, y][3]
                if 5 <= al <= 120:
                    total_edge += 1
                    r, g, b, _ = px[x, y]
                    if r > 225 and g > 225 and b > 225:
                        white_edge += 1
        return white_edge, total_edge


def main():
    os.makedirs(PV, exist_ok=True)
    for f in FILES:
        src = Image.open(os.path.join(SRC, f)).convert("RGB")
        out = Image.open(os.path.join(OUT, f)).convert("RGBA")
        src_t = src.copy()
        src_t.thumbnail((360, 360), Image.LANCZOS)
        out_t = out.copy()
        out_t.thumbnail((360, 360), Image.LANCZOS)

        blue = Image.new("RGB", out_t.size, (21, 101, 192))
        blue.paste(out_t, (0, 0), out_t)
        dark = Image.new("RGB", out_t.size, (45, 50, 60))
        dark.paste(out_t, (0, 0), out_t)

        cell = 360
        grid = Image.new("RGB", (cell * 2 + 6, cell * 2 + 6), (240, 240, 240))

        def put(im, x, y):
            grid.paste(im.convert("RGB"), (x * (cell + 3), y * (cell + 3)))

        put(src_t, 0, 0)
        put(out_t, 1, 0)
        put(blue, 0, 1)
        put(dark, 1, 1)
        grid.save(os.path.join(PV, f.replace(".png", "_compare.png")))
        we, te = check_halo(os.path.join(OUT, f))
        rate = we / te * 100 if te else 0
        print(f"{f:35s} 半透明边缘={te} 偏白={we} 白边率={rate:.1f}%")
    print("验收图已存:", PV)


if __name__ == "__main__":
    main()
