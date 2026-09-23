/* ==========================================================================
   BRONZE LAYER — Raw landing load (TRUNCATE AND LOAD pattern)
   Table : dbo.bronze_erp_orders
   Rule  : store source data as-is. NO cleansing, NO business logic here.
   Strategy: TRUNCATE AND LOAD (full refresh). For incremental feeds, swap
             the TRUNCATE/INSERT block for the APPEND variant below.
   ========================================================================== */
SET NOCOUNT ON;

BEGIN TRANSACTION;

-- 1. Drop the previous snapshot. Bronze holds raw, reloadable data only.
TRUNCATE TABLE dbo.bronze_erp_orders;

-- 2. Land the new extract with explicit columns (never SELECT *).
--    Source: staging CSV bulk load from the ERP extract job.
INSERT INTO dbo.bronze_erp_orders
(
    order_id,
    customer_id,
    order_date_raw,
    item_total_raw,
    status_raw,
    load_batch_id
)
SELECT
    order_id,
    customer_id,
    order_date_raw,
    item_total_raw,
    status_raw,
    load_batch_id
FROM stg.erp_orders_extract;

/* -- APPEND variant (incremental feeds): replace steps 1-2 above with this:
INSERT INTO dbo.bronze_erp_orders
(
    order_id,
    customer_id,
    order_date_raw,
    item_total_raw,
    status_raw,
    load_batch_id
)
SELECT
    order_id,
    customer_id,
    order_date_raw,
    item_total_raw,
    status_raw,
    load_batch_id
FROM stg.erp_orders_extract AS s
WHERE NOT EXISTS (
    SELECT 1
    FROM dbo.bronze_erp_orders AS b
    WHERE b.order_id      = s.order_id
      AND b.load_batch_id = s.load_batch_id
);
*/

COMMIT TRANSACTION;

-- ==========================================================================
-- DATA QUALITY CHECKS (bronze: completeness of the landing, nothing more)
-- ==========================================================================

-- DQ1: landing must not be empty after a successful load.
IF NOT EXISTS (SELECT 1 FROM dbo.bronze_erp_orders)
BEGIN;
    THROW 50001, 'DQ FAIL (bronze): bronze_erp_orders is empty after load.', 1;
END;

-- DQ2: every row must carry a batch id for lineage back to the extract.
IF EXISTS (
    SELECT 1
    FROM dbo.bronze_erp_orders
    WHERE load_batch_id IS NULL
)
BEGIN;
    THROW 50002, 'DQ FAIL (bronze): rows with NULL load_batch_id found.', 1;
END;

PRINT 'DQ PASS (bronze): load landed with batch lineage intact.';
