/*=====================================================================
RetailX — Omnichannel Analytics
Level 1: Data Profiling & Data Quality Checks
=======================================================================
Purpose : Before trusting any KPI or dashboard number, it is important
          to validate the raw data — row counts, date ranges,
          NULL patterns, categorical consistency, and logical
          impossibilities. Findings are documented inline and also
          summarized in data_quality_log.md.

Tables  : campaigns, customers, products, stores, marketing_spend,
          marketing_touchpoints, sessions, orders, order_items, returns
=======================================================================*/


/*---------------------------------------------------------------------
  1. Row counts and date ranges per table
  Goal: To confirm every table is loaded with the expected volume, and 
  that every date column falls within a sensible range before doing any
  further analysis.
---------------------------------------------------------------------*/

SELECT 
COUNT(*) AS number_of_campaigns, 
MIN(start_date) AS campaigns_start,
MAX(end_date) AS campaigns_end
FROM source.campaigns;

SELECT 
COUNT(*) AS number_of_customers,
MIN(signup_date) AS first_signup, 
MAX(signup_date) AS last_signup,
MIN(acquisition_date) AS first_cust_acq_date,
MAX(acquisition_date) AS last_cust_acq_date
FROM source.customers;

SELECT
COUNT(*) AS number_of_rows, 
MIN(date) AS first_spend, 
MAX(date) AS last_spend
FROM source.marketing_spend;

SELECT
COUNT(*) AS number_of_touchpoints,
MIN(timestamp) AS first_tp, 
MAX(timestamp) AS last_tp
FROM source.marketing_touchpoints;

SELECT
COUNT(*) AS number_of_items
FROM source.order_items;

SELECT
COUNT(*) AS number_of_orders,
MIN(order_date) AS first_order,
MAX(order_date) AS last_order
FROM source.orders;

SELECT 
COUNT(*) AS number_of_products
FROM source.products;

SELECT
COUNT(*) AS number_of_returns, 
MIN(return_date) AS first_return,
MAX(return_date) AS last_return
FROM source.returns;

SELECT 
COUNT(*) AS number_of_sessions,
MIN(CAST(session_start AS DATE)) AS first_session_date,
MAX(CAST(session_start AS DATE)) AS last_session_date
FROM source.sessions;

SELECT
COUNT(*) AS number_of_stores
FROM source.stores;

/*FINDING: customers.acquisition_date starts 2022-12-29, three days before
the dataset's official window (2023-01-01). See the isolated check below.*/

/*FINDING: returns.last_return (2025-01-19) falls after orders.last_order
(2024-12-30). This is expected right-censoring: late-December orders can
still be returned after the dataset's snapshot date. Return-rate KPIs
for the final ~3 weeks of the dataset will understate true returns and
should be flagged or excluded in Level 2 analysis.*/


/*---------------------------------------------------------------------
  Sanity check: touchpoint timestamps should fall within their own
  campaign's active window.
---------------------------------------------------------------------*/
SELECT 
COUNT(*) AS touchpoints_outside_campaign_window
FROM source.marketing_touchpoints tp
JOIN source.campaigns c ON tp.campaign_id = c.campaign_id
WHERE tp.timestamp < c.start_date OR tp.timestamp > c.end_date;
-- RESULT: 0. 
-- All 520,000 touchpoints validated against their campaign's start/end dates.


/*---------------------------------------------------------------------
  Isolate the 47 customers acquired before the dataset's official window
---------------------------------------------------------------------*/
SELECT 
COUNT(*) AS affected_customers
FROM source.customers
WHERE acquisition_date < '2023-01-01';
-- RESULT: 47 of 30,000 (0.16%). 
-- Decision: Retain and flag rather than delete

/*---------------------------------------------------------------------
  Q2. Referential integrity (orphan checks)
  Goal: To confirm every foreign-key-style relationship has zero orphans.
---------------------------------------------------------------------*/

