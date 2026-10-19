-- Day 2: Cleaning audit (record ke liye)
-- Note: tables (tx_step1, tx_step2, transactions_clean) ban chuki hain.
-- Is file ko dobara run mat kijiye, CREATE TABLE error dega.
USE retail_seg;

-- 1. Overlap check: 1-9 Dec 2010 ki rows dono sheets mein exact copy hain ya nahi
-- Result: groups_s1 = 22,202, unmatched_in_s2 = 0 (exact copy)
WITH s1 AS (
  SELECT invoice, stock_code, description, quantity, invoice_date,
         price, customer_id, country, COUNT(*) AS c
  FROM transactions_raw
  WHERE source_sheet = 'Year 2009-2010' AND invoice_date >= '2010-12-01'
  GROUP BY invoice, stock_code, description, quantity, invoice_date,
           price, customer_id, country
),
s2 AS (
  SELECT invoice, stock_code, description, quantity, invoice_date,
         price, customer_id, country, COUNT(*) AS c
  FROM transactions_raw
  WHERE source_sheet = 'Year 2010-2011' AND invoice_date < '2010-12-10'
  GROUP BY invoice, stock_code, description, quantity, invoice_date,
           price, customer_id, country
)
SELECT COUNT(*) AS groups_s1,
       SUM(s2.invoice IS NULL) AS unmatched_in_s2
FROM s1 LEFT JOIN s2
  ON s1.invoice = s2.invoice
 AND s1.stock_code <=> s2.stock_code
 AND s1.description <=> s2.description
 AND s1.quantity = s2.quantity
 AND s1.invoice_date = s2.invoice_date
 AND s1.price = s2.price
 AND s1.customer_id <=> s2.customer_id
 AND s1.country = s2.country
 AND s1.c = s2.c;

-- 2. Overlap hata ke tx_step1 (1,067,371 - 22,523 = 1,044,848)
CREATE TABLE tx_step1 AS
SELECT * FROM transactions_raw
WHERE NOT (source_sheet = 'Year 2010-2011' AND invoice_date < '2010-12-10');

SELECT COUNT(*) AS rows_after_overlap FROM tx_step1;

-- 3. Exact duplicates gino
-- Result: dup_groups = 11,001, extra_rows = 11,812
SELECT COUNT(*) AS dup_groups, SUM(c - 1) AS extra_rows
FROM (
  SELECT COUNT(*) AS c FROM tx_step1
  GROUP BY invoice, stock_code, description, quantity,
           invoice_date, price, customer_id, country
  HAVING COUNT(*) > 1
) t;

-- 4. Duplicates hata ke tx_step2 (1,044,848 - 11,812 = 1,033,036)
CREATE TABLE tx_step2 AS
SELECT t.*
FROM tx_step1 t
JOIN (
  SELECT MIN(row_id) AS rid FROM tx_step1
  GROUP BY invoice, stock_code, description, quantity,
           invoice_date, price, customer_id, country
) k ON t.row_id = k.rid;

SELECT COUNT(*) AS rows_after_dedup FROM tx_step2;

-- 5. Negative quantity jo 'C' invoice mein nahi hain
-- Result: price 0, zyadatar description NULL (stock adjustments)
SELECT stock_code, description, COUNT(*) AS n,
       MIN(price) AS min_price, MAX(price) AS max_price
FROM tx_step2
WHERE quantity < 0 AND invoice NOT LIKE 'C%'
GROUP BY stock_code, description
ORDER BY n DESC
LIMIT 10;

-- 6. Zero ya negative price
-- Result: neg_price = 5, zero_price = 6,014, zero_price_pos_qty = 2,621
SELECT SUM(price < 0) AS neg_price,
       SUM(price = 0) AS zero_price,
       SUM(price = 0 AND quantity > 0) AS zero_price_pos_qty
FROM tx_step2
WHERE price <= 0;

-- Result: NULL 4,275, check 163, damaged 99, ? 90, damages 88, found 38, missing 30
SELECT description, COUNT(*) AS n
FROM tx_step2
WHERE price <= 0
GROUP BY description
ORDER BY n DESC
LIMIT 10;

-- 7. Non-standard stock codes (61 rows)
SELECT stock_code, MIN(description) AS sample_desc, COUNT(*) AS n
FROM tx_step2
WHERE stock_code NOT REGEXP '^[0-9]{5}'
GROUP BY stock_code
ORDER BY n DESC;

-- Baaki codes (43 rows): DCGS..., PADS asli products; CRUK, TEST001, B service/test
SELECT stock_code, MIN(description) AS sample_desc, COUNT(*) AS n
FROM tx_step2
WHERE stock_code NOT REGEXP '^[0-9]{5}'
  AND stock_code NOT IN ('POST','DOT','M','C2','D','S',
                         'BANK CHARGES','ADJUST','AMAZONFEE')
  AND stock_code NOT LIKE 'gift\_%'
GROUP BY stock_code
ORDER BY n DESC;

-- 8. transactions_clean: har row ko row_type diya, kuch delete nahi hua
CREATE TABLE transactions_clean AS
SELECT row_id, invoice, stock_code, description, quantity, invoice_date,
       price, customer_id, country, source_sheet,
       CASE
         WHEN invoice LIKE 'C%' THEN 'cancellation'
         WHEN stock_code IN ('POST','DOT','M','C2','D','S',
                             'BANK CHARGES','ADJUST','AMAZONFEE',
                             'CRUK','TEST001','B')
              OR stock_code LIKE 'gift\_%' THEN 'non_product'
         WHEN quantity <= 0 THEN 'neg_qty_other'
         WHEN price <= 0 THEN 'bad_price'
         ELSE 'sale'
       END AS row_type,
       (customer_id IS NULL) AS is_guest,
       ROUND(quantity * price, 2) AS line_total
FROM tx_step2;

CREATE INDEX idx_c_cust ON transactions_clean (customer_id);
CREATE INDEX idx_c_date ON transactions_clean (invoice_date);
CREATE INDEX idx_c_type ON transactions_clean (row_type);

-- 9. Cleaning waterfall (row_type breakdown)
-- Result: sale 1,003,361 | cancellation 19,104 | non_product 4,605
--         neg_qty_other 3,393 | bad_price 2,573
SELECT row_type,
       COUNT(*) AS n_rows,
       ROUND(100 * COUNT(*) / (SELECT COUNT(*) FROM transactions_clean), 2) AS pct_rows,
       ROUND(SUM(line_total), 0) AS revenue
FROM transactions_clean
GROUP BY row_type
ORDER BY n_rows DESC;

-- 10. Guest rows aur usable customers (sale rows mein)
-- Result: non-guest 776,600 rows, 5,852 customers | guest 226,761 rows
SELECT is_guest,
       COUNT(*) AS n_rows,
       ROUND(SUM(line_total), 0) AS revenue,
       COUNT(DISTINCT customer_id) AS customers
FROM transactions_clean
WHERE row_type = 'sale'
GROUP BY is_guest;

-- 11. Outliers (sirf dekha, hataya nahi)
SELECT invoice, stock_code, description, quantity, price, line_total, customer_id
FROM transactions_clean
WHERE row_type = 'sale'
ORDER BY line_total DESC
LIMIT 10;

-- 12. Bade orders ke matching cancellations check
SELECT invoice, stock_code, quantity, price, invoice_date, customer_id, row_type
FROM transactions_clean
WHERE stock_code IN ('23843', '23166')
  AND ABS(quantity) IN (80995, 74215)
ORDER BY stock_code, invoice_date;