# -*- coding: utf-8 -*-
"""小烁抠图 v4：rembg(u2net) AI 语义分割 + GrabCut 融合（内容完整）+ 边缘精修 + halo消除
用法: python rembg_cutout.py [--test]  # --test 只处理 welcome 一张
"""
import os
import sys
import cv2
import numpy as np
from PIL import Image, ImageFilter
from rembg import remove, new_session
from scipy import ndimage

SRC = r"C:\Users\29538\Pictures\csinv_app美术素材"
ASSETS = r"C:\Users\29538\.qoder\worktree\cs_inv_monitor-develop\dpcN3z\inv_app\assets\character\xiaoshuo"

TASKS = {
    "xiaoshuo_welcome_1024.webp": ("xiaoshuo_welcome_1024.png", 1024),
    "xiaoshuo_station_1024.webp": ("xiaoshuo_station_1024.png", 1024),
    "xiaoshuo_offline_1024.webp": ("xiaoshuo_offline_1024.png", 1024),
    "xiaoshuo_device_1024.webp": ("xiaoshuo_device_1024.png", 1024),
    "xiaoshuo_empty_1024.webp": ("xiaoshuo_empty_1024.png", 1024),
    "xiaoshuo_reminder_1024.webp": ("xiaoshuo_reminder_1024.png", 1024),
    "xiaoshuo_success_1024.webp": ("xiaoshuo_success_1024.png", 1024),
    "xiaoshuo_warning_1024.webp": ("xiaoshuo_warning_1024.png", 1024),
    "xiaoshuo_ota_1536x1024.webp": ("xiaoshuo_ota_1536x1024.png", (1536, 1024)),
    "xiaoshuo_wifi_1536x1024.webp": ("xiaoshuo_wifi_1536x1024.png", (1536, 1024)),
}


def grabcut_mask(img):
    """GrabCut 语义分割 mask：对 Q 版角色内容完整（u2net 会丢身体，需融合）"""
    rgb = img.convert("RGB")
    arr = np.asarray(rgb)
    h, w = arr.shape[:2]
    mask = np.zeros((h, w), np.uint8)
    m = max(8, int(min(w, h) * 0.04))
    rect = (m, m, w - 2 * m, h - 2 * m)
    bgd = np.zeros((1, 65), np.float64)
    fgd = np.zeros((1, 65), np.float64)
    cv2.grabCut(arr, mask, rect, bgd, fgd, 5, cv2.GC_INIT_WITH_RECT)
    alpha = np.where((mask == 1) | (mask == 3), 255, 0).astype(np.uint8)
    # 内部空洞填充：不与边缘连通的近背景区域视为主体（白色工装/高光）
    bgmask = alpha < 128
    labels, n = ndimage.label(bgmask)
    edge_labels = set(labels[0, :]) | set(labels[-1, :]) | set(labels[:, 0]) | set(labels[:, -1])
    edge_labels.discard(0)
    alpha[bgmask & ~np.isin(labels, list(edge_labels))] = 255
    return alpha


def refine_alpha(rgba, min_alpha=16):
    """alpha 后处理：去孤立噪点（连通域保护）+ 轻微羽化"""
    a = np.asarray(rgba.getchannel("A"))
    # 小面积孤立前景块清理（<80px 的非主体块视为噪点）
    fg = a >= 128
    labels, n = ndimage.label(fg)
    if n > 0:
        sizes = ndimage.sum(fg, labels, range(1, n + 1))
        for lab in range(1, n + 1):
            if sizes[lab - 1] < 80:
                fg[labels == lab] = False
    # 背景连通域中的小洞清理
    bg = ~fg
    blabels, bn = ndimage.label(bg)
    if bn > 0:
        bsizes = ndimage.sum(bg, blabels, range(1, bn + 1))
        for lab in range(1, bn + 1):
            if bsizes[lab - 1] < 80:
                bg[blabels == lab] = False
    a2 = np.where(fg, 255, 0).astype(np.uint8)
    a = np.where(a2 == 255, 255, np.where(a >= min_alpha, a, 0))
    out = rgba.copy()
    out.putalpha(Image.fromarray(a, "L"))
    out = out.filter(ImageFilter.GaussianBlur(0.6))
    return out


