/* =========================================================
   09_powerbi_model_checks.sql
   Step 3.1 - Reference numbers for the Power BI model

   Every number here must match what Power BI shows after
   loading (row counts in Table view + DAX checks).
   ========================================================= */

USE OlistDB;
GO

/* 1) Foreign keys in dw (source of Power BI relationships) */
SELECT
    OBJECT_SCHEMA_NAME(fk.parent_object_id) + '.' + OBJECT_NAME(fk.parent_object_id)         AS child_table,
    cp.name                                                                                  AS child_column,
    OBJECT_SCHEMA_NAME(fk.referenced_object_id) + '.' + OBJECT_NAME(fk.referenced_object_id) AS parent_table,
    cr.name                                                                                  AS parent_column
FROM sys.foreign_keys fk
JOIN sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
JOIN sys.columns cp ON cp.object_id = fkc.parent_object_id     AND cp.column_id = fkc.parent_column_id
JOIN sys.columns cr ON cr.object_id = fkc.referenced_object_id AND cr.column_id = fkc.referenced_column_id
WHERE OBJECT_SCHEMA_NAME(fk.parent_object_id) = 'dw'
ORDER BY child_table, child_column;
GO

/* 2) Row counts of the 11 objects loaded into Power BI */
SELECT 'dw.DimDate'               AS object_name, COUNT_BIG(*) AS row_count FROM dw.DimDate              UNION ALL
SELECT 'dw.DimGeography',                         COUNT_BIG(*) FROM dw.DimGeography                       UNION ALL
SELECT 'dw.DimCustomer',                          COUNT_BIG(*) FROM dw.DimCustomer                        UNION ALL
SELECT 'dw.DimProduct',                           COUNT_BIG(*) FROM dw.DimProduct                         UNION ALL
SELECT 'dw.DimSeller',                            COUNT_BIG(*) FROM dw.DimSeller                          UNION ALL
SELECT 'dw.FactOrders',                           COUNT_BIG(*) FROM dw.FactOrders                         UNION ALL
SELECT 'dw.FactOrderItems',                       COUNT_BIG(*) FROM dw.FactOrderItems                     UNION ALL
SELECT 'dw.FactPayments',                         COUNT_BIG(*) FROM dw.FactPayments                       UNION ALL
SELECT 'rpt.vw_CustomerSegments',                 COUNT_BIG(*) FROM rpt.vw_CustomerSegments               UNION ALL
SELECT 'rpt.vw_CohortActivity',                   COUNT_BIG(*) FROM rpt.vw_CohortActivity                 UNION ALL
SELECT 'rpt.vw_MonthlyKPIs',                      COUNT_BIG(*) FROM rpt.vw_MonthlyKPIs;
GO

/* 3) Key numbers Power BI must reproduce through the relationships */
SELECT
    (SELECT SUM(items_value) FROM dw.FactOrders WHERE is_delivered = 1)  AS delivered_revenue,   -- 13,220,248.93
    (SELECT COUNT(*) FROM dw.FactOrders WHERE is_delivered = 1)          AS delivered_orders,    -- 96,470
    (SELECT COUNT(*) FROM rpt.vw_CustomerSegments)                       AS segment_customers,   -- 93,350
    (SELECT SUM(is_scored) FROM rpt.vw_CustomerSegments)                 AS scored_customers,    -- 30,469
    (SELECT COUNT(*) FROM dw.DimCustomer c
      WHERE NOT EXISTS (SELECT 1 FROM rpt.vw_CustomerSegments s
                        WHERE s.customer_key = c.customer_key))         AS customers_without_segment;
GO

/* 4) Revenue by segment through the relationship path
      DimCustomer -> FactOrders (Power BI matrix must match) */
SELECT s.segment,
       COUNT(DISTINCT f.customer_key) AS customers,
       SUM(f.items_value)             AS revenue
FROM dw.FactOrders f
JOIN rpt.vw_CustomerSegments s ON s.customer_key = f.customer_key
WHERE f.is_delivered = 1
GROUP BY s.segment
ORDER BY revenue DESC;
GO

/* 5) Revenue by year through DimDate (active relationship = purchase date) */
SELECT d.[year],
       COUNT(*)           AS delivered_orders,
       SUM(f.items_value) AS revenue
FROM dw.FactOrders f
JOIN dw.DimDate d ON d.date_key = f.purchase_date_key
WHERE f.is_delivered = 1
GROUP BY d.[year]
ORDER BY d.[year];
GO

/* 6) Cohort customers by segment (tests Segments -> DimCustomer -> Cohort) */
SELECT s.segment,
       COUNT(DISTINCT a.customer_key) AS cohort_customers,
       COUNT(*)                       AS cohort_rows
FROM rpt.vw_CohortActivity a
JOIN rpt.vw_CustomerSegments s ON s.customer_key = a.customer_key
GROUP BY s.segment
ORDER BY cohort_customers DESC;
GO
