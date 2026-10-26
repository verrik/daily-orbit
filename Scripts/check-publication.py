#!/usr/bin/env python3
"""Scan tracked source without printing potentially sensitive matching values."""
import pathlib
import re
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parents[1]
tracked = subprocess.check_output(["git", "ls-files", "-z"], cwd=root).decode().split("\0")
patterns = {
    "GitHub credential": re.compile(r"(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,})"),
    "cloud access key": re.compile(r"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b"),
    "OpenAI credential": re.compile(r"\bsk-(?:proj-)?[A-Za-z0-9_-]{24,}"),
    "private key": re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    "assigned secret": re.compile(r'''(?i)(?:api[_-]?key|access[_-]?token|client[_-]?secret|password)\s*[=:]\s*["'][A-Za-z0-9_./+\-=]{16,}["']'''),
    "credential in URL": re.compile(r"https?://[^\s/:]+:[^\s/@]+@"),
    "private home path": re.compile(r"/(?:Users|home)/[A-Za-z0-9_.-]+/"),
    "personal email": re.compile(r"\b[A-Za-z0-9._%+-]+@(?!users\.noreply\.github\.com\b|2x\.png\b)[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"),
}
forbidden = {".build", "dist", "Images", "__pycache__", ".env", ".DS_Store", "current.json", "previous-wallpapers.json"}
failures = []
count = 0
for name in filter(None, tracked):
    path = root / name
    if path.is_symlink():
        failures.append((name, "symlink requires manual review"))
        continue
    if any(part in forbidden or part.startswith('.env.') for part in path.relative_to(root).parts) or path.suffix in {".zip", ".jpg", ".jpeg", ".heic", ".pem", ".p12", ".p8", ".key"}:
        failures.append((name, "generated, local, image, or credential file"))
        continue
    if any(part.endswith((".app", ".saver")) for part in path.relative_to(root).parts):
        failures.append((name, "compiled bundle"))
        continue
    try:
        content = path.read_text()
    except (UnicodeError, OSError):
        failures.append((name, "non-text or unreadable file requires manual review"))
        continue
    count += 1
    # Patterns in this scanner are definitions, not embedded credentials.
    if path.resolve() == pathlib.Path(__file__).resolve():
        continue
    for label, pattern in patterns.items():
        if pattern.search(content):
            failures.append((name, label))
if failures:
    for name, reason in failures:
        print(f"FAIL: {name}: {reason}")
    sys.exit(1)
print(f"Publication check passed for {count} tracked text files. No matching credentials or private local data found.")