-- orders -> customers
SELECT COUNT(*) FROM source.orders;
SELECT COUNT(*) FROM source.orders o JOIN source.customers c ON o.customer_id = c.customer_id;

-- order_items -> orders
SELECT COUNT(*) FROM source.order_items;
SELECT COUNT(*) FROM source.order_items oi JOIN source.orders o ON oi.order_id = o.order_id;

-- order_items -> products
SELECT COUNT(*) FROM source.order_items oi JOIN source.products p ON oi.product_id = p.product_id;

-- returns -> orders
SELECT COUNT(*) FROM source.returns;
SELECT COUNT(*) FROM source.returns r JOIN source.orders o ON r.order_id = o.order_id;

-- marketing_touchpoints -> campaigns
SELECT COUNT(*) FROM source.marketing_touchpoints;
SELECT COUNT(*) FROM source.marketing_touchpoints tp JOIN source.campaigns c ON tp.campaign_id = c.campaign_id;

-- RESULT: all five relationships show matching counts -> zero orphans.

/*---------------------------------------------------------------------
  Q3. NULL pattern checks — customers, orders, sessions
  Goal: find every NULL, then explain WHY using another column, then
  verify the explanation holds for 100% of rows (not just "most").
---------------------------------------------------------------------*/

-- Blanket NULL check across every column, one table at a time
SELECT
    SUM(CASE WHEN customer_id IS NULL THEN 1 ELSE 0 END) AS null_customer_id,
    SUM(CASE WHEN signup_date IS NULL THEN 1 ELSE 0 END) AS null_signup_date,
    SUM(CASE WHEN gender IS NULL THEN 1 ELSE 0 END) AS null_gender,
    SUM(CASE WHEN age_group IS NULL THEN 1 ELSE 0 END) AS null_age_group,
    SUM(CASE WHEN city IS NULL THEN 1 ELSE 0 END) AS null_city,
    SUM(CASE WHEN state IS NULL THEN 1 ELSE 0 END) AS null_state,
    SUM(CASE WHEN acquisition_date IS NULL THEN 1 ELSE 0 END) AS null_acq_date,
    SUM(CASE WHEN acquisition_channel IS NULL THEN 1 ELSE 0 END) AS null_acq_channel
FROM source.customers;
-- (repeat the same for source.orders and source.sessions)

-- customers.acquisition_campaign_id: NULL for Organic/Direct customers?
SELECT acquisition_channel,
       COUNT(*) AS total,
       COUNT(acquisition_campaign_id) AS non_null_campaign_id,
       COUNT(*) - COUNT(acquisition_campaign_id) AS null_campaign_id
FROM source.customers
GROUP BY acquisition_channel
ORDER BY acquisition_channel;
-- RESULT: 100% NULL for Organic/Direct, 100% populated for every paid channel.
-- Expected business logic, not missing data.

-- orders.store_id: NULL for Online orders?
SELECT sales_channel,
       COUNT(*) AS total_orders,
       COUNT(store_id) AS has_store_id,
       COUNT(*) - COUNT(store_id) AS null_store_id
FROM source.orders
GROUP BY sales_channel;
-- RESULT: Online = 71,115 total / 71,115 null (100%).
--         In-Store = 33,885 total / 0 null (100% populated).

-- sessions.campaign_id: NULL for Direct / Organic Search sessions?
SELECT source,
       COUNT(*) AS total_sessions,
       COUNT(campaign_id) AS has_campaign_id,
       COUNT(*) - COUNT(campaign_id) AS null_campaign_id
FROM source.sessions
GROUP BY source;
-- RESULT: 100% NULL for Direct and Organic Search, 100% populated for every paid source
-- Expected business logic, not missing data.


/*---------------------------------------------------------------------
  Q4. Categorical consistency checks
  Goal: catch casing, whitespace, or near-duplicate category values
  before they silently split a GROUP BY into two "different" buckets.
---------------------------------------------------------------------*/

