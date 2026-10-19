-- Step 1: Create the database, load the merged CSV and build the typed raw table.
-- Prerequisite: run python/prepare_data.py first (it creates data/raw/online_retail_II.csv).
-- Run this file once on an empty database (re-running fails because the tables already exist).
-- LOAD DATA LOCAL INFILE needs:  SET GLOBAL local_infile = 1;
-- and the client connection must allow it (MySQL Workbench: connection > Advanced > Others: OPT_LOCAL_INFILE=1).

CREATE DATABASE IF NOT EXISTS retail_seg CHARACTER SET utf8mb4;
USE retail_seg;

-- 1. Staging table: every column as text, so the load never fails on formats
CREATE TABLE stg_online_retail (
    invoice       VARCHAR(20),
    stock_code    VARCHAR(30),
    description   VARCHAR(255),
    quantity      VARCHAR(20),
    invoice_date  VARCHAR(30),
    price         VARCHAR(20),
    customer_id   VARCHAR(20),
    country       VARCHAR(60),
    source_sheet  VARCHAR(20)
);

-- 2. Typed raw table: the untouched base for all later cleaning (never modified afterwards)
CREATE TABLE transactions_raw (
    row_id        INT AUTO_INCREMENT PRIMARY KEY,
    invoice       VARCHAR(20) NOT NULL,
    stock_code    VARCHAR(30),
    description   VARCHAR(255),
    quantity      INT,
    invoice_date  DATETIME,
    price         DECIMAL(12,4),
    customer_id   INT NULL,
    country       VARCHAR(60),
    source_sheet  VARCHAR(20)
);

-- 3. Load the CSV into staging (replace <PATH_TO_PROJECT> with your project folder, use forward slashes)
-- Result: 1,067,371 rows (525,461 + 541,910 from the two sheets)
LOAD DATA LOCAL INFILE '<PATH_TO_PROJECT>/data/raw/online_retail_II.csv'
INTO TABLE stg_online_retail
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

-- 4. Convert text to proper types (empty description / customer ID become NULL)
INSERT INTO transactions_raw
    (invoice, stock_code, description, quantity, invoice_date,
     price, customer_id, country, source_sheet)
SELECT
    invoice,
    stock_code,
    NULLIF(description, ''),
    CAST(quantity AS SIGNED),
    STR_TO_DATE(invoice_date, '%Y-%m-%d %H:%i:%s'),
    CAST(price AS DECIMAL(12,4)),
    CAST(NULLIF(customer_id, '') AS UNSIGNED),
    country,
    source_sheet
FROM stg_online_retail;

-- 5. Indexes (created after the load, which is faster)
CREATE INDEX idx_cust ON transactions_raw (customer_id);
CREATE INDEX idx_date ON transactions_raw (invoice_date);
CREATE INDEX idx_inv  ON transactions_raw (invoice);

-- 6. Verification
-- Result: staging_rows = 1,067,371, typed_rows = 1,067,371, null_dates = 0
SELECT
    (SELECT COUNT(*) FROM stg_online_retail) AS staging_rows,
    (SELECT COUNT(*) FROM transactions_raw) AS typed_rows,
    (SELECT COUNT(*) FROM transactions_raw WHERE invoice_date IS NULL) AS null_dates;