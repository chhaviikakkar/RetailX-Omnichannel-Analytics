/*=====================================================================
RetailX — Omnichannel Analytics
Level 2: Core KPIs
=======================================================================
Purpose : Answer core business questions — revenue, channel efficiency,
          budget discipline, category/brand profitability, and returns —
          using the data validated in 01_data_profiling.sql.

Business rules established and used throughout this script:
  - Revenue is recognized at order placement (Completed, Returned,
    Pending). Cancelled orders are excluded — no payment was retained,
    regardless of whether the order was paid-then-cancelled or never
    fulfilled; the data can't distinguish the two, so the safe
    assumption is zero revenue.
  - Refunds are tracked as a separate metric, not netted against
    revenue (standard "recognize then reverse" accounting treatment).
  - refund_amount has a known data quality issue (see
    data_quality_log.md, finding #5) — refund KPIs here use return
    COUNT, which is unaffected, rather than treating refund_amount as
    fully reconciled.

Author  : [Your Name]
Dataset : RetailX synthetic omnichannel retail dataset
=======================================================================*/


/*---------------------------------------------------------------------
  Q7. Revenue, order count, and AOV by sales_channel
---------------------------------------------------------------------*/
SELECT
    sales_channel,
    COUNT(*) AS order_count,
    SUM(net_amount) AS total_revenue,
    AVG(net_amount) AS aov
FROM source.orders
WHERE order_status <> 'Cancelled'
GROUP BY sales_channel;

-- FINDING: Online generates ~68% of revenue (Rs.168.7M... scale depends
-- on currency formatting) across 66,191 orders; In-Store generates ~32%
-- across 31,456 orders — roughly 2.1x the order volume for Online, but
-- In-Store has a marginally higher AOV. Excluding Cancelled orders (7%
-- of total) shifted AOV by <0.1%, i.e. cancellations aren't concentrated
-- at either end of the order-value spectrum.


/*---------------------------------------------------------------------
  Q9. CTR and CPC by marketing channel
---------------------------------------------------------------------*/
SELECT
    c.channel,
    SUM(m.spend) AS total_spend,
    SUM(m.impressions) AS total_impressions,
    SUM(m.clicks) AS total_clicks,
    ROUND(CAST(SUM(m.clicks) AS FLOAT) * 100 / SUM(m.impressions), 2) AS click_through_rate_pct,
    ROUND(SUM(m.spend) / CAST(SUM(m.clicks) AS FLOAT), 2) AS cost_per_click
FROM source.marketing_spend m
JOIN source.campaigns c ON c.campaign_id = m.campaign_id
GROUP BY c.channel
ORDER BY cost_per_click ASC;

-- NOTE: cost_per_click must be spend / clicks. An earlier draft computed
-- clicks / spend by mistake, which inverted the entire ranking — a
-- channel that looked "cheap" was actually the most expensive. Always
-- sanity-check a rate/ratio column against plain-language intuition
-- before trusting it.
--
-- FINDING: Influencer marketing has the best combination of engagement
-- and cost-efficiency (3.40% CTR, Rs.9.99 CPC). SMS underperforms on
-- both dimensions (2.40% CTR, Rs.15.94 CPC) despite the second-highest
-- spend allocation — a strong candidate for budget reallocation.


/*---------------------------------------------------------------------
  Q10. Campaign spend vs. budget — who overspent, and by how much
---------------------------------------------------------------------*/
SELECT
    m.campaign_id,
    c.channel,
    c.budget,
    SUM(m.spend) AS total_spend,
    SUM(m.spend) - c.budget AS overspend_amount,               -- positive = overspent
    ROUND((SUM(m.spend) - c.budget) * 100.0 / c.budget, 2) AS overspend_pct
FROM source.marketing_spend m
JOIN source.campaigns c ON c.campaign_id = m.campaign_id
GROUP BY m.campaign_id, c.channel, c.budget
ORDER BY overspend_amount DESC;

-- NOTE: an earlier draft used SUM(spend) OVER (ORDER BY campaign_id)
-- with no PARTITION BY — that computes a running total across ALL
-- campaigns in ID order, not each campaign's own total. Always pair a
-- window function's ORDER BY with an explicit PARTITION BY when you
-- want the calculation to reset per group; a plain GROUP BY was the
-- right tool here, not a window function at all.

