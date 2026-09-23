/* ==========================================================================
   SILVER LAYER — Cleansing & standardization
   Source: dbo.bronze_erp_orders  ->  Target: dbo.silver_orders
   Rule  : cleanse and standardize ONLY. NO final business aggregations.
   ========================================================================== */
SET NOCOUNT ON;

BEGIN TRANSACTION;

-- Full refresh of silver from the cleansed, deduplicated set below.
-- TRUNCATE keeps silver a clean mirror of bronze; use MERGE if history needed.
TRUNCATE TABLE dbo.silver_orders;

-- CTE 1: typed + cleansed view of the raw landing.
--   - NULLs get explicit defaults, text is trimmed/upper-cased,
--   - raw date/total strings are cast to DATE / DECIMAL(18,2).
WITH cleansed AS (
    SELECT
        TRY_CAST(b.order_id    AS INT)           AS order_id,
        TRY_CAST(b.customer_id AS INT)           AS customer_id,
        TRY_CAST(b.order_date_raw AS DATE)       AS order_date,
        TRY_CAST(b.item_total_raw AS DECIMAL(18, 2)) AS item_total,
        UPPER(LTRIM(RTRIM(COALESCE(b.status_raw, 'UNKNOWN')))) AS order_status,
        b.load_batch_id                          AS load_batch_id,
        -- Lineage columns derived in silver for every row.
        CAST(SYSDATETIME() AS DATE)              AS dwh_create_date,
        CAST('ERP' AS VARCHAR(50))               AS source_system
    FROM dbo.bronze_erp_orders AS b
),
-- CTE 2: keep one row per business key; newest batch wins on re-delivery.
--   ROW_NUMBER partitions by the natural key so duplicates collapse safely.
deduped AS (
    SELECT
        c.order_id,
        c.customer_id,
        c.order_date,
        c.item_total,
        c.order_status,
        c.load_batch_id,
        c.dwh_create_date,
        c.source_system,
        ROW_NUMBER() OVER (
            PARTITION BY c.order_id
            ORDER BY c.load_batch_id DESC
        ) AS rn
    FROM cleansed AS c
    WHERE c.order_id IS NOT NULL -- unparseable keys cannot enter silver
)
-- CTE and INSERT are one statement: T-SQL scopes a CTE to the single
-- SELECT/INSERT/UPDATE/DELETE/MERGE that immediately follows it.
INSERT INTO dbo.silver_orders
(
    order_id,
    customer_id,
    order_date,
    item_total,
    order_status,
    load_batch_id,
    dwh_create_date,
    source_system
)
SELECT
    d.order_id,
    d.customer_id,
    d.order_date,
    d.item_total,
    d.order_status,
    d.load_batch_id,
    d.dwh_create_date,
    d.source_system
FROM deduped AS d
WHERE d.rn = 1;

COMMIT TRANSACTION;

-- ==========================================================================
-- DATA QUALITY CHECKS (silver: uniqueness + no unexpected NULLs)
-- ==========================================================================

-- DQ1: primary key uniqueness on the business key.
IF EXISTS (
    SELECT order_id
    FROM dbo.silver_orders
    GROUP BY order_id
    HAVING COUNT(*) > 1
)
BEGIN;
    THROW 50011, 'DQ FAIL (silver): duplicate order_id in silver_orders.', 1;
END;

-- DQ2: zero unexpected NULLs in non-nullable business columns.
IF EXISTS (
    SELECT 1
    FROM dbo.silver_orders
    WHERE order_date IS NULL
       OR item_total IS NULL
)
BEGIN;
    THROW 50012, 'DQ FAIL (silver): NULL order_date or item_total found.', 1;
END;

PRINT 'DQ PASS (silver): keys unique, no unexpected NULLs.';
