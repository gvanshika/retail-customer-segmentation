-- Day 4: RFM scoring aur segments (record ke liye)
-- Note: tables ban chuki hain. Is file ko dobara run mat kijiye,
-- CREATE TABLE / CREATE INDEX error dega.
USE retail_seg;

-- 1. RFM ki raw values (reference date 2011-12-10)
CREATE TABLE rfm_base AS
SELECT customer_id,
       DATEDIFF('2011-12-10', last_order_date) AS recency_days,
       n_orders AS frequency,
       total_revenue AS monetary
FROM customer_metrics;

-- Result: 5,852 | recency 1-739 | frequency 1-373 | monetary 2.90 - 580,987.04
SELECT COUNT(*) AS customers,
       MIN(recency_days) AS min_r, ROUND(AVG(recency_days), 0) AS avg_r, MAX(recency_days) AS max_r,
       MIN(frequency) AS min_f, ROUND(AVG(frequency), 1) AS avg_f, MAX(frequency) AS max_f,
       MIN(monetary) AS min_m, ROUND(AVG(monetary), 0) AS avg_m, MAX(monetary) AS max_m
FROM rfm_base;

-- 2. R, F, M ke scores (1-5), PERCENT_RANK se (ties mein same value ko same score)
CREATE TABLE rfm_scores AS
SELECT customer_id, recency_days, frequency, monetary,
       LEAST(5, 1 + FLOOR(5 * PERCENT_RANK() OVER (ORDER BY recency_days DESC))) AS r_score,
       LEAST(5, 1 + FLOOR(5 * PERCENT_RANK() OVER (ORDER BY frequency ASC)))     AS f_score,
       LEAST(5, 1 + FLOOR(5 * PERCENT_RANK() OVER (ORDER BY monetary ASC)))      AS m_score
FROM rfm_base;

-- Result: F: 1,619 | 944 | 1,148 | 1,025 | 1,116    M: ~1,170 har score par
SELECT 'R' AS metric, r_score AS score, COUNT(*) AS customers FROM rfm_scores GROUP BY r_score
UNION ALL
SELECT 'F', f_score, COUNT(*) FROM rfm_scores GROUP BY f_score
UNION ALL
SELECT 'M', m_score, COUNT(*) FROM rfm_scores GROUP BY m_score
ORDER BY 1, 2;

-- 3. Spot-check
-- Result: 18102 (5,5,5) | 13078 (5,5,5) | 13085 (3,4,4) | 15362 (1,2,3)
SELECT * FROM rfm_scores
WHERE customer_id IN (18102, 13078, 13085, 15362);

-- 4. Segments (heuristic rules)
CREATE TABLE rfm_segments AS
SELECT t.*,
       CASE
         WHEN r_score >= 4 AND fm_score >= 4 THEN 'Champions'
         WHEN r_score = 3  AND fm_score >= 4 THEN 'Loyal Customers'
         WHEN r_score <= 2 AND fm_score = 5  THEN 'Cannot Lose Them'
         WHEN r_score <= 2 AND fm_score >= 3 THEN 'At Risk'
         WHEN r_score >= 3 AND fm_score = 3  THEN 'Potential Loyalists'
         WHEN r_score >= 4 AND fm_score <= 2 THEN 'New / Promising'
         WHEN r_score = 3  AND fm_score <= 2 THEN 'Needs Attention'
         ELSE 'Hibernating'
       END AS segment
FROM (
  SELECT s.*, ROUND((f_score + m_score) / 2) AS fm_score
  FROM rfm_scores s
) t;

CREATE INDEX idx_rfm_seg ON rfm_segments (segment);

-- 5. Segment-wise summary
-- Result: Champions 1,509 (71.0% rev) | Loyal 567 | At Risk 605 | Hibernating 1,699
--         Cannot Lose Them 42 | Potential Loyalists 376 | New / Promising 577
--         Needs Attention 477 | customers ka sum 5,852
SELECT segment,
       COUNT(*) AS customers,
       ROUND(100 * COUNT(*) / (SELECT COUNT(*) FROM rfm_segments), 1) AS pct_customers,
       ROUND(SUM(monetary), 0) AS revenue,
       ROUND(100 * SUM(monetary) / (SELECT SUM(monetary) FROM rfm_segments), 1) AS pct_revenue,
       ROUND(AVG(recency_days), 0) AS avg_recency_days,
       ROUND(AVG(frequency), 1) AS avg_orders,
       ROUND(AVG(monetary), 0) AS avg_spend
FROM rfm_segments
GROUP BY segment
ORDER BY revenue DESC;

-- 6. Win-back list: Cannot Lose Them (top 10 by spend)
-- Result: 16754 (65,500) | 13093 (54,144) | 17850 (51,209) ...
SELECT customer_id, recency_days, frequency, monetary
FROM rfm_segments
WHERE segment = 'Cannot Lose Them'
ORDER BY monetary DESC
LIMIT 10;