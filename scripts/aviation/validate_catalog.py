#!/usr/bin/env python3
"""Validate an already generated catalog. Does not download data."""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from cataloglib.validate import validate_catalog

ROOT = Path(__file__).resolve().parents[2]


def main() -> None:
    errors = validate_catalog(ROOT)
    if errors:
        for error in errors:
            print(error)
        raise SystemExit(f"{len(errors)} catalog validation errors")
    print("catalog validation ok")


if __name__ == "__main__":
    main()
