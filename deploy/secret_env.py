"""Load deployment credentials from the git-ignored local secret store."""

from __future__ import annotations

import os
from pathlib import Path


def load_deploy_secrets() -> None:
    path = Path(__file__).resolve().parent / ".secrets" / "deploy.env"
    if not path.is_file():
        raise RuntimeError(f"missing deployment secret file: {path}")

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key, value)


def ssh_connect_kwargs() -> dict[str, str]:
    load_deploy_secrets()
    kwargs = {
        "hostname": os.environ["DEPLOY_HOST"],
        "username": os.environ["DEPLOY_USER"],
    }
    key = os.environ.get("DEPLOY_SSH_KEY", "").strip()
    if key:
        kwargs["key_filename"] = key
    else:
        kwargs["password"] = os.environ["DEPLOY_PASSWORD"]
    return kwargs


def sudo_stdin_password() -> str:
    load_deploy_secrets()
    return os.environ.get("DEPLOY_PASSWORD", "")
