/* =========================================================
   05_star_schema.sql
   Step 1.5 - Build the Star Schema (schema: dw)

   Dimensions : DimDate, DimGeography, DimCustomer, DimProduct, DimSeller
   Facts      : FactOrders      (grain: 1 row per order)
                FactOrderItems  (grain: 1 row per order item)
                FactPayments    (grain: 1 row per payment)

   Why FactOrders (not in the original plan)?
   Delivery time and review score belong to the ORDER, not to
   each item. Storing them on FactOrderItems would count an
   order with 3 items 3 times and bias averages.

   Surrogate keys (INT IDENTITY) are used for dimensions:
   smaller and faster joins than 32-char text ids in Power BI.
   Re-runnable: drops facts first (they reference dims).
   ========================================================= */

USE OlistDB;
GO

IF SCHEMA_ID('dw') IS NULL
    EXEC('CREATE SCHEMA dw');
GO

DROP TABLE IF EXISTS dw.FactPayments, dw.FactOrderItems, dw.FactOrders;
DROP TABLE IF EXISTS dw.DimCustomer, dw.DimSeller, dw.DimProduct,
                     dw.DimGeography, dw.DimDate;
GO

/* =========================================================
   1) DimDate - one row per calendar day
   ========================================================= */
CREATE TABLE dw.DimDate (
    date_key        INT          NOT NULL PRIMARY KEY,   -- yyyymmdd
    [date]          DATE         NOT NULL,
    [year]          SMALLINT     NOT NULL,
    [quarter]       TINYINT      NOT NULL,
    [month]         TINYINT      NOT NULL,
    month_name      VARCHAR(10)  NOT NULL,
    year_month      CHAR(7)      NOT NULL,               -- e.g. 2017-11
    day_of_month    TINYINT      NOT NULL,
    day_of_week     TINYINT      NOT NULL,               -- 1 = Monday
    day_name        VARCHAR(10)  NOT NULL,
    is_weekend      BIT          NOT NULL
);

DECLARE @start DATE, @end DATE;
SELECT @start = DATEFROMPARTS(YEAR(MIN(purchase_ts)), 1, 1),
       @end   = DATEFROMPARTS(YEAR(MAX(CASE WHEN estimated_ts > ISNULL(delivered_ts, estimated_ts)
                                            THEN estimated_ts ELSE delivered_ts END)), 12, 31)
FROM clean.orders;

WITH n AS (   -- numbers 0..N
    SELECT TOP (DATEDIFF(DAY, @start, @end) + 1)
           ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS i
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
),
d AS (SELECT DATEADD(DAY, i, @start) AS dt FROM n)
INSERT INTO dw.DimDate
SELECT
    CONVERT(INT, FORMAT(dt, 'yyyyMMdd')),
    dt,
    YEAR(dt),
    DATEPART(QUARTER, dt),
    MONTH(dt),
    DATENAME(MONTH, dt),
    FORMAT(dt, 'yyyy-MM'),
    DAY(dt),
    (DATEPART(WEEKDAY, dt) + @@DATEFIRST - 2) % 7 + 1,   -- Monday = 1 regardless of server setting
    DATENAME(WEEKDAY, dt),
    CASE WHEN (DATEPART(WEEKDAY, dt) + @@DATEFIRST - 2) % 7 + 1 IN (6, 7) THEN 1 ELSE 0 END
FROM d;
GO

/* =========================================================
   2) DimGeography - one row per zip code prefix
      Includes every zip used by customers or sellers, even
      if it has no coordinates (lat/lng then NULL).
   ========================================================= */
CREATE TABLE dw.DimGeography (
    geography_key    INT IDENTITY(1,1) PRIMARY KEY,
    zip_code_prefix  VARCHAR(10)  NOT NULL UNIQUE,
    city             VARCHAR(100) NULL,
    [state]          VARCHAR(5)   NULL,
    lat              FLOAT        NULL,
    lng              FLOAT        NULL
);

