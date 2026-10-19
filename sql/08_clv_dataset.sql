-- Day 8: CLV dataset aur customer_360 view (record ke liye)
-- Note: tables aur view ban chuke hain. Is file ko dobara run mat kijiye
-- (CREATE TABLE / CREATE VIEW error dega, INSERT rows double kar dega).
USE retail_seg;

-- 1. Snapshots: 3 labelled (180-din ke windows jo overlap nahi karte) + 1 scoring (aaj ki date)
CREATE TABLE clv_snapshots (snap DATE);
INSERT INTO clv_snapshots VALUES
  ('2010-06-16'), ('2010-12-13'), ('2011-06-11'), ('2011-12-10');

-- 2. Dataset: features snapshot se PEHLE ke orders se, target (future_rev_180d) snapshot ke BAAD ke 180 din se
--    Aakhri snapshot (2011-12-10) ka target NULL hai (uske baad ka data hai hi nahi)
-- Result: 17,927 rows
CREATE TABLE clv_dataset AS
SELECT h.snap AS snapshot_date,
       h.customer_id,
       DATEDIFF(h.snap, h.last_order)   AS recency_days,
       h.n_orders                       AS frequency,
       ROUND(h.revenue, 2)              AS monetary,
       DATEDIFF(h.snap, h.first_order)  AS tenure_days,
       ROUND(h.revenue / h.n_orders, 2) AS avg_order_value,
       ROUND(DATEDIFF(h.last_order, h.first_order) / NULLIF(h.n_orders - 1, 0), 1) AS avg_gap_days,
       IFNULL(r90.n, 0)                 AS orders_last_90d,
       ROUND(IFNULL(r90.rev, 0), 2)     AS revenue_last_90d,
       IFNULL(r180.n, 0)                AS orders_last_180d,
       ROUND(IFNULL(r180.rev, 0), 2)    AS revenue_last_180d,
       CASE WHEN h.snap > '2011-06-13' THEN NULL
            ELSE ROUND(IFNULL(f.rev, 0), 2) END AS future_rev_180d
FROM (
  SELECT s.snap, i.customer_id,
         MIN(i.invoice_day) AS first_order, MAX(i.invoice_day) AS last_order,
         COUNT(*) AS n_orders, SUM(i.revenue) AS revenue
  FROM clv_snapshots s
  JOIN invoice_summary i ON i.invoice_day < s.snap
  GROUP BY s.snap, i.customer_id
) h
LEFT JOIN (
  SELECT s.snap, i.customer_id, COUNT(*) AS n, SUM(i.revenue) AS rev
  FROM clv_snapshots s
  JOIN invoice_summary i
    ON i.invoice_day < s.snap AND i.invoice_day >= DATE_SUB(s.snap, INTERVAL 90 DAY)
  GROUP BY s.snap, i.customer_id
) r90 ON r90.snap = h.snap AND r90.customer_id = h.customer_id
LEFT JOIN (
  SELECT s.snap, i.customer_id, COUNT(*) AS n, SUM(i.revenue) AS rev
  FROM clv_snapshots s
  JOIN invoice_summary i
    ON i.invoice_day < s.snap AND i.invoice_day >= DATE_SUB(s.snap, INTERVAL 180 DAY)
  GROUP BY s.snap, i.customer_id
) r180 ON r180.snap = h.snap AND r180.customer_id = h.customer_id
LEFT JOIN (
  SELECT s.snap, i.customer_id, SUM(i.revenue) AS rev
  FROM clv_snapshots s
  JOIN invoice_summary i
    ON i.invoice_day >= s.snap AND i.invoice_day < DATE_ADD(s.snap, INTERVAL 180 DAY)
  GROUP BY s.snap, i.customer_id
) f ON f.snap = h.snap AND f.customer_id = h.customer_id;

CREATE INDEX idx_clv_snap ON clv_dataset (snapshot_date);

-- 3. Check: har snapshot par customers aur future revenue
-- Result: 4 rows; 2011-12-10 par customers = 5,852 aur future wale columns NULL
SELECT snapshot_date, COUNT(*) AS customers,
       ROUND(100 * AVG(future_rev_180d > 0), 1) AS pct_with_future_revenue,
       ROUND(AVG(future_rev_180d), 0) AS avg_future_rev,
       MIN(recency_days) AS min_recency
FROM clv_dataset
GROUP BY snapshot_date
ORDER BY snapshot_date;

-- 4. customer_360: Power BI ke liye sab tables ek view mein
--    (customer_clv, customer_value_at_risk Python scripts ne banayi hain)
CREATE VIEW customer_360 AS
SELECT s.customer_id, s.segment, c.kmeans_cluster,
       s.recency_days, s.frequency, s.monetary,
       k.churn_prob, k.risk_band,
       v.clv_6m, r.value_90d, r.expected_loss
FROM rfm_segments s
LEFT JOIN customer_clusters c ON c.customer_id = s.customer_id
LEFT JOIN churn_scores k ON k.customer_id = s.customer_id
LEFT JOIN customer_clv v ON v.customer_id = s.customer_id
LEFT JOIN customer_value_at_risk r ON r.customer_id = s.customer_id;

-- Result: customers = 5,852, no_churn = 0, no_clv = 0, no_cluster = 0, no_loss = 0
SELECT COUNT(*) AS customers,
       SUM(churn_prob IS NULL) AS no_churn,
       SUM(clv_6m IS NULL) AS no_clv,
       SUM(kmeans_cluster IS NULL) AS no_cluster,
       SUM(expected_loss IS NULL) AS no_loss
FROM customer_360;