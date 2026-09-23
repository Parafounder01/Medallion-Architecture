"""Static mock test run for sql-warehouse/ T-SQL templates.

No SQL Server required. Parses each .sql file and asserts the ROLE.md
contract: transaction control, no SELECT *, CTE usage, window functions,
and appended data-quality checks. Exit 0 = all pass, 1 = failures.
Usage: python tools/mock_sql_test.py
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "sql-warehouse"

EXPECT = {
    "bronze/01_bronze_load_template.sql": {"cte": False, "windows": []},
    "silver/02_silver_cleanse_template.sql": {"cte": True, "windows": ["ROW_NUMBER"]},
    "gold/03_gold_star_schema_template.sql": {"cte": True, "windows": ["SUM", "LAG", "NTILE"]},
}


def strip_comments(sql: str) -> str:
    sql = re.sub(r"/\*.*?\*/", "", sql, flags=re.S)   # block comments
    sql = re.sub(r"--[^\n]*", "", sql)                # line comments
    return sql


def check(path: Path, rules: dict) -> list:
    failures = []
    raw = path.read_text(encoding="utf-8")
    code = strip_comments(raw)

    begins = len(re.findall(r"(?i)\bBEGIN\s+TRANSACTION\b", code))
    commits = len(re.findall(r"(?i)\bCOMMIT\s+TRANSACTION\b", code))
    if begins < 1 or commits < 1 or begins != commits:
        failures.append(f"transaction imbalance (BEGIN={begins}, COMMIT={commits})")

    # SELECT * forbidden — but COUNT(*) is allowed.
    star = re.findall(r"(?i)SELECT\s*\*", code)
    if star:
        failures.append(f"SELECT * found ({len(star)}x)")

    if rules["cte"] and not re.search(r"(?i)\bWITH\b\s+\w+\s+AS\s*\(", code):
        failures.append("no CTE (WITH ... AS) found")

    for fn in rules["windows"]:
        if not re.search(rf"(?i)\b{fn}\b\s*\(.*?\)\s*OVER", code, flags=re.S):
            failures.append(f"window function {fn}(...) OVER not found")

    if "THROW" not in code:
        failures.append("no THROW-based DQ check found")
    if not re.search(r"(?i)DQ PASS", raw):
        failures.append("no DQ PASS confirmation found")

    return failures


def main() -> int:
    total_fail = 0
    for rel, rules in EXPECT.items():
        path = ROOT / rel
        if not path.exists():
            print(f"FAIL {rel}: file missing");
            total_fail += 1
            continue
        fails = check(path, rules)
        if fails:
            total_fail += len(fails)
            for f in fails:
                print(f"FAIL {rel}: {f}")
        else:
            print(f"PASS {rel}")
    print(f"\n{len(EXPECT) - (1 if total_fail else 0) * 0} files checked, "
          f"{total_fail} failure(s).")
    print("MOCK RUN " + ("FAILED" if total_fail else "PASSED")
          + " (static validation only — execute in SSMS/sqlcmd for a live test).")
    return 1 if total_fail else 0


if __name__ == "__main__":
    sys.exit(main())
