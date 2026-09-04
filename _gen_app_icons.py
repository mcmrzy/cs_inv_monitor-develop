# -*- coding: utf-8 -*-
r"""从 2048x2048 母图一键生成 App(Android/iOS) 与 Web 全套图标尺寸。

源图:
  - App 图标母图: C:\Users\29538\Pictures\csinv_app素材\app.png
  - Web 组合 logo: C:\Users\29538\Pictures\csinv_app素材\web.png (自动裁取符号区 favicon)
输出:
  - inv_app/android/.../res/mipmap-*/ic_launcher.png  (48/72/96/144/192)
  - inv_app/ios/.../AppIcon.appiconset/*.png          (按 Contents.json)
  - inv-admin-frontend/public/favicon.ico 及配套 PNG
  - 母图存档 inv_app/assets/images/app_icon_master.png
"""
from pathlib import Path

from PIL import Image

ROOT = Path(r"d:\CS_APP_PROJECT\cs_inv_monitor-develop\cs_inv_monitor-develop")
SRC = Path(r"C:\Users\29538\Pictures\csinv_app素材\app.png")  # App 图标母图
SRC_WEB = Path(r"C:\Users\29538\Pictures\csinv_app素材\web.png")  # Web 组合 logo
APPICON = ROOT / "inv_app" / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
RES = ROOT / "inv_app" / "android" / "app" / "src" / "main" / "res"
PUBLIC = ROOT / "inv-admin-frontend" / "public"
ARCHIVE = ROOT / "inv_app" / "assets" / "images" / "app_icon_master.png"

src = Image.open(SRC).convert("RGB")  # iOS App Store 图标不允许 alpha 通道

LIMIT = 500_000  # 仓库 pre-commit 限制单文件 512KB，留安全余量


def px(size: int) -> Image.Image:
    return src.resize((size, size), Image.LANCZOS)


def save_png(img: Image.Image, p: Path) -> None:
    """保存 PNG，超过仓库 512KB 限制时用减色量化 + 抖动压缩。"""
    img.save(p, "PNG", optimize=True)
    for colors in (256, 192, 128):
        if p.stat().st_size <= LIMIT:
            return
        img.quantize(
            colors=colors, method=Image.MEDIANCUT, dither=Image.FLOYDSTEINBERG
        ).save(p, "PNG", optimize=True)
    raise SystemExit(f"仍超 512KB 限制: {p} ({p.stat().st_size} bytes)")


# --- Android mipmap ic_launcher（manifest 仅引用 @mipmap/ic_launcher，无 roundIcon）---
ANDROID = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
for dpi, size in ANDROID.items():
    p = RES / f"mipmap-{dpi}" / "ic_launcher.png"
    save_png(px(size), p)
    print("OK", p)

# --- iOS AppIcon.appiconset（文件名与尺寸严格对应 Contents.json）---
IOS = {
    "Icon-App-20x20@1x.png": 20,
    "Icon-App-20x20@2x.png": 40,
    "Icon-App-20x20@3x.png": 60,
    "Icon-App-29x29@1x.png": 29,
    "Icon-App-29x29@2x.png": 58,
    "Icon-App-29x29@3x.png": 87,
    "Icon-App-40x40@1x.png": 40,
    "Icon-App-40x40@2x.png": 80,
    "Icon-App-40x40@3x.png": 120,
    "Icon-App-60x60@2x.png": 120,
    "Icon-App-60x60@3x.png": 180,
    "Icon-App-76x76@1x.png": 76,
    "Icon-App-76x76@2x.png": 152,
    "Icon-App-83.5x83.5@2x.png": 167,
    "Icon-App-1024x1024@1x.png": 1024,
}
for name, size in IOS.items():
    p = APPICON / name
    save_png(px(size), p)
    print("OK", p)

# --- Web favicon（源为组合 logo，自动裁取符号区、去掉底部文字，小尺寸才清晰）---
def web_symbol() -> Image.Image:
    """自底向上检测「文字块」并在其上方空白带处截断，保留立方体+房屋符号，
    置于留 8% 边距的正方形白底画布居中。"""
    img = Image.open(SRC_WEB).convert("RGB")
    w, h = img.size
    p = img.load()

    def content(x: int, y: int) -> bool:
        c = p[x, y]
        return (255 - c[0]) + (255 - c[1]) + (255 - c[2]) > 60

    TH = 60  # 行内容像素数阈值，区分文字/符号行与空白带
    rows = [sum(1 for x in range(w) if content(x, y)) for y in range(h)]
    y = h - 1
    while y >= 0 and rows[y] < TH:  # 跳过底部空白
        y -= 1
    while y >= 0 and rows[y] >= TH:  # 跳过文字块
        y -= 1
    sym_max = y
    while sym_max >= 0 and rows[sym_max] < TH:  # 收紧到符号实际末行
        sym_max -= 1
    # 逐行扫符号区 bbox，取 x 方向紧致边界
    xs = []
    for yy in range(sym_max + 1):
        for x in range(w):
            if content(x, yy):
                xs.append(x)
    sym = img.crop((min(xs), 0, max(xs) + 1, sym_max + 1))
    side = int(max(sym.size) / 0.84)  # 8% 边距
    canvas = Image.new("RGB", (side, side), (255, 255, 255))
    canvas.paste(sym, ((side - sym.width) // 2, (side - sym.height) // 2))
    print(f"symbol crop: box=({min(xs)},0,{max(xs) + 1},{sym_max + 1}), canvas={side}x{side}")
    return canvas


web = web_symbol()
web.save(PUBLIC / "favicon.ico", sizes=[(16, 16), (32, 32), (48, 48)])
save_png(web.resize((32, 32), Image.LANCZOS), PUBLIC / "favicon-32x32.png")
save_png(web.resize((16, 16), Image.LANCZOS), PUBLIC / "favicon-16x16.png")
save_png(web.resize((180, 180), Image.LANCZOS), PUBLIC / "apple-touch-icon.png")
print("OK web favicons ->", PUBLIC)

# --- 母图存档（降至 1024 并量化以满足仓库 512KB 限制；重新生成所需最大尺寸即 1024，
#     2048 原图保留在用户 Pictures 目录）---
save_png(px(1024), ARCHIVE)
print("OK", ARCHIVE)
print("ALL DONE")
