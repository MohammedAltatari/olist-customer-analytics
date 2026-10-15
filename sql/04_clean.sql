/* =========================================================
   04_clean.sql
   Step 1.4 - Clean staging data into typed "clean" tables
   Rules (agreed in step 1.3):
   - Never delete records: FLAG them and exclude only from
     the calculation they would distort.
   - Reviews: keep the latest review per order.
   - Geolocation: one row per zip prefix (average lat/lng,
     coordinates outside Brazil ignored).
   - Products: English category, 'unknown' when missing,
     manual translation for the 2 untranslated categories.
   - Cities: lower case, trimmed, accents removed.
   - Payment type 'not_defined' -> 'unknown'.
   Re-runnable: drops and rebuilds the clean tables.
   ========================================================= */

USE OlistDB;
GO

IF SCHEMA_ID('clean') IS NULL
    EXEC('CREATE SCHEMA clean');
GO

DROP TABLE IF EXISTS clean.customers, clean.sellers, clean.geolocation,
                     clean.products, clean.orders, clean.order_items,
                     clean.order_payments, clean.order_reviews;
GO

/* ---------- Helper note ----------
   Accent removal trick used below:
   CAST(text COLLATE SQL_Latin1_General_CP1253_CI_AI AS VARCHAR(100))
   converts e.g. 'são paulo' -> 'sao paulo'.                     */

-- 1) Customers -------------------------------------------------
SELECT
    customer_id,
    customer_unique_id,
    customer_zip_code_prefix,
    LOWER(TRIM(CAST(customer_city COLLATE SQL_Latin1_General_CP1253_CI_AI
                    AS VARCHAR(100))))           AS customer_city,
    UPPER(TRIM(customer_state))                 AS customer_state
INTO clean.customers
FROM stg.customers;

-- 2) Sellers ---------------------------------------------------
SELECT
    seller_id,
    seller_zip_code_prefix,
    LOWER(TRIM(CAST(seller_city COLLATE SQL_Latin1_General_CP1253_CI_AI
                    AS VARCHAR(100))))           AS seller_city,
    UPPER(TRIM(seller_state))                   AS seller_state
INTO clean.sellers
FROM stg.sellers;

-- 3) Geolocation: one row per zip prefix -----------------------
WITH geo AS (
    SELECT
        geolocation_zip_code_prefix                     AS zip_code_prefix,
        TRY_CAST(geolocation_lat AS FLOAT)              AS lat,
        TRY_CAST(geolocation_lng AS FLOAT)              AS lng,
        UPPER(TRIM(geolocation_state))                  AS state
    FROM stg.geolocation
),
geo_valid AS (   -- keep only points inside Brazil's bounding box
    SELECT * FROM geo
    WHERE lat BETWEEN -34 AND 5.5
      AND lng BETWEEN -74 AND -34
),
state_rank AS (  -- most frequent state per zip
    SELECT zip_code_prefix, state,
           ROW_NUMBER() OVER (PARTITION BY zip_code_prefix
                              ORDER BY COUNT(*) DESC, state) AS rn
    FROM geo_valid
    GROUP BY zip_code_prefix, state
)
SELECT
    g.zip_code_prefix,
    AVG(g.lat)      AS lat,
    AVG(g.lng)      AS lng,
    s.state,
    COUNT(*)        AS source_points
INTO clean.geolocation
FROM geo_valid g
JOIN state_rank s
  ON s.zip_code_prefix = g.zip_code_prefix AND s.rn = 1
GROUP BY g.zip_code_prefix, s.state;

-- 4) Products --------------------------------------------------
SELECT
    p.product_id,
    COALESCE(NULLIF(p.product_category_name, ''), 'unknown')  AS category_pt,
    COALESCE(
        t.product_category_name_english,
        CASE p.product_category_name
            WHEN 'pc_gamer' THEN 'pc_gamer'
            WHEN 'portateis_cozinha_e_preparadores_de_alimentos'
                 THEN 'kitchen_portables_and_food_preparers'
        END,
        'unknown')                                            AS category_en,
    TRY_CAST(p.product_name_lenght        AS INT)   AS product_name_length,       -- fix source typo
    TRY_CAST(p.product_description_lenght AS INT)   AS product_description_length,
    TRY_CAST(p.product_photos_qty         AS INT)   AS product_photos_qty,
    TRY_CAST(p.product_weight_g           AS INT)   AS product_weight_g,
    TRY_CAST(p.product_length_cm          AS INT)   AS product_length_cm,
    TRY_CAST(p.product_height_cm          AS INT)   AS product_height_cm,
    TRY_CAST(p.product_width_cm           AS INT)   AS product_width_cm
INTO clean.products
FROM stg.products p
LEFT JOIN stg.category_translation t
       ON t.product_category_name = p.product_category_name;

