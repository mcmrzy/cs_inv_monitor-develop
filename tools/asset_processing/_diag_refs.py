# -*- coding: utf-8 -*-
"""综合诊断：图标引用 + 字体引用 + 背景图质量"""
import os
import re
import sys

sys.stdout.reconfigure(encoding="utf-8")

APP = r"C:\Users\29538\.qoder\worktree\cs_inv_monitor-develop\dpcN3z\inv_app"
names = [
    "battery", "energy_flow", "firmware", "grid", "inverter", "load",
    "monitoring", "power", "solar", "storage", "warning", "wifi",
]
pat = re.compile(r"['\"]([^'\"]*\.svg)['\"]")
hits = {}
for dp, dn, fns in os.walk(os.path.join(APP, "lib")):
    for fn in fns:
        if not fn.endswith(".dart"):
            continue
        p = os.path.join(dp, fn)
        with open(p, encoding="utf-8", errors="replace") as f:
            for i, line in enumerate(f, 1):
                for m in pat.finditer(line):
                    s = m.group(1)
                    if any(n in s for n in names):
                        hits.setdefault(s, []).append(f"{os.path.relpath(p, APP + os.sep + 'lib')}:{i}")

print("=== SVG 引用（含 battery/solar 等功能图标名）===")
for k, v in sorted(hits.items()):
    print(k, "->", v[:3])

print()
print("=== fontFamily / NotoSans 引用 ===")
for dp, dn, fns in os.walk(os.path.join(APP, "lib")):
    for fn in fns:
        if not fn.endswith(".dart"):
            continue
        p = os.path.join(dp, fn)
        with open(p, encoding="utf-8", errors="replace") as f:
            for i, line in enumerate(f, 1):
                if "NotoSans" in line or ("fontFamily" in line and "Noto" in line):
                    print(f"{os.path.relpath(p, APP + os.sep + 'lib')}:{i}: {line.strip()}")

print()
print("=== theme 文件字体设置 ===")
theme = os.path.join(APP, "lib", "core", "theme")
for fn in os.listdir(theme):
    if fn.endswith(".dart"):
        p = os.path.join(theme, fn)
        with open(p, encoding="utf-8", errors="replace") as f:
            for i, line in enumerate(f, 1):
                if "font" in line.lower():
                    print(f"{fn}:{i}: {line.strip()}")
