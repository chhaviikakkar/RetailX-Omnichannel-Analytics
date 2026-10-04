/*=====================================================================
RetailX — Omnichannel Marketing Analytics
Level 4: Advanced Analysis
=======================================================================
Purpose : Customer segmentation (RFM), channel diversity value, cohort
          retention, acquisition-label accuracy, and marketing
          attribution modeling (ROAS) — the most technically demanding
          section of the project, building on every pattern established
          in Levels 1-3.
=======================================================================*/


/*---------------------------------------------------------------------
  Q17. RFM Segmentation
---------------------------------------------------------------------*/
-- All three dimensions consistently exclude Cancelled orders, same
-- revenue-recognition rule established in Q7. Reference date for
-- Recency is 2024-12-30, the last date present in source.orders.

WITH recency AS (
    SELECT *,
        DATEDIFF(DAY, last_cust_order, last_order) AS gap_in_recent_order
    FROM (
        SELECT DISTINCT
            customer_id,
            MAX(order_date) OVER (PARTITION BY customer_id) AS last_cust_order,
            MAX(order_date) OVER () AS last_order
        FROM source.orders
        WHERE order_status <> 'Cancelled'
    ) t
),

frequency AS (
    SELECT 
        customer_id,
        COUNT(*) AS number_of_orders
    FROM source.orders
    WHERE order_status <> 'Cancelled'
    GROUP BY customer_id
),

monetary AS (
    SELECT 
        customer_id,
        SUM(net_amount) AS total_value
    FROM source.orders
    WHERE order_status <> 'Cancelled'
    GROUP BY customer_id
),

rfm_base AS (
    SELECT 
        r.customer_id,
        r.gap_in_recent_order,
        f.number_of_orders,
        m.total_value
    FROM recency r
    JOIN frequency f ON r.customer_id = f.customer_id
    JOIN monetary m ON m.customer_id = r.customer_id
),

rfm_scored AS (
    SELECT 
        customer_id,
        gap_in_recent_order,
        number_of_orders,
        total_value,
        -- Recency: SMALL gap = recent = good, so sort DESC (large gaps
        -- first) to push recent customers into the highest bucket (5).
        NTILE(5) OVER (ORDER BY gap_in_recent_order DESC) AS r_score,
        -- Frequency/Monetary: LARGE value = good, sort ASC (small
        -- values first) to push high performers into bucket 5.
        NTILE(5) OVER (ORDER BY number_of_orders ASC) AS f_score,
        NTILE(5) OVER (ORDER BY total_value ASC) AS m_score
    FROM rfm_base
)

SELECT *,
    r_score + f_score + m_score AS rfm_total,
    CASE 
        WHEN r_score + f_score + m_score >= 12 THEN 'Champions'
        WHEN r_score + f_score + m_score >= 9 THEN 'Loyal Customers'
        WHEN r_score + f_score + m_score >= 6 THEN 'At Risk'
        ELSE 'Lost'
    END AS customer_segment
FROM rfm_scored
ORDER BY customer_id;

/*NOTE: customers whose ENTIRE order history is Cancelled are absent
from this table entirely (all three CTEs use the same WHERE filter,
so they never qualify for any of the three dimensions) -- verified
deliberate, not a silent drop: row count matches
COUNT(DISTINCT customer_id) FROM orders WHERE order_status <> 'Cancelled'
exactly (24,913).

An earlier draft had the NTILE() sort directions backwards (ASC for
Recency, DESC for Frequency/Monetary) which inverted the scoring --
caught by checking a known customer's gap against their resulting
r_score and finding them contradictory.*/


/*---------------------------------------------------------------------
  18. Multi-channel vs. single-channel customer value
---------------------------------------------------------------------*/
-- Originally framed as "1 channel vs 2+", but only 1 of 30,000
-- customers has touchpoints in a single channel (expected, given
-- ~17 touchpoints/customer on average -- see Q16). Reframed as a
-- trend across the full 1-7 channel_count range instead of a binary
-- split, since a binary split would be comparing n=1 against n=29,999.

WITH channels AS (
    SELECT
        customer_id,
        COUNT(DISTINCT channel) AS channel_count
    FROM source.marketing_touchpoints
    GROUP BY customer_id
),

order_value AS (
    SELECT
        customer_id,
        COUNT(*) AS order_count,
        SUM(net_amount) AS total_value
    FROM source.orders
    WHERE order_status <> 'Cancelled'
    GROUP BY customer_id
),

cte_final AS (
    SELECT 
        c.customer_id,
        c.channel_count,
        o.order_count,
        o.total_value 
    FROM channels c
    LEFT JOIN order_value o          -- LEFT JOIN: keep touched customers
        ON o.customer_id = c.customer_id   -- even if they never ordered
)

