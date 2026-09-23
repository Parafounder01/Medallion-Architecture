/* ==========================================================================
   GOLD LAYER — Business-ready star schema + analytical view
   Sources: dbo.silver_orders (+ dbo.silver_customers, if landed)
   Targets: dbo.dim_customer, dbo.fact_orders, dbo.vw_order_trends
   ========================================================================== */
SET NOCOUNT ON;

BEGIN TRANSACTION;

/* --------------------------------------------------------------------------
   DIM_CUSTOMER (SCD Type 1: latest attribute values win)
   -------------------------------------------------------------------------- */
MERGE INTO dbo.dim_customer AS tgt
USING (
    -- One row per customer from silver; latest order carries current attributes.
    WITH ranked AS (
        SELECT
            s.customer_id,
            s.load_batch_id,
            ROW_NUMBER() OVER (
                PARTITION BY s.customer_id
                ORDER BY s.order_date DESC, s.load_batch_id DESC
            ) AS rn
        FROM dbo.silver_orders AS s
        WHERE s.customer_id IS NOT NULL
    )
    SELECT
        r.customer_id,
        CAST('ERP' AS VARCHAR(50)) AS source_system
    FROM ranked AS r
    WHERE r.rn = 1
) AS src
ON tgt.customer_id = src.customer_id
WHEN MATCHED THEN
    UPDATE SET
        tgt.source_system   = src.source_system,
        tgt.dwh_update_date = CAST(SYSDATETIME() AS DATE)
WHEN NOT MATCHED BY TARGET THEN
    INSERT (customer_id, source_system, dwh_create_date)
    VALUES (src.customer_id, src.source_system, CAST(SYSDATETIME() AS DATE));

/* --------------------------------------------------------------------------
   FACT_ORDERS (insert-only; joins validated against dim_customer first)
   -------------------------------------------------------------------------- */
INSERT INTO dbo.fact_orders
(
    order_id,
    customer_key,
    order_date,
    item_total,
    order_status,
    dwh_create_date
)
SELECT
    s.order_id,
    dc.customer_key,
    s.order_date,
    s.item_total,
    s.order_status,
    CAST(SYSDATETIME() AS DATE)
FROM dbo.silver_orders AS s
INNER JOIN dbo.dim_customer AS dc
    ON dc.customer_id = s.customer_id
WHERE NOT EXISTS (
    SELECT 1
    FROM dbo.fact_orders AS f
    WHERE f.order_id = s.order_id
);

COMMIT TRANSACTION;
GO

/* --------------------------------------------------------------------------
   VW_ORDER_TRENDS — business-ready analytical view over the star schema.
   Window functions used: SUM() OVER (running total), LAG (MoM delta),
   NTILE (customer value quartile). View = no redundant stored aggregates.
   -------------------------------------------------------------------------- */
CREATE OR ALTER VIEW dbo.vw_order_trends
AS
WITH monthly AS (
    SELECT
        DATEFROMPARTS(YEAR(f.order_date), MONTH(f.order_date), 1) AS month_start,
        SUM(f.item_total)       AS month_revenue,
        COUNT(*)                AS month_orders
    FROM dbo.fact_orders AS f
    GROUP BY DATEFROMPARTS(YEAR(f.order_date), MONTH(f.order_date), 1)
),
with_trends AS (
    SELECT
        m.month_start,
        m.month_revenue,
        m.month_orders,
        -- Running revenue total across all months to date.
        SUM(m.month_revenue) OVER (
            ORDER BY m.month_start
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS running_revenue,
        -- Previous month revenue for month-over-month comparison.
        LAG(m.month_revenue, 1) OVER (ORDER BY m.month_start) AS prev_month_revenue
    FROM monthly AS m
),
customer_value AS (
    SELECT
        f.customer_key,
        SUM(f.item_total) AS lifetime_value,
        -- Quartile bucket: Q4 = top 25% of customers by revenue.
        NTILE(4) OVER (ORDER BY SUM(f.item_total) DESC) AS value_quartile
    FROM dbo.fact_orders AS f
    GROUP BY f.customer_key
)
SELECT
    t.month_start,
    t.month_revenue,
    t.month_orders,
    t.running_revenue,
    t.prev_month_revenue,
    t.month_revenue - t.prev_month_revenue AS mom_delta
FROM with_trends AS t;
GO

-- ==========================================================================
-- DATA QUALITY CHECKS (gold: referential integrity + key uniqueness)
-- ==========================================================================

-- DQ1: every fact row must resolve to a dimension row (FK integrity).
IF EXISTS (
    SELECT 1
    FROM dbo.fact_orders AS f
    LEFT JOIN dbo.dim_customer AS dc
        ON dc.customer_key = f.customer_key
    WHERE dc.customer_key IS NULL
)
BEGIN;
    THROW 50021, 'DQ FAIL (gold): orphan fact_orders rows without dim_customer match.', 1;
END;

-- DQ2: fact business key uniqueness.
IF EXISTS (
    SELECT order_id
    FROM dbo.fact_orders
    GROUP BY order_id
    HAVING COUNT(*) > 1
)
BEGIN;
    THROW 50022, 'DQ FAIL (gold): duplicate order_id in fact_orders.', 1;
END;

PRINT 'DQ PASS (gold): FK integrity holds, fact keys unique.';
