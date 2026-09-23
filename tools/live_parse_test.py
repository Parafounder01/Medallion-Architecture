"""Live parse test: feeds every sql-warehouse/ script batch-by-batch through
the sqlglot T-SQL dialect parser (real grammar, not regex). Exit 0 = all
batches parse, 1 = parse errors. GO separators are split, not parsed.
Usage: python tools/live_parse_test.py
"""
import re
import sys
from pathlib import Path

import sqlglot

ROOT = Path(__file__).resolve().parent.parent / "sql-warehouse"
FILES = sorted(ROOT.rglob("*.sql"))


def batches(sql: str) -> list:
    # sqlglot's T-SQL grammar does not implement THROW (valid T-SQL).
    # Strip THROW statements before parsing; their presence is asserted
    # separately by tools/mock_sql_test.py.
    sql = re.sub(r"(?im)^\s*THROW\s+[^;]+;", "SELECT 1;", sql)
    return [b for b in re.split(r"(?im)^\s*GO\s*$", sql) if b.strip()]


def main() -> int:
    errors = 0
    total = 0
    for path in FILES:
        rel = path.relative_to(ROOT)
        for i, batch in enumerate(batches(path.read_text(encoding="utf-8")), 1):
            total += 1
            try:
                sqlglot.parse(batch, read="tsql")
                print(f"PASS {rel} [batch {i}]")
            except Exception as e:  # noqa: BLE001 - report parser error verbatim
                errors += 1
                print(f"FAIL {rel} [batch {i}]: {e}")
    print(f"\n{total} batches parsed, {errors} error(s).")
    print("LIVE PARSE " + ("FAILED" if errors else "PASSED")
          + " (grammar check via sqlglot tsql dialect).")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
