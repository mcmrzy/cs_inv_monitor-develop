"""Build CSERGY app and browser icons from the exported brand artwork."""

import argparse
import json
from pathlib import Path

from PIL import Image, ImageOps


ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "inv_app"
PUBLIC = ROOT / "inv-admin-frontend" / "public"
ANDROID = APP / "android" / "app" / "src" / "main" / "res"
IOS = APP / "ios" / "Runner" / "Assets.xcassets"
MACOS = APP / "macos" / "Runner" / "Assets.xcassets"


def read_logo(path):
    with Image.open(path) as source:
        logo = source.convert("RGBA")
    return logo.crop(logo.getbbox())


def centered_logo(logo, size, content_width, background=None):
    canvas = Image.new("RGBA", (size, size), background)
    mark = ImageOps.contain(
        logo, (content_width, content_width), Image.Resampling.LANCZOS
    )
    canvas.alpha_composite(mark, ((size - mark.width) // 2, (size - mark.height) // 2))
    return canvas.convert("RGB") if background else canvas


def save_png(image, path):
    image.save(path, optimize=True)


def write_app_iconset(iconset, icon):
    images = json.loads((iconset / "Contents.json").read_text(encoding="utf-8"))
    for entry in images["images"]:
        if "filename" in entry:
            points = float(entry["size"].split("x")[0])
            scale = int(entry["scale"].removesuffix("x"))
            size = round(points * scale)
            save_png(icon(size), iconset / entry["filename"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("export_dir", type=Path, help="Path to the CSERGY-AI-export directory")
    args = parser.parse_args()
    guide = args.export_dir / "brand-guide"
    zh_logo = read_logo(guide / "web-bilingual.png")
    en_logo = read_logo(guide / "product-horizontal.png")
    light_logo = read_logo(args.export_dir / "png" / "06-horizontal-bilingual-color-white.png")
    light_logo = ImageOps.contain(light_logo, (900, 240), Image.Resampling.LANCZOS)
    mark = read_logo(args.export_dir / "png" / "07-symbol-color.png")
    mark = ImageOps.contain(mark, (384, 384), Image.Resampling.LANCZOS)
    with Image.open(guide / "app-icon-store-1024.png") as source:
        app_master = source.convert("RGB")
    with Image.open(guide / "app-icon-maskable-1024.png") as source:
        maskable_master = source.convert("RGB")

    def app_icon(size):
        return app_master.resize((size, size), Image.Resampling.LANCZOS)

    def favicon(size):
        return centered_logo(mark, size, round(size * 0.93))

    images = APP / "assets" / "images"
    for path in (
        PUBLIC / "csergylogo.png",
        PUBLIC / "images" / "energy-flow" / "logo.png",
        PUBLIC.parent / "src" / "stores" / "csergylogo.png",
        images / "brand_name.png",
    ):
        save_png(zh_logo, path)
    save_png(en_logo, images / "brand_logo.png")
    save_png(light_logo, images / "brand_logo_light.png")
    save_png(light_logo, PUBLIC / "csergy-logo-light.png")
    save_png(mark, PUBLIC / "csergy-mark.png")
    save_png(app_icon(1024), images / "app_icon_master.png")
    with Image.open(guide / "app-icon.png") as source:
        rounded_app_icon = ImageOps.contain(source, (96, 96), Image.Resampling.LANCZOS)
        save_png(rounded_app_icon, PUBLIC / "csergy-app-icon.png")

    android_sizes = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    for density, size in android_sizes.items():
        save_png(app_icon(size), ANDROID / f"mipmap-{density}" / "ic_launcher.png")
    save_png(centered_logo(mark, 1024, 480), ANDROID / "drawable-nodpi" / "splash_logo_fg.png")
    one_tap_logo = centered_logo(mark, 192, 150)
    save_png(one_tap_logo, ANDROID / "drawable-xxhdpi" / "jverify_brand_logo.png")
    save_png(one_tap_logo, IOS / "jverify_brand_logo.imageset" / "jverify_brand_logo.png")

    write_app_iconset(IOS / "AppIcon.appiconset", app_icon)
    write_app_iconset(MACOS / "AppIcon.appiconset", app_icon)
    app_icon(256).save(
        APP / "windows" / "runner" / "resources" / "app_icon.ico",
        sizes=[(size, size) for size in (16, 32, 48, 64, 128, 256)],
    )

    favicon(48).save(PUBLIC / "favicon.ico", sizes=[(16, 16), (32, 32), (48, 48)])
    for size in (16, 32):
        save_png(favicon(size), PUBLIC / f"favicon-{size}x{size}.png")
    save_png(centered_logo(mark, 180, 132, "white"), PUBLIC / "apple-touch-icon.png")
    save_png(favicon(64), APP / "web" / "favicon.png")
    for size in (192, 512):
        save_png(app_icon(size), APP / "web" / "icons" / f"Icon-{size}.png")
        maskable = maskable_master.resize((size, size), Image.Resampling.LANCZOS)
        save_png(maskable, APP / "web" / "icons" / f"Icon-maskable-{size}.png")


if __name__ == "__main__":
    main()
