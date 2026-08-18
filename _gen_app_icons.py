# -*- coding: utf-8 -*-
r"""从 2048x2048 母图一键生成 App(Android/iOS) 与 Web 全套图标尺寸。

源图: C:\Users\29538\Pictures\csinv_app素材\app.png
输出:
  - inv_app/android/.../res/mipmap-*/ic_launcher.png  (48/72/96/144/192)
  - inv_app/ios/.../AppIcon.appiconset/*.png          (按 Contents.json)
  - inv-admin-frontend/public/favicon.ico 及配套 PNG
  - 母图存档 inv_app/assets/images/app_icon_master.png
"""
from pathlib import Path

from PIL import Image

ROOT = Path(r"d:\CS_APP_PROJECT\cs_inv_monitor-develop\cs_inv_monitor-develop")
SRC = Path(r"C:\Users\29538\Pictures\csinv_app素材\app.png")
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

# --- Web favicon（public/ 下的产物会随 Vite 构建拷贝到 dist/）---
src.save(PUBLIC / "favicon.ico", sizes=[(16, 16), (32, 32), (48, 48)])
save_png(px(32), PUBLIC / "favicon-32x32.png")
save_png(px(16), PUBLIC / "favicon-16x16.png")
save_png(px(180), PUBLIC / "apple-touch-icon.png")
print("OK web favicons ->", PUBLIC)

# --- 母图存档（降至 1024 并量化以满足仓库 512KB 限制；重新生成所需最大尺寸即 1024，
#     2048 原图保留在用户 Pictures 目录）---
save_png(px(1024), ARCHIVE)
print("OK", ARCHIVE)
print("ALL DONE")
