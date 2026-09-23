# sql-warehouse

A small starter kit I put together for building a data warehouse the clean
way — raw data lands first, gets cleaned next, and only then becomes
something analysts can query. That's the whole Medallion idea: Bronze,
Silver, Gold.

`ROLE.md` is the rulebook. Everything in here follows it.

## What's inside

- `bronze/01_bronze_load_template.sql` — dumps the raw ERP extract exactly
  as it arrives. No cleaning, no cleverness. Just land it so you can always
  trace back to the source.
- `silver/02_silver_cleanse_template.sql` — this is where the real work
  happens: fixing NULLs, tidying text, casting dates and numbers properly,
  and throwing out duplicates. Every row also gets stamped with where it
  came from and when.
- `gold/03_gold_star_schema_template.sql` — clean data shaped into a proper
  star schema (a customer dimension and an orders fact table), plus a view
  with running totals, month-over-month deltas, and customer quartiles.

## How to run them

In order: bronze → silver → gold. Each script runs in its own transaction
and ends with data-quality checks that will loudly fail (THROW) if
something's off — empty landing, duplicate keys, orphans, unexpected NULLs.
If a script prints `DQ PASS`, you're good to move to the next layer.

## Making it yours

The table names (`dbo.bronze_erp_orders`, `stg.*`, etc.) are placeholders.
Point them at your real tables and go:

- Different entity? Copy a layer file, rename things, keep the shape.
- Incremental loads? There's an APPEND version sitting commented in the
  bronze script — swap it in.
- Need history in silver? Replace the TRUNCATE with a MERGE on the
  business key.
- New metric? Add it to the gold view. Keep aggregations out of silver.

## Testing

Run `python tools/mock_sql_test.py` from the repo root. It doesn't touch a
database — it just reads the scripts and checks they follow the rules
(balanced transactions, no `SELECT *`, CTEs, the right window functions, DQ
checks present). For a real run, execute the scripts in SSMS or sqlcmd
against SQL Server.
