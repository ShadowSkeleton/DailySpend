#!/usr/bin/env python3
"""Reject common credentials/private data without printing their contents.

This bounded check is not an exhaustive secret scanner or a history audit.
It uses only Python's standard library and does not send files anywhere.
"""

from pathlib import Path
import re
import subprocess
import sys


FORBIDDEN_SUFFIXES = {
    ".p12", ".pfx", ".p8", ".mobileprovision", ".provisionprofile", ".key",
    ".sqlite", ".sqlite3", ".db", ".store", ".ipa",
}
SIGNATURES = (
    re.compile(rb"-----BEGIN (?:RSA |EC |OPENSSH |DSA |ENCRYPTED )?PRIVATE KEY-----"),
    re.compile(rb"\bgh[pousr]_[A-Za-z0-9]{30,}\b"),
    re.compile(rb"\bgithub_pat_[A-Za-z0-9_]{50,}\b"),
    re.compile(rb"\bAKIA[A-Z0-9]{16}\b"),
    re.compile(rb"\bsk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{40,}\b"),
)


def inspect_file(path: Path) -> str | None:
    name = path.name.lower()
    if path.is_symlink():
        return "symlink requires review; CI must not follow files outside the checkout"
    if path.suffix.lower() in FORBIDDEN_SUFFIXES or name.endswith(("-wal", "-shm")):
        return "credential, signing material, database, or app archive"
    if name == ".env" or (name.startswith(".env.") and name not in {".env.example", ".env.sample"}):
        return "environment secrets file"
    if name in {"id_rsa", "id_ed25519", "credentials", "credentials.json"}:
        return "credentials file"
    if "backup" in name and path.suffix.lower() in {".json", ".zip", ".enc", ".backup"}:
        return "backup file; use generated synthetic fixtures instead"
    # Stream to avoid loading large assets; overlap catches split signatures.
    with path.open("rb") as stream:
        overlap = b""
        while block := stream.read(1024 * 1024):
            data = overlap + block
            if any(signature.search(data) for signature in SIGNATURES):
                return "possible secret signature"
            overlap = data[-4096:]
    return None


def main() -> int:
    root = Path(subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip())
    paths = subprocess.check_output(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"], cwd=root
    ).split(b"\0")
    failures = []
    for raw_path in set(paths) - {b""}:
        relative = Path(raw_path.decode("utf-8", errors="surrogateescape"))
        path = root / relative
        # Missing tracked files can be intentional deletions in a local change.
        if path.is_symlink() or path.is_file():
            reason = inspect_file(path)
            if reason:
                failures.append((str(relative), reason))
    if failures:
        for path, reason in sorted(failures):
            print(f"Repository safety check rejected {ascii(path)}: {reason}", file=sys.stderr)
        print("Do not publish these files. Review locally; contents were not printed.", file=sys.stderr)
        return 1
    print("Repository safety check passed (common signatures and file types only).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
