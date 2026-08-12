# -*- coding: utf-8 -*-
"""仅起 HTTP 服务（供 Chrome 截图）"""
import http.server
import socketserver
import os

ROOT = r"C:\Users\29538\.qoder\worktree\cs_inv_monitor-develop\dpcN3z\inv_app\assets\icons"
PORT = 18766

class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=ROOT, **kw)
    def log_message(self, *a):
        pass

with socketserver.TCPServer(("127.0.0.1", PORT), Handler) as httpd:
    print(f"SERVING {PORT}", flush=True)
    httpd.serve_forever()
