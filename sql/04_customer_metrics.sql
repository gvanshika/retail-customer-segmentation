-- Day 3: Customer metrics aur cohorts (record ke liye)
-- Note: view/tables ban chuki hain. Is file ko dobara run mat kijiye,
-- CREATE VIEW / CREATE TABLE error dega.
USE retail_seg;

-- 1. Analysis base: sirf asli sale rows, guest nahi,
--    aur 2 cancel hue bade orders (541431, 581483) exclude
CREATE VIEW v_sales AS
SELECT * FROM transactions_clean
WHERE row_type = 'sale'
  AND is_guest = 0
  AND invoice NOT IN ('541431', '581483');

-- 2. Base check
-- Result: 776,598 rows | 36,596 invoices | 5,852 customers | revenue 16,823,662
SELECT COUNT(*) AS rows_n,
       COUNT(DISTINCT invoice) AS invoices,
       COUNT(DISTINCT customer_id) AS customers,
       ROUND(SUM(line_total), 0) AS revenue,
       MIN(invoice_date) AS first_dt,
       MAX(invoice_date) AS last_dt
FROM v_sales;

-- 3. Invoice-level table (har invoice ki ek row)
CREATE TABLE invoice_summary AS
SELECT invoice,
       customer_id,
       MIN(invoice_date) AS invoice_ts,
       DATE(MIN(invoice_date)) AS invoice_day,
       COUNT(*) AS n_lines,
       SUM(quantity) AS units,
       ROUND(SUM(line_total), 2) AS revenue
FROM v_sales
GROUP BY invoice, customer_id;

-- Result: 36,596
SELECT COUNT(*) AS n_invoices FROM invoice_summary;

-- 4. Customer-level table
-- n_orders = frequency, total_revenue = monetary, last_order_date = recency
CREATE TABLE customer_metrics AS
SELECT customer_id,
       MIN(invoice_day) AS first_order_date,
       MAX(invoice_day) AS last_order_date,
       COUNT(*) AS n_orders,
       ROUND(SUM(revenue), 2) AS total_revenue,
       ROUND(AVG(revenue), 2) AS avg_order_value,
       SUM(units) AS total_units
FROM invoice_summary
GROUP BY customer_id;

CREATE INDEX idx_cm_cust ON customer_metrics (customer_id);

-- Result: 5,852 rows
SELECT * FROM customer_metrics LIMIT 10;

-- 5. Repeat vs one-time customers
-- Result: 5,852 | one_time 1,619 | repeat 4,233 | one_time_pct 27.7
SELECT COUNT(*) AS customers,
       SUM(n_orders = 1) AS one_time,
       SUM(n_orders > 1) AS repeat_customers,
       ROUND(100 * SUM(n_orders = 1) / COUNT(*), 1) AS one_time_pct
FROM customer_metrics;

-- 6. Revenue concentration (decile 1 = top 10% customers)
-- Result: decile 1 = 63.4%, decile 2 = 13.5%, decile 3 = 7.9% ... decile 10 = 0.4%
SELECT decile,
       COUNT(*) AS customers,
       ROUND(SUM(total_revenue), 0) AS revenue,
       ROUND(100 * SUM(total_revenue) / (SELECT SUM(total_revenue) FROM customer_metrics), 1) AS pct_of_revenue
FROM (
  SELECT customer_id, total_revenue,
         NTILE(10) OVER (ORDER BY total_revenue DESC) AS decile
  FROM customer_metrics
) t
GROUP BY decile
ORDER BY decile;

-- 7. Recency (reference date 2011-12-10, dataset ka aakhri din 2011-12-09)
-- Result: 30d 1,626 | 90d 2,884 | 180d 3,470 | 365d 4,260
SELECT COUNT(*) AS customers,
       SUM(r <= 30)  AS bought_last_30d,
       SUM(r <= 90)  AS bought_last_90d,
       SUM(r <= 180) AS bought_last_180d,
       SUM(r <= 365) AS bought_last_365d
FROM (
  SELECT DATEDIFF('2011-12-10', last_order_date) AS r
  FROM customer_metrics
) t;

-- 8. Purchase gaps (inactivity window decide karne ke liye)
-- Result: 30,744 gaps | avg 52.1 | same day 12.1% | 30d 55.2% | 60d 74.4%
--         90d 82.9% | 180d ~93%
WITH g AS (
  SELECT customer_id,
         DATEDIFF(invoice_day,
                  LAG(invoice_day) OVER (PARTITION BY customer_id
                                         ORDER BY invoice_day, invoice)) AS gap
  FROM invoice_summary
)
SELECT COUNT(gap) AS n_gaps,
       ROUND(AVG(gap), 1) AS avg_gap_days,
       ROUND(100 * SUM(gap = 0) / COUNT(gap), 1) AS pct_same_day,
       ROUND(100 * SUM(gap <= 30) / COUNT(gap), 1) AS pct_within_30d,
       ROUND(100 * SUM(gap <= 60) / COUNT(gap), 1) AS pct_within_60d,
       ROUND(100 * SUM(gap <= 90) / COUNT(gap), 1) AS pct_within_90d,
       ROUND(100 * SUM(gap <= 180) / COUNT(gap), 1) AS pct_within_180d
FROM g
WHERE gap IS NOT NULL;

-- 9. Cohort tables
-- Result: customer_months 25,503 rows | cohort_retention 325 rows
CREATE TABLE customer_months AS
SELECT DISTINCT customer_id,
       DATE_SUB(invoice_day, INTERVAL DAYOFMONTH(invoice_day) - 1 DAY) AS activity_month
FROM invoice_summary;

CREATE TABLE cohort_retention AS
SELECT c.cohort_month,
       TIMESTAMPDIFF(MONTH, c.cohort_month, m.activity_month) AS month_index,
       COUNT(DISTINCT m.customer_id) AS active_customers
FROM (
  SELECT customer_id, MIN(activity_month) AS cohort_month
  FROM customer_months
  GROUP BY customer_id
) c
JOIN customer_months m ON m.customer_id = c.customer_id
GROUP BY c.cohort_month, month_index;

-- 10. Retention % (Dec 2009 cohort: size 952, month 1 = 35.0%, month 11 = 49.6%)
SELECT r.cohort_month, r.month_index, r.active_customers, s.cohort_size,
       ROUND(100 * r.active_customers / s.cohort_size, 1) AS retention_pct
FROM cohort_retention r
JOIN (SELECT cohort_month, active_customers AS cohort_size
      FROM cohort_retention WHERE month_index = 0) s
  ON s.cohort_month = r.cohort_month
ORDER BY r.cohort_month, r.month_index;