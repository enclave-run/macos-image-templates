#!/usr/bin/env python3

"""Write macOS' auto-login credential without retaining the plaintext password."""

from __future__ import annotations

import os
import re
import sys
import tempfile


KEY = bytes((0x7D, 0x89, 0x52, 0x23, 0xD2, 0xBC, 0xDD, 0xEA, 0xA3, 0xB9, 0x1F))
TARGET = "/etc/kcpassword"


def encode(password: bytes) -> bytes:
    remainder = len(password) % len(KEY)
    if remainder:
        password += b"\0" * (len(KEY) - remainder)
    return bytes(value ^ KEY[index % len(KEY)] for index, value in enumerate(password))


def main() -> int:
    password = sys.stdin.buffer.read()
    if not re.fullmatch(rb"[a-f0-9]{32}", password):
        print("builder password must be exactly 32 lowercase hexadecimal bytes", file=sys.stderr)
        return 2

    directory = os.path.dirname(TARGET)
    descriptor, temporary = tempfile.mkstemp(prefix=".kcpassword.", dir=directory)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "wb", closefd=True) as output:
            output.write(encode(password))
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, TARGET)
        directory_descriptor = os.open(directory, os.O_RDONLY)
        try:
            os.fsync(directory_descriptor)
        finally:
            os.close(directory_descriptor)
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
