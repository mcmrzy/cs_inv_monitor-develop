# -*- coding: utf-8 -*-
"""修复导航图标 SVG：
1. nav_porfile_* → nav_profile_*（对齐代码中的资产名）
2. 补 viewBox（flutter_svg 依赖）
3. 删除背景矩形 path（会被 ColorFilter 染成实心色块）
输出到 processed/nav_icons/
"""
import os
import re

SRC = r"C:\Users\29538\Pictures\csinv_app美术素材"
OUT = os.path.join(SRC, "processed", "nav_icons")

RENAME = {
    "nav_porfile_normal.svg": "nav_profile_normal.svg",
    "nav_porfile_active.svg": "nav_profile_active.svg",
}


def fix_svg(text, fname):
    """返回 (修正后文本, 修改说明列表)"""
    notes = []
    # 1) viewBox
    if "viewBox" not in text:
        m = re.search(r'<svg[^>]*width="(\d+)"[^>]*height="(\d+)"', text)
        if not m:
            m = re.search(r'<svg[^>]*height="(\d+)"[^>]*width="(\d+)"', text)
        if m:
            w, h = m.group(1), m.group(2)
            text = text.replace("<svg", f'<svg viewBox="0 0 {w} {h}"', 1)
            notes.append(f"补 viewBox 0 0 {w} {h}")
        else:
            notes.append("!! 未找到 width/height，viewBox 未补")
    # 2) 删除背景矩形：第一个 path，d 以 M0 0 开头，transform=translate(0,0)
    lines = text.splitlines()
    out_lines = []
    removed = 0
    for i, ln in enumerate(lines):
        if removed == 0 and "<path" in ln and 'd="M0 0' in ln and 'translate(0,0)' in ln:
            removed += 1
            notes.append(f"删除背景矩形 path (行{i + 1})")
            continue
        out_lines.append(ln)
    return "\n".join(out_lines), notes


def main():
    os.makedirs(OUT, exist_ok=True)
    for f in sorted(os.listdir(SRC)):
        if not f.endswith(".svg"):
            continue
        src_path = os.path.join(SRC, f)
        with open(src_path, "r", encoding="utf-8") as fh:
            text = fh.read()
        fixed, notes = fix_svg(text, f)
        out_name = RENAME.get(f, f)
        with open(os.path.join(OUT, out_name), "w", encoding="utf-8") as fh:
            fh.write(fixed)
        print(f"{f:32s} -> {out_name:32s} {'; '.join(notes) if notes else '(无修改)'}")
    print("SVG 修复完成:", OUT)


if __name__ == "__main__":
    main()