def halo_fix(rgba):
    """非前景像素 RGB <- 最近前景像素色，消除半透明边缘的光晕/背景色污染"""
    a = np.asarray(rgba.getchannel("A"))
    arr = np.asarray(rgba.convert("RGB")).astype(np.float32)
    fg = a >= 200
    if fg.all():
        return rgba
    _, indices = ndimage.distance_transform_edt(~fg, return_indices=True)
    y_idx, x_idx = indices[0], indices[1]
    outside = ~fg
    arr[outside] = arr[y_idx[outside], x_idx[outside]]
    return Image.fromarray(np.dstack([arr.astype(np.uint8), a]), "RGBA")


def autocrop_content(img, pad_ratio=0.05):
    alpha = img.getchannel("A")
    bbox = alpha.getbbox()
    if bbox is None:
        return img
    w, h = img.size
    pad = int(max(w, h) * pad_ratio)
    x0 = max(0, bbox[0] - pad)
    y0 = max(0, bbox[1] - pad)
    x1 = min(w, bbox[2] + pad)
    y1 = min(h, bbox[3] + pad)
    cw, ch = x1 - x0, y1 - y0
    side = max(cw, ch)
    x0 = max(0, min(x0, w - side))
    y0 = max(0, min(y0, h - side))
    return img.crop((x0, y0, x0 + side, y0 + side))


def fit(img, size):
    img = img.convert("RGBA")
    if isinstance(size, int):
        size = (size, size)
    img.thumbnail(size, Image.LANCZOS)
    canvas = Image.new("RGBA", size, (0, 0, 0, 0))
    canvas.paste(img, ((size[0] - img.width) // 2, (size[1] - img.height) // 2), img)
    return canvas


def compose_halo_check(cut, bg=(21, 101, 192)):
    rgba = np.asarray(cut.convert("RGBA"), dtype=np.float32)
    a = rgba[..., 3:4] / 255.0
    out = rgba[..., :3] * a + np.array(bg, dtype=np.float32) * (1 - a)
    aa = rgba[..., 3]
    ring = (aa > 30) & (aa < 200)
    if not ring.any():
        return "no-ring"
    ys, xs = np.where(ring)
    rs = out[ys, xs, 0].astype(int)
    gs = out[ys, xs, 1].astype(int)
    bs = out[ys, xs, 2].astype(int)
    white = ((rs > 220) & (gs > 220) & (bs > 220)).mean() * 100
    return f"white={white:.1f}%"


def main():
    test_only = "--test" in sys.argv
    session = new_session("u2net")  # 模型在 U2NET_HOME 下
    tasks = {k: v for k, v in TASKS.items()
             if not test_only or k.startswith("xiaoshuo_welcome")}
    for out_name, (src, size) in tasks.items():
        src_path = os.path.join(SRC, src)
        if not os.path.exists(src_path):
            print(f"[SKIP] missing {src}")
            continue
        img = Image.open(src_path).convert("RGBA")
        img.thumbnail((1152, 1152), Image.LANCZOS)
        rb = remove(img, session=session)  # rembg AI 分割（边缘精细）
        rb = refine_alpha(rb)
        rb = halo_fix(rb)
        # 融合：GrabCut mask（内容完整）与 rembg alpha 取并集
        gc_a = grabcut_mask(img)
        rb_a = np.asarray(rb.getchannel("A"))
        fused_a = np.maximum(gc_a, rb_a).astype(np.uint8)
        cut = rb.copy()
        cut.putalpha(Image.fromarray(fused_a, "L"))
        cut = cut.filter(ImageFilter.GaussianBlur(0.4))
        check = compose_halo_check(cut)
        cut = autocrop_content(cut)
        out = fit(cut, size)
        dst = os.path.join(ASSETS, out_name)
        out.save(dst, "WEBP", quality=92, method=6)
        a = np.asarray(out.getchannel("A"))
        solid = np.count_nonzero(a == 255) * 100 // a.size
        print(f"[OK] {out_name} {out.size} solid={solid}% halo[{check}] -> {os.path.getsize(dst)} bytes")
    print("done")


if __name__ == "__main__":
    main()
