/* =========================================================
   02_load_staging.sql
   Step 1.2 - Load the 9 Olist CSV files into staging tables
   - FORMAT = 'CSV' handles quoted fields (and line breaks
     inside review comments).
   - CODEPAGE = '65001' (UTF-8) keeps Portuguese characters.
   - Most files end lines with LF (0x0a); reviews and the
     category translation file use CRLF (0x0d0a).
   NOTE: change the file paths if your project folder is elsewhere.
   ========================================================= */

USE OlistDB;
GO

-- Empty the tables first so the script can be re-run safely
TRUNCATE TABLE stg.customers;
TRUNCATE TABLE stg.geolocation;
TRUNCATE TABLE stg.order_items;
TRUNCATE TABLE stg.order_payments;
TRUNCATE TABLE stg.order_reviews;
TRUNCATE TABLE stg.orders;
TRUNCATE TABLE stg.products;
TRUNCATE TABLE stg.sellers;
TRUNCATE TABLE stg.category_translation;
GO

BULK INSERT stg.customers
FROM 'C:\Projects\olist-customer-analytics\data\raw\olist_customers_dataset.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDQUOTE = '"', CODEPAGE = '65001',
      ROWTERMINATOR = '0x0a', TABLOCK);

BULK INSERT stg.geolocation
FROM 'C:\Projects\olist-customer-analytics\data\raw\olist_geolocation_dataset.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDQUOTE = '"', CODEPAGE = '65001',
      ROWTERMINATOR = '0x0a', TABLOCK);

BULK INSERT stg.order_items
FROM 'C:\Projects\olist-customer-analytics\data\raw\olist_order_items_dataset.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDQUOTE = '"', CODEPAGE = '65001',
      ROWTERMINATOR = '0x0a', TABLOCK);

BULK INSERT stg.order_payments
FROM 'C:\Projects\olist-customer-analytics\data\raw\olist_order_payments_dataset.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDQUOTE = '"', CODEPAGE = '65001',
      ROWTERMINATOR = '0x0a', TABLOCK);

BULK INSERT stg.order_reviews
FROM 'C:\Projects\olist-customer-analytics\data\raw\olist_order_reviews_dataset.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDQUOTE = '"', CODEPAGE = '65001',
      ROWTERMINATOR = '0x0d0a', TABLOCK);

BULK INSERT stg.orders
FROM 'C:\Projects\olist-customer-analytics\data\raw\olist_orders_dataset.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDQUOTE = '"', CODEPAGE = '65001',
      ROWTERMINATOR = '0x0a', TABLOCK);

BULK INSERT stg.products
FROM 'C:\Projects\olist-customer-analytics\data\raw\olist_products_dataset.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDQUOTE = '"', CODEPAGE = '65001',
      ROWTERMINATOR = '0x0a', TABLOCK);

BULK INSERT stg.sellers
FROM 'C:\Projects\olist-customer-analytics\data\raw\olist_sellers_dataset.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDQUOTE = '"', CODEPAGE = '65001',
      ROWTERMINATOR = '0x0a', TABLOCK);

BULK INSERT stg.category_translation
FROM 'C:\Projects\olist-customer-analytics\data\raw\product_category_name_translation.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDQUOTE = '"', CODEPAGE = '65001',
      ROWTERMINATOR = '0x0d0a', TABLOCK);
GO

-- Row count check: actual vs. expected (expected = rows in the official dataset)
SELECT t.table_name, t.actual_rows, e.expected_rows,
       CASE WHEN t.actual_rows = e.expected_rows THEN 'OK' ELSE 'CHECK' END AS status
FROM (
    SELECT 'customers'            AS table_name, COUNT(*) AS actual_rows FROM stg.customers            UNION ALL
    SELECT 'geolocation',                        COUNT(*) FROM stg.geolocation                          UNION ALL
    SELECT 'order_items',                        COUNT(*) FROM stg.order_items                          UNION ALL
    SELECT 'order_payments',                     COUNT(*) FROM stg.order_payments                       UNION ALL
    SELECT 'order_reviews',                      COUNT(*) FROM stg.order_reviews                        UNION ALL
    SELECT 'orders',                             COUNT(*) FROM stg.orders                               UNION ALL
    SELECT 'products',                           COUNT(*) FROM stg.products                             UNION ALL
    SELECT 'sellers',                            COUNT(*) FROM stg.sellers                              UNION ALL
    SELECT 'category_translation',               COUNT(*) FROM stg.category_translation
) AS t
JOIN (VALUES
    ('customers', 99441), ('geolocation', 1000163), ('order_items', 112650),
    ('order_payments', 103886), ('order_reviews', 99224), ('orders', 99441),
    ('products', 32951), ('sellers', 3095), ('category_translation', 71)
) AS e(table_name, expected_rows)
  ON e.table_name = t.table_name
ORDER BY t.table_name;