WITH places AS (   -- city/state as written by customers and sellers
    SELECT customer_zip_code_prefix AS zip, customer_city AS city, customer_state AS st FROM clean.customers
    UNION ALL
    SELECT seller_zip_code_prefix, seller_city, seller_state FROM clean.sellers
),
ranked AS (        -- most frequent city/state per zip
    SELECT zip, city, st,
           ROW_NUMBER() OVER (PARTITION BY zip ORDER BY COUNT(*) DESC, city) AS rn
    FROM places
    GROUP BY zip, city, st
),
all_zips AS (
    SELECT zip FROM places
    UNION
    SELECT zip_code_prefix FROM clean.geolocation
)
INSERT INTO dw.DimGeography (zip_code_prefix, city, [state], lat, lng)
SELECT z.zip, r.city, COALESCE(r.st, g.state), g.lat, g.lng
FROM all_zips z
LEFT JOIN ranked r          ON r.zip = z.zip AND r.rn = 1
LEFT JOIN clean.geolocation g ON g.zip_code_prefix = z.zip;
GO

/* =========================================================
   3) DimCustomer - one row per REAL customer (customer_unique_id)
      Location = from the customer's most recent order.
   ========================================================= */
CREATE TABLE dw.DimCustomer (
    customer_key        INT IDENTITY(1,1) PRIMARY KEY,
    customer_unique_id  VARCHAR(50)  NOT NULL UNIQUE,
    zip_code_prefix     VARCHAR(10)  NULL,
    city                VARCHAR(100) NULL,
    [state]             VARCHAR(5)   NULL,
    geography_key       INT          NULL REFERENCES dw.DimGeography(geography_key)
);

WITH latest AS (
    SELECT c.customer_unique_id, c.customer_zip_code_prefix, c.customer_city, c.customer_state,
           ROW_NUMBER() OVER (PARTITION BY c.customer_unique_id
                              ORDER BY o.purchase_ts DESC, c.customer_id) AS rn
    FROM clean.customers c
    JOIN clean.orders o ON o.customer_id = c.customer_id
)
INSERT INTO dw.DimCustomer (customer_unique_id, zip_code_prefix, city, [state], geography_key)
SELECT l.customer_unique_id, l.customer_zip_code_prefix, l.customer_city, l.customer_state,
       g.geography_key
FROM latest l
LEFT JOIN dw.DimGeography g ON g.zip_code_prefix = l.customer_zip_code_prefix
WHERE l.rn = 1;
GO

/* =========================================================
   4) DimProduct
   ========================================================= */
CREATE TABLE dw.DimProduct (
    product_key                 INT IDENTITY(1,1) PRIMARY KEY,
    product_id                  VARCHAR(50)  NOT NULL UNIQUE,
    category_en                 VARCHAR(100) NOT NULL,
    category_pt                 VARCHAR(100) NOT NULL,
    product_name_length         INT NULL,
    product_description_length  INT NULL,
    product_photos_qty          INT NULL,
    product_weight_g            INT NULL,
    product_length_cm           INT NULL,
    product_height_cm           INT NULL,
    product_width_cm            INT NULL
);

INSERT INTO dw.DimProduct (product_id, category_en, category_pt, product_name_length,
                           product_description_length, product_photos_qty, product_weight_g,
                           product_length_cm, product_height_cm, product_width_cm)
SELECT product_id, category_en, category_pt, product_name_length,
       product_description_length, product_photos_qty, product_weight_g,
       product_length_cm, product_height_cm, product_width_cm
FROM clean.products;
GO

/* =========================================================
   5) DimSeller
   ========================================================= */
CREATE TABLE dw.DimSeller (
    seller_key       INT IDENTITY(1,1) PRIMARY KEY,
    seller_id        VARCHAR(50)  NOT NULL UNIQUE,
    zip_code_prefix  VARCHAR(10)  NULL,
    city             VARCHAR(100) NULL,
    [state]          VARCHAR(5)   NULL,
    geography_key    INT          NULL REFERENCES dw.DimGeography(geography_key)
);

INSERT INTO dw.DimSeller (seller_id, zip_code_prefix, city, [state], geography_key)
SELECT s.seller_id, s.seller_zip_code_prefix, s.seller_city, s.seller_state, g.geography_key
FROM clean.sellers s
LEFT JOIN dw.DimGeography g ON g.zip_code_prefix = s.seller_zip_code_prefix;
GO

