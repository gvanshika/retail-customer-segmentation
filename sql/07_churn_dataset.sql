-- Day 6 + Day 7: Inactivity prediction ke liye SQL (record ke liye)
-- Note: snapshots, churn_dataset aur scoring_dataset ban chuki hain.
-- Is file ko dobara run mat kijiye (CREATE TABLE error dega, INSERT rows double kar dega).
-- Koi query dekhni ho to sirf use select karke Ctrl + Enter dabaiye.
USE retail_seg;

-- ===== Day 6 =====

-- 1. Snapshots (90-90 din ke gap par)
CREATE TABLE snapshots (snap DATE);
INSERT INTO snapshots VALUES
  ('2010-09-14'), ('2010-12-13'), ('2011-03-13'), ('2011-06-11'), ('2011-09-09');

-- 2. Dataset: features snapshot se PEHLE ke orders se, label snapshot ke BAAD ke 90 din se
--    churned = 1 matlab snapshot ke baad agle 90 din mein koi order nahi
-- Result: 22,441 rows
CREATE TABLE churn_dataset AS
SELECT h.snap AS snapshot_date,
       h.customer_id,
       DATEDIFF(h.snap, h.last_order)  AS recency_days,
       h.n_orders                      AS frequency,
       ROUND(h.revenue, 2)             AS monetary,
       DATEDIFF(h.snap, h.first_order) AS tenure_days,
       ROUND(h.revenue / h.n_orders, 2) AS avg_order_value,
       ROUND(DATEDIFF(h.last_order, h.first_order) / NULLIF(h.n_orders - 1, 0), 1) AS avg_gap_days,
       IFNULL(r.orders_90d, 0)         AS orders_last_90d,
       ROUND(IFNULL(r.revenue_90d, 0), 2) AS revenue_last_90d,
       CASE WHEN f.customer_id IS NULL THEN 1 ELSE 0 END AS churned
FROM (
  SELECT s.snap, i.customer_id,
         MIN(i.invoice_day) AS first_order, MAX(i.invoice_day) AS last_order,
         COUNT(*) AS n_orders, SUM(i.revenue) AS revenue
  FROM snapshots s
  JOIN invoice_summary i ON i.invoice_day < s.snap
  GROUP BY s.snap, i.customer_id
) h
LEFT JOIN (
  SELECT s.snap, i.customer_id, COUNT(*) AS orders_90d, SUM(i.revenue) AS revenue_90d
  FROM snapshots s
  JOIN invoice_summary i
    ON i.invoice_day < s.snap AND i.invoice_day >= DATE_SUB(s.snap, INTERVAL 90 DAY)
  GROUP BY s.snap, i.customer_id
) r ON r.snap = h.snap AND r.customer_id = h.customer_id
LEFT JOIN (
  SELECT DISTINCT s.snap, i.customer_id
  FROM snapshots s
  JOIN invoice_summary i
    ON i.invoice_day >= s.snap AND i.invoice_day < DATE_ADD(s.snap, INTERVAL 90 DAY)
) f ON f.snap = h.snap AND f.customer_id = h.customer_id;

CREATE INDEX idx_cd_snap ON churn_dataset (snapshot_date);

-- 3. Safety check
-- Result: snapshot_rows = 5, dataset_rows = 22,441
SELECT (SELECT COUNT(*) FROM snapshots) AS snapshot_rows,
       (SELECT COUNT(*) FROM churn_dataset) AS dataset_rows;

-- 4a. Har snapshot par customers aur inactive %
-- Result: 2010-09-14: 3,364 | 1,430 | 42.5%
--         2010-12-13: 4,292 | 2,986 | 69.6%
--         2011-03-13: 4,581 | 2,965 | 64.7%
--         2011-06-11: 4,951 | 3,365 | 68.0%
--         2011-09-09: 5,253 | 2,975 | 56.6%
SELECT snapshot_date, COUNT(*) AS customers, SUM(churned) AS churned,
       ROUND(100 * AVG(churned), 1) AS churn_pct
FROM churn_dataset
GROUP BY snapshot_date
ORDER BY snapshot_date;

