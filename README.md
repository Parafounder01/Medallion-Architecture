# Medallion Architecture

A hands-on SQL Server project built around the Medallion Architecture —
the idea that data earns its way from raw to ready in three stages:
**Bronze, Silver, Gold**.

## The idea in 30 seconds

- **Bronze** takes data exactly as it arrives. No cleaning, no judging.
  It's your safety net — you can always trace anything back to the source.
- **Silver** does the hard work: fixes NULLs, casts types, tidies text and
  dates, drops duplicates, and stamps every row with where it came from.
- **Gold** shapes the clean data into facts, dimensions, and views your
  dashboards and analysts can query directly.

## What's here

```
├── sql-warehouse/
│   ├── ROLE.md                  # the engineering rulebook (read this first)
│   ├── bronze/                  # raw landing template
│   ├── silver/                  # cleansing + standardization template
│   ├── gold/                    # star schema + analytical view template
│   ├── README.md                # layer-by-layer guide
│   └── TEST_REPORT.txt          # latest test results
└── tools/
    ├── mock_sql_test.py         # static contract checks (no database needed)
    └── live_parse_test.py       # real T-SQL grammar parse via sqlglot
```

## Run it

Scripts execute in order — bronze → silver → gold — in SSMS or sqlcmd.
Each one runs inside a transaction and ends with data-quality checks that
fail loudly on bad data and print `DQ PASS` when all is well.

No SQL Server handy? You can still validate everything:

```powershell
python tools/mock_sql_test.py    # rule checks: transactions, no SELECT *, CTEs, DQ checks
python tools/live_parse_test.py  # parses every batch as real T-SQL grammar
```

Both must exit 0. Latest results are saved in
`sql-warehouse/TEST_REPORT.txt`.

## Ground rules

All T-SQL here follows `sql-warehouse/ROLE.md`: explicit column lists
(never `SELECT *`), CTEs over nested subqueries, transaction control on
every script, and quality checks appended to each layer.
