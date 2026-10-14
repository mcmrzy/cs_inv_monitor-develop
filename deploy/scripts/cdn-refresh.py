#!/usr/bin/env python3
"""通过 CDN OpenAPI（cdn.aliyuncs.com）刷新对象缓存，用于 ESA 域名无法直连时的兜底。"""
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

ENDPOINT = "https://cdn.aliyuncs.com"
VERSION = "2018-05-10"  # CDN classic API


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def pe(s: str) -> str:
    return urllib.parse.quote(str(s), safe="-_.~")


def call(action: str, query: dict[str, str]) -> dict:
    ak = os.environ["ALIYUN_ACCESS_KEY_ID"].strip()
    sk = os.environ["ALIYUN_ACCESS_KEY_SECRET"].strip()
    host = urllib.parse.urlparse(ENDPOINT).netloc
    q = dict(query)
    q.setdefault("Format", "JSON")
    cqs = "&".join(f"{pe(k)}={pe(v)}" for k, v in sorted(q.items()))
    headers = {
        "host": host,
        "x-acs-action": action,
        "x-acs-content-sha256": sha256_hex(b""),
        "x-acs-date": utc_now(),
        "x-acs-signature-nonce": str(uuid.uuid4()),
        "x-acs-version": VERSION,
    }
    sh = sorted(headers)
    ch = "".join(f"{k}:{headers[k]}\n" for k in sh)
    shs = ";".join(sh)
    cre = "\n".join(["POST", "/", cqs, ch, shs, sha256_hex(b"")])
    sts = "ACS3-HMAC-SHA256\n" + sha256_hex(cre.encode())
    sig = hmac.new(sk.encode(), sts.encode(), hashlib.sha256).hexdigest()
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
            f"SignedHeaders={shs},Signature={sig}"
        ),
    }
    req = urllib.request.Request(
        f"{ENDPOINT}/?{cqs}", data=b"", headers=http_headers, method="POST"
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
            return json.loads(raw) if raw.strip() else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", errors="replace")
        raise SystemExit(f"CDN HTTP {e.code}: {detail}") from e
    except urllib.error.URLError as e:
        raise SystemExit(f"CDN 网络错误: {e.reason}") from e


def main() -> None:
    for key in ("ALIYUN_ACCESS_KEY_ID", "ALIYUN_ACCESS_KEY_SECRET"):
        if not os.environ.get(key):
            sys.exit(f"缺少 {key}")
    host = os.environ.get("ESA_REFRESH_HOST", "download.jiuxiaoyw.online").strip()
    host = host.removeprefix("https://").removeprefix("http://").split("/")[0]
    paths = "\n".join(
        [
            f"https://{host}/app-release-info",
            f"https://{host}/api/v1/ota/app/latest",
        ]
    )
    print(f"CDN RefreshObjectCaches host={host}")
    print(paths)
    print(
        json.dumps(
            call(
                "RefreshObjectCaches",
                {"ObjectPath": paths, "ObjectType": "File"},
            ),
            ensure_ascii=False,
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