/* =========================================================
   6) FactOrders - 1 row per order (all statuses)
      Delivery metrics only when has_valid_delivery_dates = 1.
      delay_days > 0 means delivered AFTER the estimated date.
   ========================================================= */
CREATE TABLE dw.FactOrders (
    order_id                  VARCHAR(50) NOT NULL PRIMARY KEY,
    customer_key              INT NOT NULL REFERENCES dw.DimCustomer(customer_key),
    purchase_date_key         INT NOT NULL REFERENCES dw.DimDate(date_key),
    delivered_date_key        INT NULL     REFERENCES dw.DimDate(date_key),
    estimated_date_key        INT NULL     REFERENCES dw.DimDate(date_key),
    order_status              VARCHAR(20) NOT NULL,
    purchase_ts               DATETIME2(0) NOT NULL,
    is_delivered              BIT NOT NULL,
    has_valid_delivery_dates  BIT NOT NULL,
    item_count                INT NOT NULL,
    items_value               DECIMAL(12,2) NOT NULL,   -- sum of item prices
    freight_value             DECIMAL(12,2) NOT NULL,
    payment_value             DECIMAL(12,2) NOT NULL,
    delivery_days             INT NULL,                 -- purchase -> customer
    estimated_days            INT NULL,                 -- purchase -> estimated date
    delay_days                INT NULL,                 -- estimated -> delivered (+ = late)
    is_late                   BIT NULL,
    review_score              TINYINT NULL
);

WITH items AS (
    SELECT order_id, COUNT(*) AS item_count,
           SUM(price) AS items_value, SUM(freight_value) AS freight_value
    FROM clean.order_items GROUP BY order_id
),
pays AS (
    SELECT order_id, SUM(payment_value) AS payment_value
    FROM clean.order_payments GROUP BY order_id
)
INSERT INTO dw.FactOrders
SELECT
    o.order_id,
    dc.customer_key,
    CONVERT(INT, FORMAT(o.purchase_ts, 'yyyyMMdd')),
    CONVERT(INT, FORMAT(o.delivered_ts, 'yyyyMMdd')),
    CONVERT(INT, FORMAT(o.estimated_ts, 'yyyyMMdd')),
    o.order_status,
    o.purchase_ts,
    o.is_delivered,
    o.has_valid_delivery_dates,
    ISNULL(i.item_count, 0),
    ISNULL(i.items_value, 0),
    ISNULL(i.freight_value, 0),
    ISNULL(p.payment_value, 0),
    CASE WHEN o.has_valid_delivery_dates = 1
         THEN DATEDIFF(DAY, o.purchase_ts, o.delivered_ts) END,
    CASE WHEN o.has_valid_delivery_dates = 1
         THEN DATEDIFF(DAY, o.purchase_ts, o.estimated_ts) END,
    CASE WHEN o.has_valid_delivery_dates = 1
         THEN DATEDIFF(DAY, CAST(o.estimated_ts AS DATE), CAST(o.delivered_ts AS DATE)) END,
    CASE WHEN o.has_valid_delivery_dates = 1
         THEN CASE WHEN CAST(o.delivered_ts AS DATE) > CAST(o.estimated_ts AS DATE)
                   THEN 1 ELSE 0 END END,
    r.review_score
FROM clean.orders o
JOIN clean.customers c  ON c.customer_id = o.customer_id
JOIN dw.DimCustomer dc  ON dc.customer_unique_id = c.customer_unique_id
LEFT JOIN items i       ON i.order_id = o.order_id
LEFT JOIN pays p        ON p.order_id = o.order_id
LEFT JOIN clean.order_reviews r ON r.order_id = o.order_id;
GO

/* =========================================================
   7) FactOrderItems - 1 row per item in an order
   ========================================================= */
CREATE TABLE dw.FactOrderItems (
    order_id           VARCHAR(50) NOT NULL REFERENCES dw.FactOrders(order_id),
    order_item_id      INT NOT NULL,
    customer_key       INT NOT NULL REFERENCES dw.DimCustomer(customer_key),
    product_key        INT NOT NULL REFERENCES dw.DimProduct(product_key),
    seller_key         INT NOT NULL REFERENCES dw.DimSeller(seller_key),
    purchase_date_key  INT NOT NULL REFERENCES dw.DimDate(date_key),
    is_delivered       BIT NOT NULL,
    price              DECIMAL(10,2) NOT NULL,
    freight_value      DECIMAL(10,2) NOT NULL,
    CONSTRAINT PK_FactOrderItems PRIMARY KEY (order_id, order_item_id)
);

