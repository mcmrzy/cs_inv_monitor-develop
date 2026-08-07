# -*- coding: utf-8 -*-
"""CSERGY App 美术素材批量处理脚本
- 白底去底（ImageChops 向量化，软边缘羽化）
- 智能裁切（方形 / 竖版）
- 缩放 + RGBA WebP 转换
用法: python process_images.py <task>
task: preview | full
"""
import os
import sys
import numpy as np
from scipy import ndimage
from PIL import Image, ImageFilter

SRC = r"C:\Users\29538\Pictures\csinv_app美术素材"
OUT = os.path.join(SRC, "processed")


def detect_bg_color(img):
    """边缘 4% 区域采样（上下边中位数近似背景色）"""
    rgb = img.convert("RGB")
    w, h = rgb.size
    m = int(min(w, h) * 0.04)
    box = rgb.crop((0, 0, w, m)).resize((1, 1))
    top = box.getpixel((0, 0))
    box = rgb.crop((0, h - m, w, h)).resize((1, 1))
    bot = box.getpixel((0, 0))
    return tuple((top[i] + bot[i]) // 2 for i in range(3))


# ---------- 连通域 flood-fill 去底 ----------
def remove_bg_connected(img, bg, dist_thresh=38, feather=2):
    """
    只删除与图像边缘连通的"近背景色"区域：
    - 渐变/光晕背景与边缘连通 → 整块删除
    - 人物内部的白色高光/白字被前景包围 → 保留
    - 边缘 feather 像素羽化过渡
    """
    rgb = img.convert("RGB")
    arr = np.asarray(rgb, dtype=np.int16)
    bgc = np.array(bg, dtype=np.int16)
    dist = np.max(np.abs(arr - bgc), axis=2)  # Chebyshev 距离
    bgmask = dist < dist_thresh

    # 连通域标记，只保留接触边缘的连通域作为背景
    labels, n = ndimage.label(bgmask)
    h, w = bgmask.shape
    edge_labels = set(labels[0, :]) | set(labels[-1, :]) | set(labels[:, 0]) | set(labels[:, -1])
    edge_labels.discard(0)
    bg_conn = np.isin(labels, list(edge_labels))

    # 羽化：背景区域膨胀 feather 像素做渐变过渡
    alpha = np.full((h, w), 255, dtype=np.uint8)
    bg_eroded = ndimage.binary_erosion(bg_conn, iterations=feather)
    alpha[bg_eroded] = 0
    # 膨胀环（feather 宽度）半透明渐变
    for i in range(feather - 1, -1, -1):
        ring = bg_conn & ~ndimage.binary_erosion(bg_conn, iterations=i + 1)
        alpha[ring] = int(255 * (i + 0.5) / feather)

    rgba = rgb.convert("RGBA")
    rgba.putalpha(Image.fromarray(alpha))
    return rgba


# ---------- 智能裁切 ----------
def autocrop_center(img, target_ratio):
    """中心裁切到目标宽高比"""
    w, h = img.size
    cur = w / h
    if abs(cur - target_ratio) < 0.01:
        return img
    if cur > target_ratio:  # 太宽 → 裁宽
        nw = int(h * target_ratio)
        x0 = (w - nw) // 2
        return img.crop((x0, 0, x0 + nw, h))
    nh = int(w / target_ratio)
    y0 = (h - nh) // 2
    return img.crop((0, y0, w, y0 + nh))


def autocrop_content(img, pad_ratio=0.05):
    """按 alpha 内容包围盒裁切到正方形（去底后使用）"""
    rgba = img.convert("RGBA")
    alpha = rgba.getchannel("A")
    bbox = alpha.getbbox()
    if bbox is None:
        return img
    w, h = rgba.size
    pad = int(max(w, h) * pad_ratio)
    x0 = max(0, bbox[0] - pad)
    y0 = max(0, bbox[1] - pad)
    x1 = min(w, bbox[2] + pad)
    y1 = min(h, bbox[3] + pad)
    cw, ch = x1 - x0, y1 - y0
    side = max(cw, ch)
    x0 = max(0, min(x0, w - side))
    y0 = max(0, min(y0, h - side))
    return rgba.crop((x0, y0, x0 + side, y0 + side))


def fit(img, size):
    """等比缩放（不拉伸）到 <= size，然后居中填充到目标画布（透明填充）
    size: int（方形）或 (w, h) 元组
    """
    img = img.convert("RGBA")
    if isinstance(size, int):
        size = (size, size)
    img.thumbnail(size, Image.LANCZOS)
    canvas = Image.new("RGBA", size, (0, 0, 0, 0))
    canvas.paste(img, ((size[0] - img.width) // 2, (size[1] - img.height) // 2), img)
    return canvas


def save_webp(img, path, quality=100):
    img.convert("RGBA").save(path, "WEBP", quality=quality, method=6)


# ---------- 任务定义 ----------
TRANSPARENT_TASKS = {
    "xiaoshuo_welcome_1024.webp": ("xiaoshuo_welcome_1024.png", 1024, True),
    "xiaoshuo_station_1024.webp": ("xiaoshuo_station_1024.png", 1024, True),
    "xiaoshuo_offline_1024.webp": ("xiaoshuo_offline_1024.png", 1024, True),
    "xiaoshuo_device_1024.webp": ("xiaoshuo_device_1024.png", 1024, True),
    "xiaoshuo_empty_1024.webp": ("xiaoshuo_empty_1024.png", 1024, True),
    "xiaoshuo_reminder_1024.webp": ("xiaoshuo_reminder_1024.png", 1024, True),
    "xiaoshuo_success_1024.webp": ("xiaoshuo_success_1024.png", 1024, True),
    "xiaoshuo_warning_1024.webp": ("xiaoshuo_warning_1024.png", 1024, True),
    "xiaoshuo_ota_1536x1024.webp": ("xiaoshuo_ota_1536x1024.png", (1536, 1024), False),
    "xiaoshuo_wifi_1536x1024.webp": ("xiaoshuo_wifi_1536x1024.png", (1536, 1024), False),
    "avatar_default_512.webp": ("avatar_default_512.png", 512, True),
    "empty_station_720.webp": ("empty_station_720.png", 720, False),
    "empty_device_720.webp": ("empty_device_720.png", 720, False),
    "empty_alarm_720.webp": ("empty_alarm_720.png", 720, False),
    "empty_record_720.webp": ("empty_record_720.png", 720, False),
}

BG_TASKS = {
    "bg_auth_abstract.png": ("bg_auth_abstract.png", (1080, 2340)),
    "bg_splash_xiaoshuo.png": ("bg_splash_xiaoshuo.png", (1440, 3200)),
    "bg_jverify_xiaoshuo.png": ("bg_jverify_xiaoshuo.png", (1080, 2340)),
}

RGB_TASKS = {
    "brand_showcase_1600x900.webp": ("brand_showcase_1600x900.png", (1600, 900)),
    "csergy_inverter_product_master_2048.png": (
        "csergy_inverter_product_master_2048.png",
        (2048, 2048),
    ),
    "csergy_inverter_product_card_800.webp": (
        "csergy_inverter_product_card_800.png",
        (800, 800),
    ),
}


def run_preview():
    os.makedirs(OUT, exist_ok=True)
    files = [
        ("xiaoshuo_welcome_1024.png", "xiaoshuo_welcome_1024.png", 1024, True),
        ("xiaoshuo_device_1024.png", "xiaoshuo_device_1024.png", 1024, True),
        ("empty_station_720.png", "empty_station_720.png", 720, False),
        ("avatar_default_512.png", "avatar_default_512.png", 512, True),
    ]
    for src, name, size, content_crop in files:
        p = os.path.join(SRC, src)
        img = Image.open(p)
        bg = detect_bg_color(img)
        print(f"[preview] {src} 背景色={bg}")
        cut = remove_bg_connected(img, bg=bg)
        if content_crop:
            cut = autocrop_content(cut)
        out = fit(cut, size)
        save_webp(out, os.path.join(OUT, name))
        print(f"[preview] -> {name} {out.size} {out.mode}")


def run_full():
    os.makedirs(OUT, exist_ok=True)
    for out_name, (src, size, content_crop) in TRANSPARENT_TASKS.items():
        p = os.path.join(SRC, src)
        if not os.path.exists(p):
            print(f"[SKIP] 缺源文件 {src}")
            continue
        img = Image.open(p)
        bg = detect_bg_color(img)
        cut = remove_bg_connected(img, bg=bg)
        if content_crop:
            cut = autocrop_content(cut)
        out = fit(cut, size)
        save_webp(out, os.path.join(OUT, out_name))
        print(f"[OK] {out_name} {out.size} {out.mode}")
    for out_name, (src, (tw, th)) in BG_TASKS.items():
        p = os.path.join(SRC, src)
        if not os.path.exists(p):
            print(f"[SKIP] 缺源文件 {src}")
            continue
        img = Image.open(p)
        cut = autocrop_center(img, tw / th)
        cut = cut.resize((tw, th), Image.LANCZOS)
        cut.convert("RGB").save(os.path.join(OUT, out_name), "PNG")
        print(f"[OK] {out_name} {cut.size}")
    for out_name, (src, (tw, th)) in RGB_TASKS.items():
        p = os.path.join(SRC, src)
        if not os.path.exists(p):
            print(f"[SKIP] 缺源文件 {src}")
            continue
        img = Image.open(p)
        img = img.resize((tw, th), Image.LANCZOS)
        if out_name.endswith(".webp"):
            save_webp(img, os.path.join(OUT, out_name))
        else:
            img.convert("RGB").save(os.path.join(OUT, out_name), "PNG")
        print(f"[OK] {out_name} {img.size}")
    print("全部完成。")


if __name__ == "__main__":
    task = sys.argv[1] if len(sys.argv) > 1 else "preview"
    if task == "preview":
        run_preview()
    else:
        run_full()
