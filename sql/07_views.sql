/* =========================================================
   07_views.sql
   Step 1.7 - Reporting views for Python and Power BI (schema: rpt)

   Why views?
   - One stable "contract": Python and Power BI read the same
     definitions, so their numbers always match SQL.
   - Business rules (delivered only, revenue without freight)
     live in ONE place instead of being repeated everywhere.

   Views:
   1) rpt.vw_CustomerOrders   - 1 row per delivered order (Python: RFM, churn)
   2) rpt.vw_CustomerSummary  - 1 row per customer
   3) rpt.vw_CohortActivity   - 1 row per customer per active month (cohort page)
   4) rpt.vw_MonthlyKPIs      - 1 row per month (to cross-check Power BI)
   ========================================================= */

USE OlistDB;
GO

IF SCHEMA_ID('rpt') IS NULL
    EXEC('CREATE SCHEMA rpt');
GO

/* 1) One row per delivered order -------------------------- */
CREATE OR ALTER VIEW rpt.vw_CustomerOrders AS
SELECT
    f.order_id,
    f.customer_key,
    c.customer_unique_id,
    c.[state]                                   AS customer_state,
    f.purchase_ts,
    CAST(f.purchase_ts AS DATE)                 AS purchase_date,
    d.year_month                                AS purchase_month,
    ROW_NUMBER() OVER (PARTITION BY f.customer_key
                       ORDER BY f.purchase_ts, f.order_id) AS order_seq,   -- 1 = first order
    f.item_count,
    f.items_value                               AS revenue,                -- excludes freight
    f.freight_value,
    f.payment_value,
    f.delivery_days,
    f.delay_days,
    f.is_late,
    f.review_score
FROM dw.FactOrders f
JOIN dw.DimCustomer c ON c.customer_key = f.customer_key
JOIN dw.DimDate d     ON d.date_key     = f.purchase_date_key
WHERE f.is_delivered = 1;
GO

/* 2) One row per customer --------------------------------- */
CREATE OR ALTER VIEW rpt.vw_CustomerSummary AS
SELECT
    customer_key,
    customer_unique_id,
    MAX(customer_state)                                   AS customer_state,
    MIN(purchase_ts)                                      AS first_purchase_ts,
    MAX(purchase_ts)                                      AS last_purchase_ts,
    COUNT(*)                                              AS orders,
    SUM(revenue)                                          AS revenue,
    CAST(AVG(1.0 * revenue) AS DECIMAL(10,2))             AS avg_order_value,
    SUM(freight_value)                                    AS freight_value,
    CAST(AVG(1.0 * review_score) AS DECIMAL(3,2))         AS avg_review_score,
    SUM(CASE WHEN is_late = 1 THEN 1 ELSE 0 END)          AS late_orders,
    CASE WHEN COUNT(*) >= 2 THEN 1 ELSE 0 END             AS is_repeat_customer
FROM rpt.vw_CustomerOrders
GROUP BY customer_key, customer_unique_id;
GO

/* 3) Cohort activity: customer x month -------------------- */
CREATE OR ALTER VIEW rpt.vw_CohortActivity AS
WITH firsts AS (
    SELECT customer_key,
           DATEFROMPARTS(YEAR(MIN(purchase_date)), MONTH(MIN(purchase_date)), 1) AS cohort_month_start
    FROM rpt.vw_CustomerOrders
    GROUP BY customer_key
),
activity AS (
    SELECT DISTINCT customer_key,
           DATEFROMPARTS(YEAR(purchase_date), MONTH(purchase_date), 1) AS activity_month_start
    FROM rpt.vw_CustomerOrders
)
SELECT
    a.customer_key,
    FORMAT(f.cohort_month_start,   'yyyy-MM')                           AS cohort_month,
    FORMAT(a.activity_month_start, 'yyyy-MM')                           AS activity_month,
    DATEDIFF(MONTH, f.cohort_month_start, a.activity_month_start)      AS month_number  -- 0 = first month
FROM activity a
JOIN firsts f ON f.customer_key = a.customer_key;
GO

/* 4) Monthly KPIs ----------------------------------------- */
CREATE OR ALTER VIEW rpt.vw_MonthlyKPIs AS
SELECT
    purchase_month,
    COUNT(*)                                                         AS orders,
    COUNT(DISTINCT customer_key)                                     AS customers,
    SUM(revenue)                                                     AS revenue,
    CAST(SUM(revenue) / COUNT(*) AS DECIMAL(10,2))                   AS avg_order_value,
    SUM(CASE WHEN order_seq = 1 THEN 1 ELSE 0 END)                   AS new_customers,
    CAST(100.0 * SUM(CASE WHEN is_late = 1 THEN 1 ELSE 0 END)
         / NULLIF(COUNT(is_late), 0) AS DECIMAL(5,1))                AS late_rate_pct,
    CAST(AVG(1.0 * review_score) AS DECIMAL(3,2))                    AS avg_review_score
FROM rpt.vw_CustomerOrders
GROUP BY purchase_month;
GO

/* ---------- Verification (must match step 1.6) ----------
   Expected: revenue 13,220,248.93 | customers 93,350 | repeat 2,801   */
SELECT
    (SELECT COUNT(*)     FROM rpt.vw_CustomerOrders)                      AS delivered_orders,
    (SELECT SUM(revenue) FROM rpt.vw_CustomerOrders)                      AS revenue_orders_view,
    (SELECT SUM(revenue) FROM rpt.vw_CustomerSummary)                     AS revenue_customer_view,
    (SELECT SUM(revenue) FROM rpt.vw_MonthlyKPIs)                         AS revenue_monthly_view,
    (SELECT COUNT(*)     FROM rpt.vw_CustomerSummary)                     AS customers,
    (SELECT SUM(is_repeat_customer) FROM rpt.vw_CustomerSummary)          AS repeat_customers,
    (SELECT SUM(new_customers) FROM rpt.vw_MonthlyKPIs)                   AS new_customers_total;  -- must equal customers

-- Preview: cohort sizes and how many came back in month 1-3
SELECT TOP (12)
    cohort_month,
    SUM(CASE WHEN month_number = 0 THEN 1 ELSE 0 END)  AS cohort_size,
    SUM(CASE WHEN month_number = 1 THEN 1 ELSE 0 END)  AS active_month_1,
    SUM(CASE WHEN month_number = 2 THEN 1 ELSE 0 END)  AS active_month_2,
    SUM(CASE WHEN month_number = 3 THEN 1 ELSE 0 END)  AS active_month_3
FROM rpt.vw_CohortActivity
WHERE cohort_month >= '2017-01'
GROUP BY cohort_month
ORDER BY cohort_month;
