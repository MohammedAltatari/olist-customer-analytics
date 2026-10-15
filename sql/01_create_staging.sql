/* =========================================================
   01_create_staging.sql
   Step 1.1 - Create OlistDB and staging tables
   Staging tables mirror the 9 Olist CSV files 1:1.
   All columns are NVARCHAR on purpose: we load raw text first,
   then validate and convert data types in later steps.
   ========================================================= */

-- 1) Create the database (only if it does not exist)
IF DB_ID('OlistDB') IS NULL
    CREATE DATABASE OlistDB;
GO

USE OlistDB;
GO

-- 2) Separate schema for raw/staging data
IF SCHEMA_ID('stg') IS NULL
    EXEC('CREATE SCHEMA stg');
GO

-- 3) Drop old staging tables so the script can be re-run safely
DROP TABLE IF EXISTS stg.customers, stg.geolocation, stg.order_items,
                     stg.order_payments, stg.order_reviews, stg.orders,
                     stg.products, stg.sellers, stg.category_translation;
GO

-- 4) Staging tables (column names match CSV headers exactly)

CREATE TABLE stg.customers (
    customer_id               NVARCHAR(50),
    customer_unique_id        NVARCHAR(50),
    customer_zip_code_prefix  NVARCHAR(10),   -- text, to keep leading zeros
    customer_city             NVARCHAR(100),
    customer_state            NVARCHAR(5)
);

CREATE TABLE stg.geolocation (
    geolocation_zip_code_prefix NVARCHAR(10),
    geolocation_lat             NVARCHAR(50),
    geolocation_lng             NVARCHAR(50),
    geolocation_city            NVARCHAR(100),
    geolocation_state           NVARCHAR(5)
);

CREATE TABLE stg.order_items (
    order_id             NVARCHAR(50),
    order_item_id        NVARCHAR(10),
    product_id           NVARCHAR(50),
    seller_id            NVARCHAR(50),
    shipping_limit_date  NVARCHAR(30),
    price                NVARCHAR(20),
    freight_value        NVARCHAR(20)
);

CREATE TABLE stg.order_payments (
    order_id              NVARCHAR(50),
    payment_sequential    NVARCHAR(10),
    payment_type          NVARCHAR(30),
    payment_installments  NVARCHAR(10),
    payment_value         NVARCHAR(20)
);

CREATE TABLE stg.order_reviews (
    review_id                NVARCHAR(50),
    order_id                 NVARCHAR(50),
    review_score             NVARCHAR(5),
    review_comment_title     NVARCHAR(MAX),
    review_comment_message   NVARCHAR(MAX),
    review_creation_date     NVARCHAR(30),
    review_answer_timestamp  NVARCHAR(30)
);

CREATE TABLE stg.orders (
    order_id                       NVARCHAR(50),
    customer_id                    NVARCHAR(50),
    order_status                   NVARCHAR(20),
    order_purchase_timestamp       NVARCHAR(30),
    order_approved_at              NVARCHAR(30),
    order_delivered_carrier_date   NVARCHAR(30),
    order_delivered_customer_date  NVARCHAR(30),
    order_estimated_delivery_date  NVARCHAR(30)
);

CREATE TABLE stg.products (
    product_id                  NVARCHAR(50),
    product_category_name       NVARCHAR(100),
    product_name_lenght         NVARCHAR(10),  -- typo "lenght" is in the source file
    product_description_lenght  NVARCHAR(10),
    product_photos_qty          NVARCHAR(10),
    product_weight_g            NVARCHAR(20),
    product_length_cm           NVARCHAR(20),
    product_height_cm           NVARCHAR(20),
    product_width_cm            NVARCHAR(20)
);

CREATE TABLE stg.sellers (
    seller_id               NVARCHAR(50),
    seller_zip_code_prefix  NVARCHAR(10),
    seller_city             NVARCHAR(100),
    seller_state            NVARCHAR(5)
);

CREATE TABLE stg.category_translation (
    product_category_name          NVARCHAR(100),
    product_category_name_english  NVARCHAR(100)
);
GO

-- 5) Check: should return 9 tables
SELECT TABLE_SCHEMA, TABLE_NAME
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'stg'
ORDER BY TABLE_NAME;
