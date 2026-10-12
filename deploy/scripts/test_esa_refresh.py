import importlib.util
import json
import os
from pathlib import Path
import unittest
from unittest.mock import patch

SCRIPT_DIR = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("esa_refresh", SCRIPT_DIR / "esa-refresh.py")
esa_refresh = importlib.util.module_from_spec(spec)
spec.loader.exec_module(esa_refresh)


class DownloadReleaseTests(unittest.TestCase):
    def test_refresh_uses_supported_file_quota_and_known_query_urls(self):
        with patch.dict(os.environ, {"ALIYUN_ACCESS_KEY_ID": "test", "ALIYUN_ACCESS_KEY_SECRET": "test", "ESA_SITE_ID": "1"}), patch.object(esa_refresh, "call_esa", return_value={}) as api:
            esa_refresh.main()
        action, query = api.call_args.args
        self.assertEqual(action, "PurgeCaches")
        self.assertEqual(query["Type"], "file")
        files = json.loads(query["Content"])["Files"]
        self.assertIn("https://download.jiuxiaoyw.online/download.html", files)
        self.assertIn("https://download.jiuxiaoyw.online/app-release-info?platform=android", files)

    def test_download_entry_uses_independent_html_and_no_store(self):
        config = (SCRIPT_DIR.parent / "nginx-proxy.conf").read_text(encoding="utf-8")
        download_server = config.split("# ---------- download：")[1].split("# ---------- emqx：")[0]
        entry = download_server.split("location = /download {")[1].split("\n    }")[0]
        self.assertIn("proxy_pass http://inv-admin-frontend:8080/download.html;", entry)
        self.assertIn('Cache-Control "no-store', entry)
        self.assertIn("location = /download.html", download_server)


if __name__ == "__main__":
    unittest.main()
