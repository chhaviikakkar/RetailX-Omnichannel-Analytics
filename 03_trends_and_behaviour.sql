/*=====================================================================
RetailX — Omnichannel Marketing Analytics
Level 3: Trends & Behaviour 
=======================================================================
Purpose : Apply ranking, running totals, gap analysis, and multi-table
          funnel logic — building on the validated data and business
          rules established in Levels 1 and 2.

Key lesson carried through this whole file: PARTITION BY controls
whether a window function resets per group or runs continuously across
the whole result set. Getting this wrong (or leaving it out) was the
root cause of nearly every bug encountered while building these queries
— see the NOTE under each query for specifics.

Author  : [Your Name]
Dataset : RetailX synthetic omnichannel retail dataset
=======================================================================*/


/*---------------------------------------------------------------------
  Q13. Top 3 products by revenue within each category
---------------------------------------------------------------------*/
SELECT product_id, category, revenue, ranking
FROM (
    SELECT
        p.product_id,
        p.category,
        SUM(oi.unit_price * oi.quantity - oi.discount_amount) AS revenue,
        DENSE_RANK() OVER (PARTITION BY p.category ORDER BY
            SUM(oi.unit_price * oi.quantity - oi.discount_amount) DESC) AS ranking
    FROM source.products p
    JOIN source.order_items oi ON oi.product_id = p.product_id
    GROUP BY p.product_id, p.category
) ranked
WHERE ranking <= 3
ORDER BY category, ranking;

