#!/usr/bin/env python3
"""Resume a checked release archive over four bounded SSH upload streams."""
import argparse
import concurrent.futures
import hashlib
from pathlib import Path
import re
import shlex
import subprocess
import sys

CHUNK_SIZE = 2 * 1024 * 1024
REMOTE_PATTERN = re.compile(
    r"/opt/inv-mqtt/\.release-relay/[a-f0-9]{40}/"
    r"(?:inv-device-server|inv-api-server|inv-admin-frontend|app)/([a-f0-9]{64})"
)


def digest_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(CHUNK_SIZE), b""):
            digest.update(block)
    return digest.hexdigest()


def upload(path, remote_dir, host, identity):
    match = REMOTE_PATTERN.fullmatch(remote_dir)
    if match is None:
        raise ValueError("Invalid release upload directory")
    if not re.fullmatch(r"(?:[a-zA-Z0-9_][a-zA-Z0-9_.-]*@)?[a-zA-Z0-9][a-zA-Z0-9.-]*", host):
        raise ValueError("Invalid SSH host")
    if not path.is_file() or not identity.is_file():
        raise ValueError("Upload file and SSH identity must exist")
    size = path.stat().st_size
    if size <= 0 or (size + CHUNK_SIZE - 1) // CHUNK_SIZE > 1000000:
        raise ValueError("Invalid upload file size")
    archive_sha = digest_file(path)
    if archive_sha != match.group(1):
        raise ValueError("Archive digest does not match release upload directory")
    ssh = [
        "ssh", "-i", str(identity), "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=no",
        "-o", "ConnectTimeout=20", "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=4", host,
    ]
    q = shlex.quote

    def remote(command, data=None, timeout=240):
        try:
            result = subprocess.run(
                ssh + [command], input=data, stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL, timeout=timeout, check=False,
            )
            return result.returncode == 0
        except (subprocess.TimeoutExpired, OSError):
            return False

    def checked(pathname, digest):
        return "test -f {0} && printf '%s  %s\\n' {1} {0} | sha256sum -c - >/dev/null".format(
            q(pathname), q(digest)
        )

    payload = remote_dir + "/payload"
    if remote(checked(payload, archive_sha)):
        print("Verified archive already present", flush=True)
        return
    if not remote("set -eu; umask 077; mkdir -p " + q(remote_dir)):
        raise RuntimeError("Could not prepare release upload directory")
    count = (size + CHUNK_SIZE - 1) // CHUNK_SIZE

    def part(index):
        with path.open("rb") as source:
            source.seek(index * CHUNK_SIZE)
            data = source.read(CHUNK_SIZE)
        digest = hashlib.sha256(data).hexdigest()
        target = remote_dir + "/part-{:06d}".format(index)
        partial = target + ".partial"
        for attempt in range(3):
            if remote(checked(target, digest)):
                return index, "reused"
            command = "set -eu; umask 077; cat > {0}; {1}; mv {0} {2}".format(
                q(partial), checked(partial, digest), q(target)
            )
            if remote(command, data=data):
                return index, "uploaded"
        raise RuntimeError("Chunk {} failed after three attempts".format(index + 1))

    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        futures = [pool.submit(part, index) for index in range(count)]
        completed = 0
        try:
            for future in concurrent.futures.as_completed(futures):
                index, state = future.result()
                completed += 1
                print("Chunk {}/{} {}; completed {}/{}".format(index + 1, count, state, completed, count), flush=True)
        except Exception:
            for future in futures:
                future.cancel()
            raise
    command = (
        "set -eu; umask 077; directory={directory}; index=0; "
        "while [ \"$index\" -lt {count} ]; do "
        "part=$(printf 'part-%06d' \"$index\"); cat \"$directory/$part\"; "
        "index=$((index + 1)); done > {partial}; {verify}; mv {partial} {payload}"
    ).format(
        directory=q(remote_dir), count=count, partial=q(payload + ".partial"),
        verify=checked(payload + ".partial", archive_sha), payload=q(payload),
    )
    if not remote(command, timeout=300):
        raise RuntimeError("Archive assembly or digest verification failed; verified chunks retained")
    print("Archive reassembled and SHA-256 verified", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--file", required=True, type=Path)
    parser.add_argument("--remote-dir", required=True)
    parser.add_argument("--host", required=True)
    parser.add_argument("--identity", required=True, type=Path)
    args = parser.parse_args()
    try:
        upload(args.file, args.remote_dir, args.host, args.identity)
    except (ValueError, RuntimeError) as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