SELECT 
    channel_count,
    COUNT(*) AS total_customers,
    SUM(CASE WHEN total_value IS NOT NULL THEN 1 ELSE 0 END) AS customers_who_ordered,
    ROUND(SUM(CASE WHEN total_value IS NOT NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS conversion_rate_pct,
    ROUND(AVG(COALESCE(total_value, 0)), 2) AS avg_customer_value
FROM cte_final
GROUP BY channel_count
ORDER BY channel_count;

/*NOTE: an earlier draft used INNER JOIN, which silently dropped every
touched-but-never-purchased customer -- exactly the group needed to
calculate a real conversion rate. LEFT JOIN + COALESCE(..., 0) was
required to keep them visible as zero-value rows instead of absent.

FINDING: conversion rate (~80-83%) and average customer value
(~Rs.77K-84K) are essentially FLAT across channel_count 4-7, which
covers 97%+ of the customer base. channel_count 1-3 rows are built on
tiny samples (1-86 customers) and too noisy to trust. Contrary to the
assumption that more channel exposure drives more value, this dataset
shows negligible returns from reaching a customer through additional
channels beyond a baseline of ~4.*/


/*---------------------------------------------------------------------
  19. Cohort retention by acquisition month
---------------------------------------------------------------------*/
-- Retention % is shown ONLY for cohorts that have had enough time
-- (relative to the dataset's 2024-12-30 end date) to be fairly judged
-- at that month mark -- otherwise a recent cohort would show a
-- misleadingly low/blank percentage simply because the window to
-- measure them hasn't occurred yet (right-censoring, same class of
-- issue as the returns right-censoring found in Level 1).

WITH cohort_base AS (
    SELECT 
        YEAR(signup_date) AS cohort_year,
        MONTH(signup_date) AS cohort_month,
        COUNT(*) AS cohort_size,
        MAX(signup_date) AS latest_signup_in_cohort  -- conservative anchor:
    FROM source.customers                             -- if even the LAST
    GROUP BY YEAR(signup_date), MONTH(signup_date)     -- joiner has enough
),                                                      -- runway, everyone
                                                         -- earlier does too
eligibility AS (
    SELECT *,
        CASE WHEN DATEADD(MONTH, 1, latest_signup_in_cohort) <= '2024-12-30' THEN 1 ELSE 0 END AS month_1_eligible,
        CASE WHEN DATEADD(MONTH, 2, latest_signup_in_cohort) <= '2024-12-30' THEN 1 ELSE 0 END AS month_2_eligible,
        CASE WHEN DATEADD(MONTH, 3, latest_signup_in_cohort) <= '2024-12-30' THEN 1 ELSE 0 END AS month_3_eligible
    FROM cohort_base
),

order_gaps AS (
    SELECT 
        c.customer_id,
        YEAR(c.signup_date) AS cohort_year,
        MONTH(c.signup_date) AS cohort_month,
        DATEDIFF(MONTH, c.signup_date, o.order_date) AS gap_in_months
    FROM source.customers c
    JOIN source.orders o ON c.customer_id = o.customer_id
),

retained AS (
    SELECT 
        cohort_year,
        cohort_month,
        COUNT(DISTINCT CASE WHEN gap_in_months = 1 THEN customer_id END) AS retained_month_1,
        COUNT(DISTINCT CASE WHEN gap_in_months = 2 THEN customer_id END) AS retained_month_2,
        COUNT(DISTINCT CASE WHEN gap_in_months = 3 THEN customer_id END) AS retained_month_3
    FROM order_gaps
    GROUP BY cohort_year, cohort_month
)

SELECT 
    e.cohort_year,
    e.cohort_month,
    e.cohort_size,
    CASE WHEN e.month_1_eligible = 1 
         THEN ROUND(r.retained_month_1 * 100.0 / e.cohort_size, 1) END AS retention_month_1_pct,
    CASE WHEN e.month_2_eligible = 1 
         THEN ROUND(r.retained_month_2 * 100.0 / e.cohort_size, 1) END AS retention_month_2_pct,
    CASE WHEN e.month_3_eligible = 1 
         THEN ROUND(r.retained_month_3 * 100.0 / e.cohort_size, 1) END AS retention_month_3_pct
FROM eligibility e
JOIN retained r ON e.cohort_year = r.cohort_year AND e.cohort_month = r.cohort_month
ORDER BY e.cohort_year, e.cohort_month;

/*FINDING (important limitation, shared with Q14): retention appears to
climb sharply and almost monotonically from ~12-17% (early 2023
cohorts) to ~50-76% (late 2024 cohorts). This is NOT real improvement
in customer loyalty -- it is the same order-date generation artifact
identified in Q14. Early cohorts have their orders spread across up
to two years, so any single month captures only a thin slice of
their eventual order probability; late cohorts have almost no
remaining window, so any order they place is mechanically compressed
close to signup, inflating their short-term retention. Cohort
retention trends in this dataset should not be read as real
behavioral change over time.*/

/*---------------------------------------------------------------------
  20. Acquisition channel vs. actual touchpoint channel history
---------------------------------------------------------------------*/
WITH channel_match AS (
    SELECT 
        c.customer_id,
        MAX(CASE WHEN m.channel = c.acquisition_channel THEN 1 ELSE 0 END) AS matched
    FROM source.customers c
    JOIN source.marketing_touchpoints m ON c.customer_id = m.customer_id
    GROUP BY c.customer_id
)
SELECT 
    matched,
    COUNT(*) AS customer_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage
FROM channel_match
GROUP BY matched;

/*FINDING: only 51.1% of customers were ever actually touched, at any
point, by the specific channel they were credited with for
acquisition -- essentially a coin flip, far below what the near-total
touchpoint saturation found in Q16 would suggest. For 48.9% of
customers, acquisition_channel does not appear anywhere in their real
touchpoint history. With 7 possible channels and most customers
touched by 6-7 of them (Q19), there's still a meaningful chance the
ONE specific credited channel is among the 1-2 a customer was NOT
touched by. This calls into question how much to trust
acquisition_channel as a standalone label, and directly motivates the
attribution modeling below as a more rigorous alternative.*/


/*---------------------------------------------------------------------
  21. First-touch vs. last-touch attribution
---------------------------------------------------------------------*/
-- The hardest query in the project. For every order, finds the
-- customer's earliest and latest marketing touchpoint that occurred
-- STRICTLY BEFORE that order's date. Manually verified end-to-end for
-- one order (ORD000001) against raw marketing_touchpoints data before
-- being trusted.

WITH qualifying_touchpoints AS (
    -- LEFT JOIN with the date filter INSIDE the ON clause (not a WHERE
    -- clause afterward) -- this is the critical, easy-to-get-wrong
    -- detail. Putting `t.timestamp < o.order_date` in ON preserves every
    -- order even when zero touchpoints qualify (NULL channel/timestamp,
    -- row survives). Putting the same condition in a WHERE clause after
    -- the join would silently drop those orders entirely, because
    -- `NULL < order_date` evaluates to unknown/false -- turning a
    -- LEFT JOIN into a de facto INNER JOIN. Same class of mistake as
    -- the Q16/Q19 LEFT JOIN + WHERE trap, now applied to a date filter.
    SELECT 
        o.order_id,
        o.customer_id,
        o.order_date,
        t.channel,
        t.timestamp
    FROM source.orders o
    LEFT JOIN source.marketing_touchpoints t
        ON t.customer_id = o.customer_id
        AND t.timestamp < o.order_date
),

ranked AS (
    -- PARTITION BY order_id, not customer_id -- ranking must reset for
    -- EVERY individual order, since the same customer's touchpoint
    -- pool differs depending on which order's date you're filtering
    -- against. An earlier draft partitioned by customer_id only, which
    -- collapsed all of a customer's orders into one shared first/last
    -- touch and fanned out badly when joined back to orders.
    SELECT *,
        ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY timestamp ASC) AS rn_first,
        ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY timestamp DESC) AS rn_last
    FROM qualifying_touchpoints
)