-- NOTE: grouped by product_id (the actual key), not product_name — a
-- text label could theoretically collide across different products,
-- even though it doesn't in this dataset. DENSE_RANK() was chosen over
-- ROW_NUMBER() as a deliberate choice: if two products in a category
-- were exactly tied for 3rd place, DENSE_RANK() would return both
-- (4 rows for that category) rather than arbitrarily picking one.
-- Verified no ties exist in this dataset, so both would give an
-- identical result here — but DENSE_RANK() is the more defensible
-- default when tie-handling matters.
--
-- A window function's result (ranking) can't be filtered directly in
-- a WHERE clause in the same query — hence wrapping it in a subquery
-- and filtering in the outer SELECT.
--
-- FINDING: revenue gap between category leaders is enormous — Sony
-- Mobile Phones (Electronics, #1) generates ~68x the revenue of Tata
-- Snacks (Grocery, #1). Some categories show heavy brand concentration
-- at the top (Books' top 3 are all HarperCollins; Sports' top 3 include
-- 2 Nike products) — a supply issue with one brand could meaningfully
-- dent that category's revenue.


/*---------------------------------------------------------------------
  Q14. Month-over-month revenue growth %
---------------------------------------------------------------------*/
SELECT
    years,
    months,
    current_revenue,
    prev_month_revenue,
    CAST(current_revenue - prev_month_revenue AS FLOAT) * 100 / prev_month_revenue AS mom_growth_pct
FROM (
    SELECT
        years,
        months,
        current_revenue,
        LAG(current_revenue) OVER (ORDER BY years, months) AS prev_month_revenue
    FROM (
        SELECT
            YEAR(order_date) AS years,
            MONTH(order_date) AS months,
            SUM(net_amount) AS current_revenue
        FROM source.orders
        WHERE order_status <> 'Cancelled'
        GROUP BY YEAR(order_date), MONTH(order_date)
    ) monthly
) with_lag
ORDER BY years, months;

-- NOTE: an earlier draft used LAG() with PARTITION BY years — this
-- reset the lookback at every year boundary, so January 2024 incorrectly
-- showed NULL/no-previous-month instead of pulling December 2023's
-- revenue. Removed the PARTITION BY entirely, since month-over-month
-- growth should read as one continuous 24-month timeline, not two
-- separate 12-month ones.
--
-- FINDING: growth is extremely volatile in the first few months (>50%,
-- driven by a tiny early-2023 base), settles to a steadier ~15-20% band
-- through most of the dataset, then spikes again in Oct-Dec 2024 (29%,
-- 43%). This end-of-window spike is a data-generation artifact: late
-- signups have their single order compressed into a short remaining
-- window before the dataset ends, inflating the final months. Growth
-- in the final quarter should not be read as accelerating momentum.


/*---------------------------------------------------------------------
  Q15. Running total of revenue by month, within each sales channel
---------------------------------------------------------------------*/
SELECT
    sales_channel,
    year,
    month,
    monthly_rev,
    SUM(monthly_rev) OVER (
        PARTITION BY sales_channel
        ORDER BY year, month
    ) AS running_total
FROM (
    SELECT
        sales_channel,
        YEAR(order_date) AS year,
        MONTH(order_date) AS month,
        SUM(net_amount) AS monthly_rev
    FROM source.orders
    WHERE order_status <> 'Cancelled'
    GROUP BY sales_channel, YEAR(order_date), MONTH(order_date)
) t
ORDER BY sales_channel, year, month;

-- NOTE: PARTITION BY sales_channel is required so the running total
-- resets cleanly for each channel instead of accumulating across both
-- combined (the same mistake as Q10's overspend bug, avoided here by
-- partitioning correctly from the start). No PARTITION BY on year,
-- unlike Q14's fix — a running total should keep accumulating straight
-- through the 2023->2024 boundary, not reset at year-end.
--
-- Verified: running total resets to a small number at the first month
-- of each channel and carries continuously across the year boundary
-- within a channel.


/*---------------------------------------------------------------------
  Q16. Funnel: sessions -> touchpoints -> orders, by device
---------------------------------------------------------------------*/
-- Device is established ONCE, from sessions.device, and used as the
-- anchor for all three stages. marketing_touchpoints.device and orders
-- (which has no device column) are intentionally not used for grouping
-- -- they'd represent a different, unrelated device dimension and mixing
-- them in was an early mistake corrected here.
SELECT
    s.device,
    COUNT(DISTINCT s.customer_id) AS stage1_had_session,
    COUNT(DISTINCT tp.customer_id) AS stage2_had_touchpoint,
    COUNT(DISTINCT o.customer_id) AS stage3_placed_order
FROM source.sessions s
LEFT JOIN source.marketing_touchpoints tp ON tp.customer_id = s.customer_id
LEFT JOIN source.orders o ON o.customer_id = s.customer_id
GROUP BY s.device;

-- Verification: confirmed 0 of 30,000 customers have zero touchpoints
-- (SELECT COUNT(*) FROM customers c WHERE NOT EXISTS (SELECT 1 FROM
-- marketing_touchpoints tp WHERE tp.customer_id = c.customer_id) = 0).
-- At ~17 touchpoints per customer on average (520,000 touchpoints /
-- 30,000 customers), touchpoint coverage is effectively total, which is
-- why stage1 and stage2 are identical for every device -- this is a
-- verified property of the data, not a bug.
--
-- FINDING: session -> touchpoint is a saturated, non-filtering stage
-- (100% pass rate). The only real attrition is session -> order:
-- ~84-85% conversion, consistent across Desktop (84.4%), Mobile
-- (84.5%), and Tablet (85.0%) -- device does not meaningfully predict
-- purchase conversion in this dataset.


/*---------------------------------------------------------------------
  Q17. Days between consecutive orders per customer
---------------------------------------------------------------------*/
SELECT AVG(difference_in_days) AS avg_repeat_purchase_gap_days
FROM (
    SELECT
        customer_id,
        order_date,
        last_order,
        DATEDIFF(DAY, last_order, order_date) AS difference_in_days
    FROM (
        SELECT
            customer_id,
            order_date,
            LAG(order_date) OVER (PARTITION BY customer_id ORDER BY order_date) AS last_order
        FROM source.orders
    ) t
) gaps
WHERE difference_in_days IS NOT NULL;

-- NOTE: PARTITION BY customer_id is required here (unlike Q14) because
-- each customer has their own independent order timeline -- comparing
-- one customer's order to a DIFFERENT customer's previous order would
-- be meaningless. AVG() ignores NULLs automatically (same as COUNT()),
-- so the WHERE filter is technically redundant, but kept for clarity:
-- customers with only one order correctly produce NULL (nothing to
-- compare against) and are excluded from the average rather than
-- treated as a zero-day gap.
--
-- FINDING: average gap between a customer's consecutive orders is
-- ~54 days. Useful as a churn-risk benchmark -- customers approaching
-- or exceeding roughly 90 days since their last order likely warrant a
-- retention/win-back campaign.

/*=====================================================================
END OF LEVEL 3
Summary of findings -> see findings.md
=======================================================================*/