-- 5) Orders (typed dates + quality flags) ----------------------
WITH o AS (
    SELECT
        order_id,
        customer_id,
        order_status,
        TRY_CAST(order_purchase_timestamp      AS DATETIME2(0)) AS purchase_ts,
        TRY_CAST(order_approved_at             AS DATETIME2(0)) AS approved_ts,
        TRY_CAST(order_delivered_carrier_date  AS DATETIME2(0)) AS carrier_ts,
        TRY_CAST(order_delivered_customer_date AS DATETIME2(0)) AS delivered_ts,
        TRY_CAST(order_estimated_delivery_date AS DATETIME2(0)) AS estimated_ts
    FROM stg.orders
)
SELECT
    o.*,
    -- 1 = counts as a real purchase (used for revenue, RFM, churn)
    CASE WHEN order_status = 'delivered' AND delivered_ts IS NOT NULL
         THEN 1 ELSE 0 END                                   AS is_delivered,
    -- 1 = dates are complete and logical (used for delivery-time analysis)
    CASE WHEN delivered_ts IS NOT NULL
          AND delivered_ts >= purchase_ts
          AND (carrier_ts IS NULL OR (carrier_ts >= purchase_ts
                                      AND delivered_ts >= carrier_ts))
         THEN 1 ELSE 0 END                                   AS has_valid_delivery_dates
INTO clean.orders
FROM o;

-- 6) Order items -----------------------------------------------
SELECT
    order_id,
    TRY_CAST(order_item_id AS INT)                   AS order_item_id,
    product_id,
    seller_id,
    TRY_CAST(shipping_limit_date AS DATETIME2(0))    AS shipping_limit_ts,
    TRY_CAST(price         AS DECIMAL(10,2))         AS price,
    TRY_CAST(freight_value AS DECIMAL(10,2))         AS freight_value
INTO clean.order_items
FROM stg.order_items;

-- 7) Payments --------------------------------------------------
SELECT
    order_id,
    TRY_CAST(payment_sequential   AS INT)            AS payment_sequential,
    CASE WHEN payment_type = 'not_defined' THEN 'unknown'
         ELSE payment_type END                       AS payment_type,
    TRY_CAST(payment_installments AS INT)            AS payment_installments,
    TRY_CAST(payment_value AS DECIMAL(10,2))         AS payment_value
INTO clean.order_payments
FROM stg.order_payments;

-- 8) Reviews: latest review per order --------------------------
WITH r AS (
    SELECT
        review_id,
        order_id,
        TRY_CAST(review_score AS INT)                       AS review_score,
        NULLIF(review_comment_title, '')                    AS review_comment_title,
        NULLIF(review_comment_message, '')                  AS review_comment_message,
        TRY_CAST(review_creation_date    AS DATETIME2(0))   AS review_creation_ts,
        TRY_CAST(review_answer_timestamp AS DATETIME2(0))   AS review_answer_ts
    FROM stg.order_reviews
),
ranked AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY order_id
                              ORDER BY review_answer_ts DESC,
                                       review_creation_ts DESC,
                                       review_id) AS rn
    FROM r
)
SELECT review_id, order_id, review_score, review_comment_title,
       review_comment_message, review_creation_ts, review_answer_ts
INTO clean.order_reviews
FROM ranked
WHERE rn = 1;
GO

-- ---------- Verification ----------
SELECT 'customers' AS table_name, COUNT(*) AS rows_clean FROM clean.customers UNION ALL
SELECT 'sellers',        COUNT(*) FROM clean.sellers        UNION ALL
SELECT 'geolocation',    COUNT(*) FROM clean.geolocation    UNION ALL
SELECT 'products',       COUNT(*) FROM clean.products       UNION ALL
SELECT 'orders',         COUNT(*) FROM clean.orders         UNION ALL
SELECT 'order_items',    COUNT(*) FROM clean.order_items    UNION ALL
SELECT 'order_payments', COUNT(*) FROM clean.order_payments UNION ALL
SELECT 'order_reviews',  COUNT(*) FROM clean.order_reviews;

SELECT
    (SELECT COUNT(*) FROM clean.order_reviews)                             AS reviews,
    (SELECT COUNT(DISTINCT order_id) FROM clean.order_reviews)             AS orders_with_review,  -- must equal reviews
    (SELECT COUNT(*) FROM clean.products WHERE category_en = 'unknown')    AS products_unknown_category,
    (SELECT COUNT(*) FROM clean.orders WHERE is_delivered = 1)             AS delivered_orders,
    (SELECT COUNT(*) FROM clean.orders WHERE has_valid_delivery_dates = 1) AS orders_valid_delivery_dates,
    (SELECT COUNT(*) FROM clean.order_payments WHERE payment_type = 'unknown') AS payments_unknown_type;
