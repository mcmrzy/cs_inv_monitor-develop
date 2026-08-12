# -*- coding: utf-8 -*-
"""哈希对比：找重复资源文件 + 背景图内容差异"""
import os
import sys
import hashlib
from PIL import Image

sys.stdout.reconfigure(encoding="utf-8")

APP = r"C:\Users\29538\.qoder\worktree\cs_inv_monitor-develop\dpcN3z\inv_app"


def md5(p):
    return hashlib.md5(open(p, "rb").read()).hexdigest()


print("=== 小烁抠图哈希 ===")
chdir = os.path.join(APP, "assets", "character", "xiaoshuo")
hashes = {}
for f in sorted(os.listdir(chdir)):
    p = os.path.join(chdir, f)
    h = md5(p)
    hashes[f] = h
    print(f"{f}: {h[:12]}")

print()
print("=== 重复文件对 ===")
keys = list(hashes)
for i in range(len(keys)):
    for j in range(i + 1, len(keys)):
        if hashes[keys[i]] == hashes[keys[j]]:
            print(f"DUPLICATE: {keys[i]} == {keys[j]}")

print()
print("=== 背景图哈希 ===")
bgdir = os.path.join(APP, "assets", "images", "backgrounds")
bg_h = {}
for f in sorted(os.listdir(bgdir)):
    p = os.path.join(bgdir, f)
    bg_h[f] = md5(p)
    print(f"{f}: {bg_h[f][:12]} ({os.path.getsize(p)}B)")
for i, a in enumerate(sorted(bg_h)):
    for b in list(sorted(bg_h))[i + 1:]:
        if bg_h[a] == bg_h[b]:
            print(f"DUPLICATE BG: {a} == {b}")

print()
print("=== bg_splash 视觉信息（对比主仓库已提交版本）===")
# worktree 当前（被压缩后） vs 主仓库 HEAD（原始）
wt = os.path.join(APP, "assets", "images", "backgrounds", "bg_splash_xiaoshuo.webp")
main = r"d:\CS_APP_PROJECT\cs_inv_monitor-develop\cs_inv_monitor-develop\inv_app\assets\images\backgrounds\bg_splash_xiaoshuo.webp"
for label, p in [("worktree当前", wt), ("主仓库HEAD", main)]:
    if os.path.exists(p):
        im = Image.open(p)
        print(f"{label}: {im.size} {im.mode} {os.path.getsize(p)}B md5={md5(p)[:12]}")

print()
print("=== 图标 SVG 哈希（csergy 目录）===")
icdir = os.path.join(APP, "assets", "icons", "csergy")
ih = {}
for f in sorted(os.listdir(icdir)):
    if f.endswith(".svg"):
        ih[f] = md5(os.path.join(icdir, f))
for i, a in enumerate(sorted(ih)):
    for b in list(sorted(ih))[i + 1:]:
        if ih[a] == ih[b]:
            print(f"DUPLICATE SVG: {a} == {b}")
