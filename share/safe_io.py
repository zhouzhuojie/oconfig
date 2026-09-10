#!/usr/bin/env python3
"""Symlink-safe, owner-checked, atomic writes for oconfig state files."""
from __future__ import annotations

import errno
import json
import os
import stat
import sys
import tempfile


def fail(msg: str) -> None:
    print(f"oconfig: {msg}", file=sys.stderr)
    raise SystemExit(1)


def _lstat_if_exists(path: str) -> os.stat_result | None:
    try:
        return os.lstat(path)
    except FileNotFoundError:
        return None


def assert_writable_regular(path: str) -> None:
    """Refuse to write through a symlink, directory, or another user's file."""
    st = _lstat_if_exists(path)
    if st is None:
        return
    if not stat.S_ISREG(st.st_mode):
        fail(f"refusing to write {path}: not a regular file")
    if st.st_uid != os.getuid():
        fail(f"refusing to write {path}: not owned by current user")


def read_text(path: str) -> str:
    """Read a regular file owned by the current user. Does not follow symlinks."""
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    except FileNotFoundError:
        fail(f"missing {path}")
    except OSError as exc:
        if exc.errno in (errno.ELOOP, getattr(errno, "EMLINK", errno.ELOOP)):
            fail(f"refusing to read {path}: not a regular file")
        fail(f"cannot read {path}: {exc}")
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode):
            fail(f"refusing to read {path}: not a regular file")
        if st.st_uid != os.getuid():
            fail(f"refusing to read {path}: not owned by current user")
        with os.fdopen(fd, "r", encoding="utf-8") as fh:
            fd = -1
            return fh.read()
    finally:
        if fd >= 0:
            os.close(fd)


def atomic_write_text(path: str, text: str, mode: int = 0o600) -> None:
    path = os.path.abspath(path)
    directory = os.path.dirname(path)
    os.makedirs(directory, exist_ok=True)
    assert_writable_regular(path)
    fd, tmp = tempfile.mkstemp(prefix=".oconfig-", suffix=".tmp", dir=directory)
    try:
        os.fchmod(fd, mode)
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fd = -1
            fh.write(text)
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, path)
        tmp = ""
    finally:
        if fd >= 0:
            os.close(fd)
        if tmp:
            try:
                os.unlink(tmp)
            except OSError:
                pass


def json_get(path: str, key: str) -> str:
    if _lstat_if_exists(path) is None:
        return ""
    try:
        data = json.loads(read_text(path) or "{}")
    except json.JSONDecodeError:
        return ""
    if not isinstance(data, dict):
        return ""
    value = data.get(key, "") or ""
    if key == "repo":
        return os.path.expanduser(str(value))
    return str(value)


def json_set(path: str, key: str, value: str) -> None:
    cfg: dict = {}
    if _lstat_if_exists(path) is not None:
        try:
            loaded = json.loads(read_text(path) or "{}")
            if isinstance(loaded, dict):
                cfg = loaded
        except SystemExit:
            raise
        except Exception:
            cfg = {}
    cfg[key] = value
    atomic_write_text(path, json.dumps(cfg, indent=2) + "\n")


def copy_if_absent(src: str, dest: str) -> None:
    if _lstat_if_exists(dest) is not None:
        assert_writable_regular(dest)
        return
    with open(src, encoding="utf-8") as fh:
        atomic_write_text(dest, fh.read())


def append_line(path: str, line: str) -> None:
    existing = ""
    if _lstat_if_exists(path) is not None:
        existing = read_text(path)
    if existing.splitlines() and not existing.endswith("\n"):
        existing += "\n"
    if line in existing.splitlines():
        return
    atomic_write_text(path, existing + line + "\n")


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        fail("safe_io: missing command")
    cmd = argv[1]
    if cmd == "json-get" and len(argv) == 4:
        sys.stdout.write(json_get(argv[2], argv[3]))
        return 0
    if cmd == "json-set" and len(argv) == 5:
        json_set(argv[2], argv[3], argv[4])
        return 0
    if cmd == "copy-if-absent" and len(argv) == 4:
        copy_if_absent(argv[2], argv[3])
        return 0
    if cmd == "append-line" and len(argv) == 4:
        append_line(argv[2], argv[3])
        return 0
    fail(f"safe_io: bad command {cmd}")
    return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
