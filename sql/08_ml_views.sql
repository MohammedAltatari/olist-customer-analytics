/* =========================================================
   08_ml_views.sql
   Step 2.9 - Reporting view over the Python / ML results (schema: ml)

   Tables written by the notebooks:
   - ml.CustomerSegments      (02_rfm_segmentation.ipynb) - 1 row per customer
   - ml.SecondPurchaseScores  (03_churn_model.ipynb)      - 1 row per customer
                                                             that can be targeted now
   Power BI reads rpt.vw_CustomerSegments only.
   ========================================================= */

USE OlistDB;
GO

CREATE OR ALTER VIEW rpt.vw_CustomerSegments AS
SELECT
    s.customer_key,
    s.customer_unique_id,
    c.[state]                     AS customer_state,
    c.city                        AS customer_city,
    s.snapshot_date,
    s.first_purchase,
    s.last_purchase,
    s.recency_days,
    s.purchase_days,
    s.orders,
    s.monetary,
    s.R, s.F, s.M,
    s.RFM_code,
    s.segment,                    -- main segmentation (rules)
    s.cluster,
    s.cluster_name,               -- K-Means, extra column
    p.main_category               AS first_main_category,
    p.days_since_first,
    p.return_probability,         -- ranking aid only (inflated by class weights)
    p.rank_pct,                   -- 1 = most likely to return
    p.priority_group,
    CASE WHEN p.customer_key IS NULL THEN 0 ELSE 1 END AS is_scored
FROM ml.CustomerSegments s
JOIN dw.DimCustomer c          ON c.customer_key = s.customer_key
LEFT JOIN ml.SecondPurchaseScores p ON p.customer_key = s.customer_key;
GO

/* ---------- Verification ----------
   Expected: 93,350 customers | revenue 13,220,248.93           */
SELECT COUNT(*)                 AS customers,
       ROUND(SUM(monetary), 2)  AS revenue,
       SUM(is_scored)           AS scored_customers
FROM rpt.vw_CustomerSegments;

SELECT segment,
       COUNT(*)                 AS customers,
       ROUND(SUM(monetary), 2)  AS revenue,
       SUM(is_scored)           AS scored_customers
FROM rpt.vw_CustomerSegments
GROUP BY segment
ORDER BY revenue DESC;

SELECT priority_group,
       COUNT(*)                 AS customers,
       ROUND(AVG(return_probability), 3) AS avg_score
FROM rpt.vw_CustomerSegments
WHERE is_scored = 1
GROUP BY priority_group
ORDER BY priority_group;