INSERT INTO dw.FactOrderItems
SELECT
    i.order_id, i.order_item_id,
    fo.customer_key, dp.product_key, ds.seller_key,
    fo.purchase_date_key, fo.is_delivered,
    i.price, i.freight_value
FROM clean.order_items i
JOIN dw.FactOrders fo ON fo.order_id  = i.order_id
JOIN dw.DimProduct dp ON dp.product_id = i.product_id
JOIN dw.DimSeller  ds ON ds.seller_id  = i.seller_id;
GO

/* =========================================================
   8) FactPayments - 1 row per payment of an order
   ========================================================= */
CREATE TABLE dw.FactPayments (
    order_id              VARCHAR(50) NOT NULL REFERENCES dw.FactOrders(order_id),
    payment_sequential    INT NOT NULL,
    customer_key          INT NOT NULL REFERENCES dw.DimCustomer(customer_key),
    purchase_date_key     INT NOT NULL REFERENCES dw.DimDate(date_key),
    payment_type          VARCHAR(30) NOT NULL,
    payment_installments  INT NOT NULL,
    payment_value         DECIMAL(10,2) NOT NULL,
    CONSTRAINT PK_FactPayments PRIMARY KEY (order_id, payment_sequential)
);

INSERT INTO dw.FactPayments
SELECT p.order_id, p.payment_sequential, fo.customer_key, fo.purchase_date_key,
       p.payment_type, p.payment_installments, p.payment_value
FROM clean.order_payments p
JOIN dw.FactOrders fo ON fo.order_id = p.order_id;
GO

/* =========================================================
   Verification: row counts vs. source + key checks
   ========================================================= */
SELECT t.table_name, t.dw_rows, s.source_rows,
       CASE WHEN s.source_rows IS NULL THEN '-'
            WHEN t.dw_rows = s.source_rows THEN 'OK' ELSE 'CHECK' END AS status
FROM (
    SELECT 'DimDate' AS table_name, COUNT(*) AS dw_rows FROM dw.DimDate UNION ALL
    SELECT 'DimGeography',   COUNT(*) FROM dw.DimGeography   UNION ALL
    SELECT 'DimCustomer',    COUNT(*) FROM dw.DimCustomer    UNION ALL
    SELECT 'DimProduct',     COUNT(*) FROM dw.DimProduct     UNION ALL
    SELECT 'DimSeller',      COUNT(*) FROM dw.DimSeller      UNION ALL
    SELECT 'FactOrders',     COUNT(*) FROM dw.FactOrders     UNION ALL
    SELECT 'FactOrderItems', COUNT(*) FROM dw.FactOrderItems UNION ALL
    SELECT 'FactPayments',   COUNT(*) FROM dw.FactPayments
) t
LEFT JOIN (
    SELECT 'DimCustomer' AS table_name, COUNT(DISTINCT customer_unique_id) AS source_rows FROM clean.customers UNION ALL
    SELECT 'DimProduct',     COUNT(*) FROM clean.products       UNION ALL
    SELECT 'DimSeller',      COUNT(*) FROM clean.sellers        UNION ALL
    SELECT 'FactOrders',     COUNT(*) FROM clean.orders         UNION ALL
    SELECT 'FactOrderItems', COUNT(*) FROM clean.order_items    UNION ALL
    SELECT 'FactPayments',   COUNT(*) FROM clean.order_payments
) s ON s.table_name = t.table_name;

-- Money check: totals must match the clean tables exactly
SELECT
    (SELECT SUM(price)          FROM clean.order_items)    AS clean_items_value,
    (SELECT SUM(price)          FROM dw.FactOrderItems)    AS dw_items_value,
    (SELECT SUM(items_value)    FROM dw.FactOrders)        AS dw_orders_items_value,
    (SELECT SUM(payment_value)  FROM clean.order_payments) AS clean_payment_value,
    (SELECT SUM(payment_value)  FROM dw.FactPayments)      AS dw_payment_value;