SELECT DISTINCT channel, LEN(channel) - LEN(TRIM(channel)) AS whitespace_chars
FROM source.campaigns
WHERE LEN(channel) <> LEN(TRIM(channel));

SELECT DISTINCT sales_channel, LEN(sales_channel) - LEN(TRIM(sales_channel)) AS whitespace_chars
FROM source.orders
WHERE LEN(sales_channel) <> LEN(TRIM(sales_channel));

SELECT DISTINCT order_status, LEN(order_status) - LEN(TRIM(order_status)) AS whitespace_chars
FROM source.orders
WHERE LEN(order_status) <> LEN(TRIM(order_status));

SELECT DISTINCT payment_method, LEN(payment_method) - LEN(TRIM(payment_method)) AS whitespace_chars
FROM source.orders
WHERE LEN(payment_method) <> LEN(TRIM(payment_method));

SELECT DISTINCT device, LEN(device) - LEN(TRIM(device)) AS whitespace_chars
FROM source.sessions
WHERE LEN(device) <> LEN(TRIM(device));

-- RESULT: all five queries return zero rows. No whitespace or casing
-- issues found in any categorical column checked.


/*---------------------------------------------------------------------
  Q5. Logical impossibilities
  Goal: To find values that shouldn't exist regardless of business
  context — these are bugs to flag, not patterns to explain away.
---------------------------------------------------------------------*/

-- clicks should never exceed impressions
SELECT * FROM source.marketing_spend WHERE clicks > impressions;

-- spend should never be negative
SELECT * FROM source.marketing_spend WHERE spend < 0;

-- a campaign can't end before it starts
SELECT * FROM source.campaigns WHERE end_date < start_date;

-- a customer can't order before they existed as a customer
SELECT o.order_id, o.customer_id, o.order_date, c.signup_date
FROM source.orders o
JOIN source.customers c ON o.customer_id = c.customer_id
WHERE o.order_date < c.signup_date;

-- a refund shouldn't exceed the value of the specific item returned
-- (unit_price * quantity, net of that item's own discount)
SELECT r.return_id, r.order_id, r.product_id, r.refund_amount,
       oi.quantity, oi.unit_price, oi.discount_amount,
       (oi.unit_price * oi.quantity - oi.discount_amount) AS item_line_value
FROM source.returns r
JOIN source.order_items oi
    ON r.order_id = oi.order_id AND r.product_id = oi.product_id
WHERE r.refund_amount > (oi.unit_price * oi.quantity - oi.discount_amount);

SELECT COUNT(*) AS refund_exceeds_item_value
FROM source.returns r
JOIN source.order_items oi
    ON r.order_id = oi.order_id AND r.product_id = oi.product_id
WHERE r.refund_amount > (oi.unit_price * oi.quantity - oi.discount_amount);

/*RESULT: 6,889 of 19,971 returns (34.5%) exceed their own item's line
value. A looser order-level check (refund_amount > orders.net_amount)
returns 1,428 (7.2%). Root cause: refund_amount was calculated from
pre-discount unit_price x return_quantity, while item/order values are
post-discount. Material limitation — flag in any refund-based KPI.*/


/*---------------------------------------------------------------------
  Q6. net_amount reconciliation
  Goal: confirm net_amount = gross_amount - discount_amount + shipping_amount
---------------------------------------------------------------------*/
SELECT COUNT(*) AS mismatched_orders
FROM source.orders
WHERE ROUND(gross_amount - discount_amount + shipping_amount, 2) <> net_amount;

/*RESULT: 1,611 of 105,000 orders (1.53%) do not reconcile. gross_amount
and discount_amount are unaffected; only net_amount carries this gap.
Flag in any revenue analysis built on net_amount.*/

/*=====================================================================
END OF LEVEL 1
Summary of findings -> see data_quality_log.md
=======================================================================*/