-- 4b. Leakage check: recency aur tenure kam se kam 1 hone chahiye
-- Result: min_recency = 1, min_tenure = 1, null_gap_rows = 7,321 (leakage nahi)
SELECT MIN(recency_days) AS min_recency, MIN(tenure_days) AS min_tenure,
       SUM(avg_gap_days IS NULL) AS null_gap_rows
FROM churn_dataset;

-- 4c. Sanity: recency badhne par inactive % badhna chahiye
-- Result: 0-30: 5,172 rows, 37.0% | 31-90: 5,040, 50.9% | 91-180: 4,825, 65.8% | 180+: 7,404, 82.0%
SELECT CASE WHEN recency_days <= 30 THEN '1) 0-30'
            WHEN recency_days <= 90 THEN '2) 31-90'
            WHEN recency_days <= 180 THEN '3) 91-180'
            ELSE '4) 180+' END AS recency_bucket,
       COUNT(*) AS rows_n,
       ROUND(100 * AVG(churned), 1) AS churn_pct
FROM churn_dataset
GROUP BY recency_bucket
ORDER BY recency_bucket;

-- 5. Baseline: rule "recency > 90 din => inactive", test snapshot par
-- Result: tp 2,390 | fp 975 | fn 585 | tn 1,303
--         precision 71.0% | recall 80.3% | accuracy 70.3%
SELECT SUM(recency_days > 90  AND churned = 1) AS tp,
       SUM(recency_days > 90  AND churned = 0) AS fp,
       SUM(recency_days <= 90 AND churned = 1) AS fn,
       SUM(recency_days <= 90 AND churned = 0) AS tn
FROM churn_dataset
WHERE snapshot_date = '2011-09-09';

-- ===== Day 7 =====

-- 6. Scoring dataset: wahi features, snapshot 2011-12-10 ke liye, bina label ke
--    (is date ke baad ka data hai hi nahi, isliye label nahi banta)
-- Result: rows_n = 5,852, min_recency = 1
CREATE TABLE scoring_dataset AS
SELECT CAST('2011-12-10' AS DATE) AS snapshot_date,
       h.customer_id,
       DATEDIFF('2011-12-10', h.last_order)  AS recency_days,
       h.n_orders                            AS frequency,
       ROUND(h.revenue, 2)                   AS monetary,
       DATEDIFF('2011-12-10', h.first_order) AS tenure_days,
       ROUND(h.revenue / h.n_orders, 2)      AS avg_order_value,
       ROUND(DATEDIFF(h.last_order, h.first_order) / NULLIF(h.n_orders - 1, 0), 1) AS avg_gap_days,
       IFNULL(r.orders_90d, 0)               AS orders_last_90d,
       ROUND(IFNULL(r.revenue_90d, 0), 2)    AS revenue_last_90d
FROM (
  SELECT customer_id, MIN(invoice_day) AS first_order, MAX(invoice_day) AS last_order,
         COUNT(*) AS n_orders, SUM(revenue) AS revenue
  FROM invoice_summary
  WHERE invoice_day < '2011-12-10'
  GROUP BY customer_id
) h
LEFT JOIN (
  SELECT customer_id, COUNT(*) AS orders_90d, SUM(revenue) AS revenue_90d
  FROM invoice_summary
  WHERE invoice_day < '2011-12-10'
    AND invoice_day >= DATE_SUB('2011-12-10', INTERVAL 90 DAY)
  GROUP BY customer_id
) r ON r.customer_id = h.customer_id;

SELECT COUNT(*) AS rows_n, MIN(recency_days) AS min_recency FROM scoring_dataset;

-- 7. churn_scores: Python script (07_churn_model.py) ne banayi hai
-- Result (Python output se): High 2,718 | Medium 1,575 | Low 1,559 | sum 5,852
-- avg_prob: High 0.854 | Medium 0.561 | Low 1,559 customers, 0.231
SELECT risk_band, COUNT(*) AS customers,
       ROUND(AVG(churn_prob), 3) AS avg_prob
FROM churn_scores
GROUP BY risk_band
ORDER BY avg_prob DESC;