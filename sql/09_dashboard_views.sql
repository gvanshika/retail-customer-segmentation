USE retail_seg;

-- 1. Monthly trend (sirf non-guest sale rows)
CREATE VIEW monthly_summary AS
SELECT DATE_SUB(invoice_day, INTERVAL DAYOFMONTH(invoice_day) - 1 DAY) AS month_start,
       COUNT(*) AS orders,
       COUNT(DISTINCT customer_id) AS active_customers,
       ROUND(SUM(revenue), 0) AS revenue
FROM invoice_summary
GROUP BY month_start
ORDER BY month_start;

-- 2. Cohort retention % (heatmap ke liye)
CREATE VIEW cohort_retention_pct AS
SELECT r.cohort_month, r.month_index, r.active_customers, s.cohort_size,
       ROUND(100 * r.active_customers / s.cohort_size, 1) AS retention_pct
FROM cohort_retention r
JOIN (SELECT cohort_month, active_customers AS cohort_size
      FROM cohort_retention WHERE month_index = 0) s
  ON s.cohort_month = r.cohort_month;

-- 3. Data cleaning waterfall (Data Quality page ke liye)
CREATE VIEW cleaning_waterfall AS
SELECT 1 AS step_no, 'Raw rows' AS step_name, COUNT(*) AS rows_n FROM transactions_raw
UNION ALL SELECT 2, 'After overlap removed', COUNT(*) FROM tx_step1
UNION ALL SELECT 3, 'After duplicates removed', COUNT(*) FROM tx_step2
UNION ALL SELECT 4, 'Valid sale rows', COUNT(*) FROM transactions_clean WHERE row_type = 'sale'
UNION ALL SELECT 5, 'Analysis base (non-guest, 2 outliers removed)', COUNT(*) FROM v_sales;

-- 4. Segment ke hisaab se recommended action
CREATE TABLE segment_actions (segment VARCHAR(30), action VARCHAR(120), priority INT);
INSERT INTO segment_actions VALUES
  ('Cannot Lose Them',    'Personal outreach (top priority)', 1),
  ('At Risk',             'Win-back offer', 2),
  ('Champions',           'Reward, early access, referral', 3),
  ('Loyal Customers',     'Upsell, loyalty program', 4),
  ('Potential Loyalists', 'Nudge for repeat purchase', 5),
  ('New / Promising',     'Onboarding offer', 6),
  ('Needs Attention',     'Reminder, limited-time offer', 7),
  ('Hibernating',         'Low-cost reactivation or ignore', 8);


  SELECT (SELECT COUNT(*) FROM monthly_summary) AS months,
       (SELECT COUNT(*) FROM cohort_retention_pct) AS cohort_rows,
       (SELECT COUNT(*) FROM cleaning_waterfall) AS waterfall_rows,
       (SELECT COUNT(*) FROM segment_actions) AS actions;

SELECT * FROM cleaning_waterfall ORDER BY step_no;