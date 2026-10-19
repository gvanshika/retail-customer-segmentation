-- Verification checks: recompute the README's headline numbers directly from the database.
-- Read-only (SELECT only), safe to run any time. Expected values are in the comments.
USE retail_seg;

-- 1. Cleaning waterfall. Expected: 1,067,371 | 1,044,848 | 1,033,036 | 1,003,361 | 776,598
SELECT step_no, step_name, rows_n FROM cleaning_waterfall ORDER BY step_no;

-- 2. Overlap between the two source sheets. Expected: 22,523 rows
SELECT COUNT(*) AS overlap_rows_in_second_sheet
FROM transactions_raw
WHERE source_sheet = 'Year 2010-2011' AND invoice_date < '2010-12-10';

-- 3. Customers and revenue in the analysis base. Expected: 5,852 customers, revenue 16,823,662
SELECT COUNT(*) AS customers, ROUND(SUM(monetary), 0) AS revenue FROM customer_360;

-- 4. Segment shares. Expected: Champions 25.8% of customers, 71.0% of revenue
SELECT segment,
       COUNT(*) AS customers,
       ROUND(100 * COUNT(*) / (SELECT COUNT(*) FROM customer_360), 1) AS pct_customers,
       ROUND(100 * SUM(monetary) / (SELECT SUM(monetary) FROM customer_360), 1) AS pct_revenue
FROM customer_360
GROUP BY segment
ORDER BY pct_revenue DESC;

-- 5. One-time customers. Expected: 27.7%
SELECT ROUND(100 * AVG(frequency = 1), 1) AS pct_one_time FROM customer_360;

-- 6. Revenue concentration. Expected: top decile (top 10% of customers) = 63.4% of revenue
SELECT ROUND(100 * SUM(CASE WHEN d = 1 THEN monetary END) / SUM(monetary), 1) AS top10_pct_revenue
FROM (SELECT monetary, NTILE(10) OVER (ORDER BY monetary DESC) AS d FROM customer_360) t;

-- 7. Risk bands. Expected: High 2,718 | Medium 1,575 | Low 1,559
SELECT risk_band, COUNT(*) AS customers FROM customer_360 GROUP BY risk_band;

-- 8. Leakage guards. Expected: min recency = 1 and min tenure = 1 in both datasets
SELECT (SELECT MIN(recency_days) FROM churn_dataset) AS churn_min_recency,
       (SELECT MIN(tenure_days)  FROM churn_dataset) AS churn_min_tenure,
       (SELECT MIN(recency_days) FROM clv_dataset)   AS clv_min_recency;

-- 9. No missing model outputs. Expected: all four = 0
SELECT SUM(churn_prob IS NULL) AS no_churn, SUM(clv_6m IS NULL) AS no_clv,
       SUM(kmeans_cluster IS NULL) AS no_cluster, SUM(expected_loss IS NULL) AS no_loss
FROM customer_360;

-- 10. Simulator (10% discount, 30% margin, contact cost 1). Expected net profit for
--     'All High-risk' at save rates 5% / 10% / 20%: -6,187 | -3,659 | +1,397
SELECT strategy, save_rate, net_profit
FROM simulator_scenarios
WHERE strategy = 'All High-risk'
ORDER BY save_rate;