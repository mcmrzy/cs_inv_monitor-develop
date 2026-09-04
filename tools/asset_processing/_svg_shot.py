# -*- coding: utf-8 -*-
"""起本地 HTTP 服务并 Chrome 截图预览 SVG（file:// 下 SVG img 加载不可靠）"""
import http.server
import socketserver
import threading
import subprocess
import os
import time

ROOT = r"C:\Users\29538\.qoder\worktree\cs_inv_monitor-develop\dpcN3z\inv_app\assets\icons"
PORT = 18765

html = """<html><body style="background:#fff;font-family:sans-serif">
<h3>CSERGY SVG Icons: row1 gray#555 / row2 blue#0D47A1 / row3 blue#1565C0</h3>
{body}
</body></html>"""

files = sorted(f for f in os.listdir(os.path.join(ROOT, "csergy")) if f.endswith(".svg"))
cells = []
for f in files:
    cells.append(
        f'<div style="display:inline-block;text-align:center;margin:8px;'
        f'border:1px solid #ccc;padding:8px;border-radius:8px">'
        f'<div style="font-size:10px;color:#666">{f}</div>'
        f'<div style="margin-top:4px"><img src="csergy/{f}" width="40" height="40" style="background:#f5f7fa;color:#555"></div>'
        f'<div style="margin-top:2px"><img src="csergy/{f}" width="40" height="40" style="background:#eef3fb;color:#0D47A1"></div>'
        f'<div style="margin-top:2px"><img src="csergy/{f}" width="40" height="40" style="background:#fafafa;color:#1565C0"></div>'
        f'</div>'
    )
with open(os.path.join(ROOT, "_preview.html"), "w", encoding="utf-8") as fp:
    fp.write(html.format(body="\n".join(cells)))
print("preview html:", os.path.join(ROOT, "_preview.html"))

class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=ROOT, **kw)
    def log_message(self, *a):
        pass

httpd = socketserver.TCPServer(("127.0.0.1", PORT), Handler)
t = threading.Thread(target=httpd.serve_forever, daemon=True)
t.start()
time.sleep(1)
chrome = r"C:\Users\29538\AppData\Local\ms-playwright\chromium-1228\chrome-win64\chrome.exe"
shot = r"C:\Users\29538\AppData\Local\Temp\_svg_http.png"
subprocess.run(
    [chrome, "--headless=new", "--no-sandbox", "--disable-gpu", "--hide-scrollbars",
     "--window-size=1440,1500", f"--screenshot={shot}",
     f"http://127.0.0.1:{PORT}/_preview.html"],
    capture_output=True, timeout=60,
)
httpd.shutdown()
print("shot:", shot, os.path.getsize(shot) if os.path.exists(shot) else "MISSING")
