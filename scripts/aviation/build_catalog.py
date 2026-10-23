#!/usr/bin/env python3
"""Build the offline aviation catalog from pinned snapshots."""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from cataloglib.build import ROOT, build_documents, write_catalog
from cataloglib.fixtures import copy_fixtures, write_reference_fixtures, write_search_cases
from cataloglib.validate import validate_catalog


def main() -> None:
    write_reference_fixtures()
    texts = build_documents()
    write_catalog(texts)
    write_search_cases(ROOT / "data" / "aviation")
    copy_fixtures(ROOT)
    errors = validate_catalog(ROOT)
    if errors:
        for error in errors:
            print(error)
        raise SystemExit(f"{len(errors)} catalog validation errors")
    print("catalog build ok")
    for name, text in sorted(texts.items()):
        print(f"{name}: {len(text.encode('utf-8'))} bytes")


if __name__ == "__main__":
    main()
