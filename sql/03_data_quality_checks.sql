/* =========================================================
   03_data_quality_checks.sql
   Step 1.3 - Data quality checks on staging tables
   Returns ONE summary table: each row = one check and how
   many records have that issue. We fix issues in step 1.4.
   NULLIF(x, '') treats empty text as missing.
   ========================================================= */

USE OlistDB;
GO

WITH checks AS (

    -- ---------- 1) Keys & duplicates ----------
    SELECT 1 AS check_no, 'Duplicates' AS category,
           'Duplicate order_id in orders' AS check_name,
           COUNT(*) - COUNT(DISTINCT order_id) AS issue_count
    FROM stg.orders
    UNION ALL
    SELECT 2, 'Duplicates', 'Duplicate customer_id in customers',
           COUNT(*) - COUNT(DISTINCT customer_id)
    FROM stg.customers
    UNION ALL
    SELECT 3, 'Duplicates', 'Duplicate product_id in products',
           COUNT(*) - COUNT(DISTINCT product_id)
    FROM stg.products
    UNION ALL
    SELECT 4, 'Duplicates', 'Duplicate review_id rows in reviews',
           COUNT(*) - COUNT(DISTINCT review_id)
    FROM stg.order_reviews
    UNION ALL
    SELECT 5, 'Duplicates', 'Orders with more than one review',
           COUNT(*)
    FROM (SELECT order_id FROM stg.order_reviews
          GROUP BY order_id HAVING COUNT(*) > 1) x
    UNION ALL
    SELECT 6, 'Customers', 'Real customers (unique_id) with more than one customer_id',
           COUNT(*)
    FROM (SELECT customer_unique_id FROM stg.customers
          GROUP BY customer_unique_id HAVING COUNT(DISTINCT customer_id) > 1) x
    UNION ALL
    SELECT 7, 'Duplicates', 'Geolocation rows beyond 1 per zip prefix',
           COUNT(*) - COUNT(DISTINCT geolocation_zip_code_prefix)
    FROM stg.geolocation

    -- ---------- 2) Missing relationships ----------
    UNION ALL
    SELECT 8, 'Relationships', 'Orders with no items',
           COUNT(*)
    FROM stg.orders o
    WHERE NOT EXISTS (SELECT 1 FROM stg.order_items i WHERE i.order_id = o.order_id)
    UNION ALL
    SELECT 9, 'Relationships', 'Orders with no payment',
           COUNT(*)
    FROM stg.orders o
    WHERE NOT EXISTS (SELECT 1 FROM stg.order_payments p WHERE p.order_id = o.order_id)
    UNION ALL
    SELECT 10, 'Relationships', 'Orders with no review',
           COUNT(*)
    FROM stg.orders o
    WHERE NOT EXISTS (SELECT 1 FROM stg.order_reviews r WHERE r.order_id = o.order_id)
    UNION ALL
    SELECT 11, 'Relationships', 'Customer zip not found in geolocation',
           COUNT(*)
    FROM stg.customers c
    WHERE NOT EXISTS (SELECT 1 FROM stg.geolocation g
                      WHERE g.geolocation_zip_code_prefix = c.customer_zip_code_prefix)
    UNION ALL
    SELECT 12, 'Relationships', 'Product categories with no English translation',
           COUNT(DISTINCT p.product_category_name)
    FROM stg.products p
    WHERE NULLIF(p.product_category_name, '') IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM stg.category_translation t
                      WHERE t.product_category_name = p.product_category_name)

    -- ---------- 3) Missing values ----------
    UNION ALL
    SELECT 13, 'Missing values', 'Products with no category',
           COUNT(*)
    FROM stg.products WHERE NULLIF(product_category_name, '') IS NULL
    UNION ALL
    SELECT 14, 'Missing values', 'Orders with no approval date',
           COUNT(*)
    FROM stg.orders WHERE NULLIF(order_approved_at, '') IS NULL
    UNION ALL
    SELECT 15, 'Missing values', 'Orders with no customer delivery date (all statuses)',
           COUNT(*)
    FROM stg.orders WHERE NULLIF(order_delivered_customer_date, '') IS NULL
    UNION ALL
    SELECT 16, 'Missing values', 'Status = delivered but no delivery date',
           COUNT(*)
    FROM stg.orders
    WHERE order_status = 'delivered'
      AND NULLIF(order_delivered_customer_date, '') IS NULL

    -- ---------- 4) Invalid formats / illogical values ----------
    UNION ALL
    SELECT 17, 'Invalid values', 'Purchase dates that cannot be converted',
           COUNT(*)
    FROM stg.orders
    WHERE TRY_CAST(order_purchase_timestamp AS DATETIME2(0)) IS NULL
    UNION ALL
    SELECT 18, 'Invalid values', 'Prices that cannot be converted to a number',
           COUNT(*)
    FROM stg.order_items
    WHERE TRY_CAST(price AS DECIMAL(10,2)) IS NULL
    UNION ALL
    SELECT 19, 'Invalid values', 'Payments with value = 0',
           COUNT(*)
    FROM stg.order_payments
    WHERE TRY_CAST(payment_value AS DECIMAL(10,2)) = 0
    UNION ALL
    SELECT 20, 'Invalid values', 'Payment type = not_defined',
           COUNT(*)
    FROM stg.order_payments WHERE payment_type = 'not_defined'
    UNION ALL
    SELECT 21, 'Illogical dates', 'Delivered to customer BEFORE purchase',
           COUNT(*)
    FROM stg.orders
    WHERE TRY_CAST(order_delivered_customer_date AS DATETIME2(0))
        < TRY_CAST(order_purchase_timestamp AS DATETIME2(0))
    UNION ALL
    SELECT 22, 'Illogical dates', 'Handed to carrier BEFORE purchase',
           COUNT(*)
    FROM stg.orders
    WHERE TRY_CAST(order_delivered_carrier_date AS DATETIME2(0))
        < TRY_CAST(order_purchase_timestamp AS DATETIME2(0))
    UNION ALL
    SELECT 23, 'Illogical dates', 'Delivered to customer BEFORE handed to carrier',
           COUNT(*)
    FROM stg.orders
    WHERE TRY_CAST(order_delivered_customer_date AS DATETIME2(0))
        < TRY_CAST(order_delivered_carrier_date AS DATETIME2(0))
)
SELECT check_no, category, check_name, issue_count
FROM checks
ORDER BY check_no;
GO

-- Extra context: how many orders in each status?
SELECT order_status, COUNT(*) AS orders
FROM stg.orders
GROUP BY order_status
ORDER BY orders DESC;
