/* =========================================================
   06_analysis_queries.sql
   Step 1.6 - Business analysis queries (CTEs + Window Functions)

   Definitions used everywhere:
   - Only DELIVERED orders count as real purchases (is_delivered = 1).
   - Revenue = sum of item prices (excludes freight).
     Payments include freight, so payment totals are higher.
   - Customer = real person (customer_unique_id / customer_key).
   ========================================================= */

USE OlistDB;
GO

/* ---------------------------------------------------------
   Q1) Monthly revenue, month-over-month growth, running total
   Window functions: LAG (previous month), SUM() OVER (running total)
   --------------------------------------------------------- */
WITH monthly AS (
    SELECT d.year_month,
           COUNT(*)                AS orders,
           SUM(f.items_value)      AS revenue
    FROM dw.FactOrders f
    JOIN dw.DimDate d ON d.date_key = f.purchase_date_key
    WHERE f.is_delivered = 1
    GROUP BY d.year_month
)
SELECT
    year_month,
    orders,
    revenue,
    CAST(revenue / orders AS DECIMAL(10,2))                         AS avg_order_value,
    LAG(revenue) OVER (ORDER BY year_month)                         AS prev_month_revenue,
    CAST(100.0 * (revenue - LAG(revenue) OVER (ORDER BY year_month))
         / NULLIF(LAG(revenue) OVER (ORDER BY year_month), 0)
         AS DECIMAL(10,1))                                          AS mom_growth_pct,
    SUM(revenue) OVER (ORDER BY year_month
                       ROWS UNBOUNDED PRECEDING)                    AS running_revenue
FROM monthly
ORDER BY year_month;
GO

/* ---------------------------------------------------------
   Q2) Top 10 product categories by revenue
   Window functions: RANK, SUM() OVER () for share of total
   --------------------------------------------------------- */
WITH cat AS (
    SELECT p.category_en,
           COUNT(*)              AS items_sold,
           SUM(i.price)          AS revenue
    FROM dw.FactOrderItems i
    JOIN dw.DimProduct p ON p.product_key = i.product_key
    WHERE i.is_delivered = 1
    GROUP BY p.category_en
),
ranked AS (
    SELECT *,
           RANK() OVER (ORDER BY revenue DESC)                          AS revenue_rank,
           CAST(100.0 * revenue / SUM(revenue) OVER () AS DECIMAL(5,1)) AS revenue_share_pct
    FROM cat
)
SELECT revenue_rank, category_en, items_sold, revenue, revenue_share_pct,
       SUM(revenue_share_pct) OVER (ORDER BY revenue_rank
                                    ROWS UNBOUNDED PRECEDING)          AS cumulative_share_pct
FROM ranked
WHERE revenue_rank <= 10
ORDER BY revenue_rank;
GO

/* ---------------------------------------------------------
   Q3) Top 10 customer states by revenue
   --------------------------------------------------------- */
WITH st AS (
    SELECT c.[state],
           COUNT(DISTINCT f.customer_key) AS customers,
           COUNT(*)                       AS orders,
           SUM(f.items_value)             AS revenue
    FROM dw.FactOrders f
    JOIN dw.DimCustomer c ON c.customer_key = f.customer_key
    WHERE f.is_delivered = 1
    GROUP BY c.[state]
)
SELECT TOP (10)
    RANK() OVER (ORDER BY revenue DESC)                              AS revenue_rank,
    [state], customers, orders, revenue,
    CAST(100.0 * revenue / SUM(revenue) OVER () AS DECIMAL(5,1))     AS revenue_share_pct,
    CAST(revenue / orders AS DECIMAL(10,2))                          AS avg_order_value
FROM st
ORDER BY revenue DESC;
GO

/* ---------------------------------------------------------
   Q4a) Delivery: actual vs. estimated, late rate (overall)
   Only orders with valid delivery dates.
   --------------------------------------------------------- */
SELECT
    COUNT(*)                                                       AS orders_measured,
    CAST(AVG(1.0 * delivery_days)  AS DECIMAL(5,1))                AS avg_actual_days,
    CAST(AVG(1.0 * estimated_days) AS DECIMAL(5,1))                AS avg_estimated_days,
    CAST(100.0 * SUM(CAST(is_late AS INT)) / COUNT(*) AS DECIMAL(5,1)) AS late_rate_pct,
    CAST(AVG(CASE WHEN is_late = 1 THEN 1.0 * delay_days END) AS DECIMAL(5,1)) AS avg_days_late_when_late
FROM dw.FactOrders
WHERE is_delivered = 1 AND has_valid_delivery_dates = 1;
GO

/* ---------------------------------------------------------
   Q4b) Does lateness hurt the review score?
   (preview of the dashboard's Delivery & Reviews page)
   --------------------------------------------------------- */
SELECT
    CASE WHEN is_late = 1 THEN 'Late' ELSE 'On time' END           AS delivery,
    COUNT(*)                                                       AS orders,
    CAST(AVG(1.0 * review_score) AS DECIMAL(3,2))                  AS avg_review_score,
    CAST(100.0 * SUM(CASE WHEN review_score <= 2 THEN 1 ELSE 0 END)
         / COUNT(review_score) AS DECIMAL(5,1))                    AS pct_bad_reviews_1_2
FROM dw.FactOrders
WHERE is_delivered = 1 AND has_valid_delivery_dates = 1
GROUP BY CASE WHEN is_late = 1 THEN 'Late' ELSE 'On time' END;
GO

/* ---------------------------------------------------------
   Q4c) Late rate by customer state (states with 1,000+ orders)
   --------------------------------------------------------- */
WITH s AS (
    SELECT c.[state],
           COUNT(*)                                      AS orders,
           AVG(1.0 * f.delivery_days)                    AS avg_days,
           100.0 * SUM(CAST(f.is_late AS INT)) / COUNT(*) AS late_rate
    FROM dw.FactOrders f
    JOIN dw.DimCustomer c ON c.customer_key = f.customer_key
    WHERE f.is_delivered = 1 AND f.has_valid_delivery_dates = 1
    GROUP BY c.[state]
    HAVING COUNT(*) >= 1000
)
SELECT
    RANK() OVER (ORDER BY late_rate DESC)     AS late_rank,
    [state], orders,
    CAST(avg_days  AS DECIMAL(5,1))           AS avg_delivery_days,
    CAST(late_rate AS DECIMAL(5,1))           AS late_rate_pct
FROM s
ORDER BY late_rate DESC;
GO

/* ---------------------------------------------------------
   Q5) Repeat customers: how many came back?
   --------------------------------------------------------- */
WITH per_customer AS (
    SELECT customer_key, COUNT(*) AS orders
    FROM dw.FactOrders
    WHERE is_delivered = 1
    GROUP BY customer_key
)
SELECT
    COUNT(*)                                                         AS customers,
    SUM(CASE WHEN orders >= 2 THEN 1 ELSE 0 END)                     AS repeat_customers,
    CAST(100.0 * SUM(CASE WHEN orders >= 2 THEN 1 ELSE 0 END) / COUNT(*)
         AS DECIMAL(5,2))                                            AS repeat_rate_pct,
    MAX(orders)                                                      AS max_orders_one_customer
FROM per_customer;
