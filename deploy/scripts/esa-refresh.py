#!/usr/bin/env python3
"""强制刷新阿里云 ESA 边缘缓存（纯标准库，不依赖 Go/SDK）。

用法（在能访问 esa.aliyuncs.com 的服务器上）：

  export ALIYUN_ACCESS_KEY_ID='LTAI...'
  export ALIYUN_ACCESS_KEY_SECRET='...'   # 真实 Secret，不要写 <占位符>
  export ESA_SITE_ID='172343211966680'
  python3 deploy/scripts/esa-refresh.py

只列站点：
  ESA_LIST_SITES=1 python3 deploy/scripts/esa-refresh.py

注意：ESA 2024-09-10 刷新接口是 PurgeCaches（不是旧 CDN 的 RefreshESAObjectCaches）。
"""

from __future__ import annotations

import datetime as dt
import hashlib
import hmac
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid

ENDPOINT = os.environ.get("ESA_ENDPOINT", "https://esa.aliyuncs.com")
VERSION = "2024-09-10"
DEFAULT_PATHS = (
    "/app-release-info",
    "/api/v1/ota/app/latest",
)


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def percent_encode(s: str) -> str:
    # Aliyun ACS 编码：RFC3986，保留 - _ . ~
    return urllib.parse.quote(str(s), safe="-_.~")


def call_esa(action: str, query: dict[str, str]) -> dict:
    ak = os.environ["ALIYUN_ACCESS_KEY_ID"].strip()
    sk = os.environ["ALIYUN_ACCESS_KEY_SECRET"].strip()
    host = urllib.parse.urlparse(ENDPOINT).netloc

    query = dict(query)
    query.setdefault("Format", "JSON")

    canonical_qs = "&".join(
        f"{percent_encode(k)}={percent_encode(v)}" for k, v in sorted(query.items())
    )

    headers = {
        "host": host,
        "x-acs-action": action,
        "x-acs-content-sha256": sha256_hex(b""),
        "x-acs-date": utc_now(),
        "x-acs-signature-nonce": str(uuid.uuid4()),
        "x-acs-version": VERSION,
    }
    signed_headers = sorted(headers)
    canonical_headers = "".join(f"{k}:{headers[k]}\n" for k in signed_headers)
    signed_header_str = ";".join(signed_headers)

    canonical_request = "\n".join(
        ["POST", "/", canonical_qs, canonical_headers, signed_header_str, sha256_hex(b"")]
    )
    string_to_sign = "ACS3-HMAC-SHA256\n" + sha256_hex(canonical_request.encode("utf-8"))
    signature = hmac.new(sk.encode("utf-8"), string_to_sign.encode("utf-8"), hashlib.sha256).hexdigest()

    http_headers = {
        "Host": host,
        "x-acs-action": action,
        "x-acs-content-sha256": headers["x-acs-content-sha256"],
        "x-acs-date": headers["x-acs-date"],
        "x-acs-signature-nonce": headers["x-acs-signature-nonce"],
        "x-acs-version": VERSION,
        "Accept": "application/json",
        "Authorization": (
            f"ACS3-HMAC-SHA256 Credential={ak},"
            f"SignedHeaders={signed_header_str},"
            f"Signature={signature}"
        ),
    }

    url = f"{ENDPOINT.rstrip('/')}/?{canonical_qs}"
    req = urllib.request.Request(url, data=b"", headers=http_headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
            return json.loads(raw) if raw.strip() else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", errors="replace")
        raise SystemExit(f"ESA HTTP {e.code}: {detail}") from e
    except urllib.error.URLError as e:
        raise SystemExit(f"ESA 网络错误: {e.reason}") from e


def main() -> None:
    for key in ("ALIYUN_ACCESS_KEY_ID", "ALIYUN_ACCESS_KEY_SECRET"):
        if not os.environ.get(key):
            sys.exit(f"缺少环境变量 {key}")

    if os.environ.get("ESA_LIST_SITES") == "1":
        print(json.dumps(call_esa("ListSites", {"PageSize": "50"}), ensure_ascii=False, indent=2))
        return

    site_id = os.environ.get("ESA_SITE_ID", "").strip()
    if not site_id:
        sys.exit("缺少环境变量 ESA_SITE_ID")

    host = os.environ.get("ESA_REFRESH_HOST", "download.jiuxiaoyw.online").strip()
    host = host.removeprefix("https://").removeprefix("http://").split("/")[0]
    # ignoreParams：去掉 query 后匹配，覆盖 ?platform=android 等变体。
    ignore_urls = [f"https://{host}{p}" for p in DEFAULT_PATHS]
    content = json.dumps({"IgnoreParams": ignore_urls}, ensure_ascii=False)

    print(f"SiteId={site_id}")
    print("刷新目标（ignoreParams，去参数后匹配）:")
    for line in ignore_urls:
        print(f"  {line}")

    result = call_esa(
        "PurgeCaches",
        {
            "Type": "ignoreParams",
            "Content": content,
            "SiteId": site_id,
            "Force": "true",
        },
    )
    print(json.dumps(result, ensure_ascii=False, indent=2))
    print("已提交刷新任务（边缘通常数秒到数分钟生效）")


if __name__ == "__main__":
    main()
