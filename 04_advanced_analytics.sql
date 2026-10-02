
/*================================================
17. RFM Segmentation
==================================================*/

WITH recency AS
(SELECT *,
DATEDIFF(DAY,last_cust_order,last_order) AS gap_in_recent_order
FROM(
SELECT DISTINCT
customer_id,
MAX(order_date) OVER(PARTITION BY customer_id) AS last_cust_order,
MAX(order_date) OVER() AS last_order
FROM source.orders
WHERE order_status <> 'Cancelled')t),

frequnecy AS
(SELECT 
customer_id,
COUNT(*) AS number_of_orders
FROM source.orders
WHERE order_status <> 'Cancelled'
GROUP BY customer_id),

monetory AS
(SELECT 
customer_id,
COUNT(*) total_orders,
SUM(net_amount) AS total_value
FROM source.orders
WHERE order_status <> 'Cancelled'
GROUP BY customer_id),

rfm_model AS
(SELECT 
r.customer_id,
r.gap_in_recent_order,
f.number_of_orders,
m.total_value
FROM recency r
JOIN frequnecy f ON r.customer_id = f.customer_id
JOIN monetory m ON m.customer_id = r.customer_id)


SELECT *,
r_score + f_score + m_score AS total_score,
CASE
WHEN  r_score + f_score + m_score >= 12 THEN 'Champions'
WHEN  r_score + f_score + m_score >= 9 THEN 'Loyal Customers'
WHEN  r_score + f_score + m_score >= 6 THEN 'At risk'
ELSE 'Lost'
END AS 'segmentation' FROM(
SELECT 
customer_id,
gap_in_recent_order,
number_of_orders,
total_value,
NTILE(5) OVER (ORDER BY gap_in_recent_order DESC) r_score,
NTILE(5) OVER (ORDER BY number_of_orders ASC)  f_score,
NTILE(5) OVER (ORDER BY total_value ASC) m_score
FROM rfm_model)u
ORDER BY customer_id