-- Same view, rolled up by channel, to check whether overspending
-- clusters in a particular channel:
SELECT
    c.channel,
    COUNT(*) AS total_campaigns,
    SUM(CASE WHEN spend_summary.total_spend > c.budget THEN 1 ELSE 0 END) AS campaigns_overspent,
    ROUND(SUM(CASE WHEN spend_summary.total_spend > c.budget THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS pct_overspent,
    SUM(spend_summary.total_spend - c.budget) AS net_overspend
FROM source.campaigns c
JOIN (
    SELECT campaign_id, SUM(spend) AS total_spend
    FROM source.marketing_spend
    GROUP BY campaign_id
) spend_summary ON spend_summary.campaign_id = c.campaign_id
GROUP BY c.channel
ORDER BY pct_overspent DESC;

-- FINDING: 14 of 100 campaigns overspent their budget. SMS and Display
-- are tied for the highest overspend rate (19% of campaigns each) —
-- SMS is not uniquely worse on this metric alone, but combined with its
-- weak CTR/CPC performance (Q9), it's the stronger case for review.
-- Influencer has a 0% overspend rate, reinforcing it as the standout
-- channel for efficiency.


/*---------------------------------------------------------------------
  Q11. Revenue, profit, and margin by product category and brand
---------------------------------------------------------------------*/
-- Uses order_items.unit_price (actual transaction price), not
-- products.price (catalog/reference price) — price and unit_price
-- intentionally differ in this dataset to simulate promotions/price
-- drift over time. Revenue and profit must reflect what was actually
-- charged, not the catalog price.

WITH item_level AS (
    SELECT
        p.category,
        p.brand,
        (o.unit_price * o.quantity) - o.discount_amount AS revenue,
        (o.unit_price * o.quantity) - o.discount_amount - (p.cost * o.quantity) AS profit
    FROM source.products p
    JOIN source.order_items o ON p.product_id = o.product_id
)
-- by category
SELECT
    category,
    SUM(revenue) AS total_revenue,
    SUM(profit) AS total_profit,
    ROUND(SUM(profit) * 100.0 / SUM(revenue), 2) AS profit_margin_pct
FROM item_level
GROUP BY category
ORDER BY total_revenue DESC;

-- by brand (separate GROUP BY — combining category+brand in one query
-- would cross every category-brand pair instead of two clean breakdowns)
WITH item_level AS (
    SELECT
        p.brand,
        (o.unit_price * o.quantity) - o.discount_amount AS revenue,
        (o.unit_price * o.quantity) - o.discount_amount - (p.cost * o.quantity) AS profit
    FROM source.products p
    JOIN source.order_items o ON p.product_id = o.product_id
)
SELECT
    brand,
    SUM(revenue) AS total_revenue,
    SUM(profit) AS total_profit,
    ROUND(SUM(profit) * 100.0 / SUM(revenue), 2) AS profit_margin_pct
FROM item_level
GROUP BY brand
ORDER BY total_revenue DESC;

-- FINDING: Electronics dominates absolute revenue and profit (~68% of
-- total revenue) almost entirely due to a much higher average selling
-- price (Rs.39,056 vs. the next-highest category at Rs.8,915) rather
-- than higher sales volume — Books actually sells more units. However,
-- Electronics has the second-lowest profit MARGIN (32.51%) of any
-- category; Sports is the most efficient (36.84%). Best-selling,
-- highest-revenue, and highest-margin are three different questions —
-- category strategy should treat them separately.
--
-- At brand level, Electronics brands (Sony, boAt, OnePlus, Apple)
-- dominate revenue but mostly sit in the bottom half by margin; Samsung
-- is the exception. Apple combines high revenue with one of the lowest
-- margins in the dataset. NOTE: brand-level cost/price ratios were
-- randomly generated per brand in this synthetic dataset and should not
-- be read as real-world brand economics.


/*---------------------------------------------------------------------
  Q12. Return rate and refund value by reason and by category
---------------------------------------------------------------------*/

-- Part A: by return reason (needs only the returns table — reason and
-- refund_amount both live there directly, no join required)
SELECT
    return_reason,
    COUNT(*) AS total_returns,
    SUM(refund_amount) AS total_refund
FROM source.returns
GROUP BY return_reason
ORDER BY total_refund DESC;

-- FINDING: return reasons are evenly distributed (3,277-3,413 returns
-- each) — no single cause dominates, so no one operational fix would
-- meaningfully cut overall return volume on its own.

-- Part B: by category, WITH a true rate (returns / items sold), not
-- just a raw count. order_items is the anchor table so every sale is
-- counted, whether returned or not; returns is LEFT JOINed on BOTH
-- order_id and product_id so it only adds information, never filters
-- the base set of sales.
SELECT
    p.category,
    SUM(oi.quantity) AS total_sold,
    COUNT(DISTINCT r.return_id) AS total_returns,
    ROUND(COUNT(DISTINCT r.return_id) * 100.0 / SUM(oi.quantity), 2) AS return_rate_pct,
    SUM(r.refund_amount) AS total_refunds
FROM source.order_items oi
JOIN source.products p ON p.product_id = oi.product_id
LEFT JOIN source.returns r
    ON r.product_id = oi.product_id AND r.order_id = oi.order_id
GROUP BY p.category
ORDER BY total_refunds DESC;

-- NOTE: this query went through three broken versions before landing
-- here, all variations of the same root cause — joining returns and
-- order_items without matching BOTH order_id and product_id together.
-- Symptoms at each stage: (1) joining products->returns->order_items
-- on product_id alone caused one return to fan out across every order
-- that ever contained that product (return count off by ~1,400x);
-- (2) fixing the returns/order_items join but keeping order_items
-- joined only to matched returns turned an INNER JOIN into a filter,
-- shrinking total_sold and inflating the rate to a nonsensical ~72%
-- for every category. The working pattern: anchor on the full
-- order_items table, JOIN dimension tables normally, LEFT JOIN
-- transactional/event tables (like returns) on the FULL composite key
-- that actually identifies one event (order_id + product_id).
--
-- FINDING: return rates are consistent across every category
-- (6.57%-7.03%) — no category is disproportionately likely to be
-- returned. But refund VALUE is heavily concentrated in Electronics
-- (~74% of total refunds) purely because of its high price point.
-- Return-reduction efforts should prioritize Electronics not because
-- it's returned more often, but because each return there is far more
-- expensive.

/*=====================================================================
END OF LEVEL 2
Summary of findings -> see findings.md
=======================================================================*/
