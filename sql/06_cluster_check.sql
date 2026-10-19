-- Day 5: K-means clusters ka check (record ke liye)
-- Note: table customer_clusters Python script (05_kmeans.py) ne banayi hai.
USE retail_seg;

-- 1. Har cluster mein customers
-- Result: cluster 0 = 1,955 | 1 = 1,193 | 2 = 1,444 | 3 = 1,260 | sum 5,852
SELECT kmeans_cluster, COUNT(*) AS customers
FROM customer_clusters
GROUP BY kmeans_cluster
ORDER BY kmeans_cluster;

-- 2. Har customer ko cluster mila ya nahi (0 aana chahiye)
SELECT COUNT(*) AS customers_without_cluster
FROM rfm_segments s
LEFT JOIN customer_clusters c ON c.customer_id = s.customer_id
WHERE c.kmeans_cluster IS NULL;