SELECT
    order_id,
    customer_id,
    order_date,
    MAX(CASE WHEN rn_first = 1 THEN channel END) AS first_touch_channel,
    MAX(CASE WHEN rn_last = 1 THEN channel END) AS last_touch_channel
FROM ranked
GROUP BY order_id, customer_id, order_date
ORDER BY order_id;


/*---------------------------------------------------------------------
  22. ROAS by channel (first-touch and last-touch models)
---------------------------------------------------------------------*/
-- Built directly on the Q20 attribution logic, with net_amount carried
-- through and two new CTEs for revenue and spend per channel.
-- CPA (cost per acquisition) was scoped alongside ROAS but NOT built --
-- see header note.

-- ===== FIRST-TOUCH MODEL =====
WITH qualifying_touchpoints AS (
    SELECT 
        o.order_id, o.customer_id, o.order_date, o.net_amount,
        t.channel, t.timestamp
    FROM source.orders o
    LEFT JOIN source.marketing_touchpoints t
        ON t.customer_id = o.customer_id AND t.timestamp < o.order_date
    WHERE o.order_status <> 'Cancelled'
),
ranked AS (
    SELECT *,
        ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY timestamp ASC) AS rn_first,
        ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY timestamp DESC) AS rn_last
    FROM qualifying_touchpoints
),
attribution AS (
    SELECT
        order_id, customer_id, order_date, net_amount,
        MAX(CASE WHEN rn_first = 1 THEN channel END) AS first_touch_channel,
        MAX(CASE WHEN rn_last = 1 THEN channel END) AS last_touch_channel
    FROM ranked
    GROUP BY order_id, customer_id, order_date, net_amount
),
revenue_by_channel AS (
    SELECT first_touch_channel AS channel, SUM(net_amount) AS attributed_revenue
    FROM attribution
    WHERE first_touch_channel IS NOT NULL   -- excludes 517 orders (Rs.1.4Cr)
    GROUP BY first_touch_channel             -- with zero qualifying touchpoints
),
spend_by_channel AS (
    SELECT c.channel, SUM(m.spend) AS total_spend
    FROM source.marketing_spend m
    JOIN source.campaigns c ON c.campaign_id = m.campaign_id
    GROUP BY c.channel
)
SELECT
    s.channel, s.total_spend, r.attributed_revenue,
    ROUND(r.attributed_revenue / CAST(s.total_spend AS FLOAT), 2) AS roas
