-- Day 1: Profiling queries (raw data dekhna, kuch badalna nahi)
USE retail_seg;

-- 0. Load verification
SELECT
    (SELECT COUNT(*) FROM stg_online_retail) AS staging_rows,
    (SELECT COUNT(*) FROM transactions_raw) AS typed_rows,
    (SELECT COUNT(*) FROM transactions_raw WHERE invoice_date IS NULL) AS null_dates;

-- 1. Sheet-wise rows aur date range
SELECT source_sheet,
       COUNT(*) AS n_rows,
       MIN(invoice_date) AS first_dt,
       MAX(invoice_date) AS last_dt
FROM transactions_raw
GROUP BY source_sheet;

-- 2. Overall scale
SELECT COUNT(*) AS rows_total,
       COUNT(DISTINCT invoice) AS invoices,
       COUNT(DISTINCT customer_id) AS customers,
       COUNT(DISTINCT stock_code) AS products,
       COUNT(DISTINCT country) AS countries
FROM transactions_raw;

-- 3. Missing values
SELECT SUM(customer_id IS NULL) AS null_customer,
       SUM(description IS NULL) AS null_desc,
       ROUND(100 * SUM(customer_id IS NULL) / COUNT(*), 2) AS null_cust_pct
FROM transactions_raw;

-- 4. Cancellations (invoice 'C' se shuru)
SELECT COUNT(*) AS cancel_rows,
       COUNT(DISTINCT invoice) AS cancel_invoices
FROM transactions_raw
WHERE invoice LIKE 'C%';

-- 5. Negative / zero quantity aur price
SELECT SUM(quantity < 0) AS neg_qty,
       SUM(quantity = 0) AS zero_qty,
       SUM(price <= 0)   AS zero_or_neg_price
FROM transactions_raw;

-- 6. Non-product stock codes (postage, fees, adjustments)
SELECT stock_code, COUNT(*) AS n
FROM transactions_raw
WHERE stock_code NOT REGEXP '^[0-9]{5}'
GROUP BY stock_code
ORDER BY n DESC
LIMIT 30;

-- 7. Dono sheets ka overlap (1-9 Dec 2010)
SELECT source_sheet, COUNT(*) AS n
FROM transactions_raw
WHERE invoice_date >= '2010-12-01' AND invoice_date < '2010-12-10'
GROUP BY source_sheet;

-- 8. Exact duplicate rows (heavy query, ~35 sec; Workbench read timeout 600 sec hona chahiye)
SELECT COUNT(*) AS dup_groups,
       SUM(c - 1) AS extra_rows
FROM (
    SELECT COUNT(*) AS c
    FROM transactions_raw
    GROUP BY invoice, stock_code, description, quantity,
             invoice_date, price, customer_id, country
    HAVING COUNT(*) > 1
) t;

-- 9. Country-wise rows
SELECT country, COUNT(*) AS n
FROM transactions_raw
GROUP BY country
ORDER BY n DESC;