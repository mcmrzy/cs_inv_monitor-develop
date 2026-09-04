# -*- coding: utf-8 -*-
"""生成 SVG 预览 HTML（24 个图标）"""
import os

d = r"C:\Users\29538\.qoder\worktree\cs_inv_monitor-develop\dpcN3z\inv_app\assets\icons\csergy"
files = sorted(f for f in os.listdir(d) if f.endswith(".svg"))
cells = []
for f in files:
    url = "file:///" + d.replace("\\", "/") + "/" + f
    cells.append(
        f'<div style="display:inline-block;text-align:center;margin:10px;'
        f'border:1px solid #ccc;padding:8px;border-radius:8px">'
        f'<img src="{url}" width="48" height="48" style="background:#f5f7fa">'
        f'<div style="font-size:10px;color:#666;max-width:140px;word-break:break-all">{f}</div></div>'
    )
html = (
    '<html><body style="background:#fff;font-family:sans-serif">'
    f"<h3>CSERGY SVG Icons ({len(files)})</h3>{chr(10).join(cells)}"
    "</body></html>"
)
out = os.path.join(os.environ["TEMP"], "_svg_preview.html")
with open(out, "w", encoding="utf-8") as fp:
    fp.write(html)
print("html written:", out, "files:", len(files))