FROM spend_by_channel s
JOIN revenue_by_channel r ON r.channel = s.channel
ORDER BY roas DESC;

-- Verification: 517 orders (Rs. 1,39,55,870.34) have no qualifying
-- touchpoint before them and are correctly excluded from attributed
-- revenue -- filtered explicitly (WHERE ... IS NOT NULL) rather than
-- silently dropped, so the gap is visible and documented, not hidden.

-- ===== LAST-TOUCH MODEL =====
-- Identical query; only revenue_by_channel's source column changes
-- from first_touch_channel to last_touch_channel throughout.
WITH qualifying_touchpoints AS (
    SELECT 
        o.order_id, o.customer_id, o.order_date, o.net_amount,
        t.channel, t.timestamp
    FROM source.orders o
    LEFT JOIN source.marketing_touchpoints t
        ON t.customer_id = o.customer_id AND t.timestamp < o.order_date
    WHERE o.order_status <> 'Cancelled'
),
ranked AS (
    SELECT *,
        ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY timestamp ASC) AS rn_first,
        ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY timestamp DESC) AS rn_last
    FROM qualifying_touchpoints
),
attribution AS (
    SELECT
        order_id, customer_id, order_date, net_amount,
        MAX(CASE WHEN rn_first = 1 THEN channel END) AS first_touch_channel,
        MAX(CASE WHEN rn_last = 1 THEN channel END) AS last_touch_channel
    FROM ranked
    GROUP BY order_id, customer_id, order_date, net_amount
),
revenue_by_channel AS (
    SELECT last_touch_channel AS channel, SUM(net_amount) AS attributed_revenue
    FROM attribution
    WHERE last_touch_channel IS NOT NULL
    GROUP BY last_touch_channel
),
spend_by_channel AS (
    SELECT c.channel, SUM(m.spend) AS total_spend
    FROM source.marketing_spend m
    JOIN source.campaigns c ON c.campaign_id = m.campaign_id
    GROUP BY c.channel
)
SELECT
    s.channel, s.total_spend, r.attributed_revenue,
    ROUND(r.attributed_revenue / CAST(s.total_spend AS FLOAT), 2) AS roas
FROM spend_by_channel s
JOIN revenue_by_channel r ON r.channel = s.channel
ORDER BY roas DESC;

/*FINDING (headline result of the whole project): the "best channel"
completely flips depending on attribution model.
   First-touch leaders: Paid Search (165.54), Social Media (154.95)
   First-touch laggard:  Influencer (0.93 -- barely breaks even)
   Last-touch leaders:   Social Media (107.30), Email (100.33)
   Last-touch laggard:   Affiliate (25.65)
Paid Search drops from rank 1 (first-touch) to rank 6 (last-touch).
Influencer rises from rank 7 to rank 3. This suggests Paid Search and
Affiliate excel at INTRODUCING new customers (winning the first
touch), while Social Media and Email are more effective at CLOSING
the sale (winning the last touch) -- Influencer's apparent weakness
under first-touch is largely explained by it running far fewer
campaigns (7, vs. 21 for Display/SMS -- see Q10), giving it
statistically fewer chances to ever be anyone's literal first contact,
not necessarily lower quality. Neither model alone is sufficient:
both are extremes that credit only one touchpoint and give zero
credit to every touchpoint in between, likely understating channels
that play a supporting, mid-journey role. Budget decisions should
weigh a channel's ROLE in the journey (awareness vs. conversion), not
a single ROAS figure from one model in isolation.*/

/*=====================================================================
END OF LEVEL 4 — END OF PROJECT ANALYSIS (20 of 23 planned questions
complete; Q8, Q14-adjacent growth discussion, and CPA noted as gaps/
folded elsewhere above)
Summary of findings -> see findings.md
=======================================================================*/
