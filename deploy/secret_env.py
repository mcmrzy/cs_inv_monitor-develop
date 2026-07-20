"""Load deployment credentials from the git-ignored local secret store."""

from __future__ import annotations

import os
from pathlib import Path


def load_deploy_secrets() -> None:
    configured = os.environ.get("DEPLOY_SECRET_FILE", "").strip()
    path = Path(configured) if configured else Path(__file__).resolve().parent / ".secrets" / "deploy.env"
    if not path.is_file():
        if os.environ.get("DEPLOY_HOST") and os.environ.get("DEPLOY_USER"):
            return
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
        kwargs["password"] = required_secret("DEPLOY_PASSWORD")
    return kwargs


def sudo_stdin_password() -> str:
    load_deploy_secrets()
    name = "DEPLOY_SUDO_PASSWORD" if os.environ.get("DEPLOY_SUDO_PASSWORD") else "DEPLOY_PASSWORD"
    return required_secret(name)


def required_secret(name: str) -> str:
    load_deploy_secrets()
    value = os.environ.get(name, "").strip()
    if not value or value.upper().startswith(("CHANGE_ME", "REMOVED", "REDACTED")):
        raise RuntimeError(f"{name} must be provided by the deployment secret store")
    return value
