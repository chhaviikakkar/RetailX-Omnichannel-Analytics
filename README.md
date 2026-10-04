# RetailX-Omnichannel-Analytics

A SQL-driven analysis of a simulated omnichannel retail business,
built to identify which marketing channels, product categories, and
customer segments actually drive revenue and profit — backed by a
documented data quality audit and real analytical trade-off decisions,
not just a list of charts.

**Scope**: This project does not aggressively focus on data cleaning
or transformation (no ETL layers, no bronze/silver/gold architecture).
Data quality issues are identified, quantified, and documented rather
than corrected upstream. The aim is to answer business questions,
analyze the data as-is, and surface actionable insights and
recommendations — an EDA-first project, not a data engineering one.

---

## The Business Problem

RetailX is a mid-size omnichannel retailer (online + physical stores)
that wants to understand how its marketing spend across channels
(Email, Social Media, Paid Search, Display, Affiliate, SMS, Influencer)
translates into actual sales, and where customers are being acquired,
retained, or lost. This project explores two years of customer, sales,
and marketing data to answer that, using SQL Server for analysis.

## Dataset

A synthetic, relationally-consistent dataset generated to simulate a
real omnichannel retailer's data warehouse:

| Table | Rows | Table | Rows |
|---|---|---|---|
| customers | 30,000 | marketing_touchpoints | 520,000 |
| orders | 105,000 | sessions | 210,000 |
| order_items | 213,931 | marketing_spend | 9,949 |
| campaigns | 100 | products | 150 |
| returns | 19,971 | stores | 40 |

Two-year window: 2023-01-01 to 2024-12-30. All IDs use one consistent
format per entity across every table (`CAMP001`, `CUS00001`, `PROD001`,
etc.).

## Tools

- **SQL Server (T-SQL)** — all analysis
- **Power BI** — dashboard *(in progress)*

## Repository Structure

```
retailx-omnichannel-analytics/
├── README.md                    <- you are here
├── findings.md                  <- consolidated business insights, all 4 levels
├── data_quality_log.md          <- full data quality audit write-up
└── sql/
    ├── 00_db_setup.sql           <- database + schema + table creation
    ├── 01_data_profiling.sql     <- Level 1: data quality checks
    ├── 02_core_kpi.sql          <- Level 2: revenue, CTR/CPC, overspend, margin, returns
    ├── 03_trends_and_behaviour.sql   <- Level 3: rankings, growth %, running totals, funnel
    └── 04_advanced_analytics.sql  <- Level 4: RFM, cohorts, attribution, ROAS
```

## Approach

The project follows four levels, each building on the last:

1. **Data Quality Profiling** — before trusting a single metric, every
   table was checked for row counts, date ranges, referential
   integrity, NULL patterns, categorical consistency, and logical
   impossibilities (e.g., can a refund exceed the order it belongs
   to?). 8+ real findings came out of this stage — see
   `data_quality_log.md` for the full write-up, including a bug that
   affected ~34.5% of all returns and was traced to its root cause.
2. **Core KPIs** — revenue, AOV, CTR, CPC, campaign budget discipline,
   category/brand profitability and margin, return rate and refund
   value — each with an explicit, documented business rule (e.g., how
   Cancelled and Returned orders are treated in revenue).
3. **Trends & Behavior Analysis** — product rankings within category,
   month-over-month growth, running revenue totals, a 3-stage
   marketing funnel, and repeat-purchase gap analysis, using window
   functions (`RANK`, `LAG`, `SUM() OVER()`).
4. **Advanced Analysis** — RFM customer segmentation, channel-diversity
   value analysis, cohort retention, acquisition-label accuracy, and
   first-touch/last-touch marketing attribution with ROAS by channel —
   the most technically demanding section, tying together every
   pattern from the levels before it.

## Key Findings

Full write-up with supporting numbers in **`findings.md`**. Headlines:

- **The "best marketing channel" completely flips** depending on
  whether you credit first-touch or last-touch attribution — Paid
  Search leads one model, Social Media leads the other. Neither model
  alone is sufficient for a budget decision.
- **Electronics drives ~75% of category revenue** almost entirely on
  price, not volume — and has one of the lowest profit margins of any
  category. Highest revenue and highest margin are not the same
  category.
- **Only 51% of customers** were ever actually touched by the specific
  channel they're credited with for acquisition — a single static
  label is an unreliable substitute for real attribution.
- **SMS is the weakest channel** on both engagement (lowest CTR/highest
  CPC) and budget discipline (tied-highest overspend rate).
- Several growth and retention trends in the dataset's final months
  are data-generation artifacts, not real business signals — explained
  and flagged rather than misreported.

## Data Quality: What Was Found and How It Was Handled

This project treats data quality as part of the analysis, not a
prerequisite to skip past. Full detail in `data_quality_log.md`;
highlights:

- Verified referential integrity across 5+ key relationships (zero
  orphans), confirmed via both count-comparison and `NOT EXISTS`
  patterns.
- Traced a refund calculation bug affecting ~34.5% of returns at the
  item level to its root cause (pre-discount vs. post-discount value
  mismatch) rather than just flagging the symptom.
- Identified and explained a right-censoring issue affecting returns
  near the dataset's end date.
- Made and documented explicit judgment calls (e.g., 47 customers with
  pre-window acquisition dates: flagged and retained rather than
  deleted, with reasoning for the decision).

## Notable Technical Challenges

A few bugs caught and fixed during this project, kept visible in the
SQL comments rather than silently corrected, because the debugging
process is itself worth showing:

- **Join fan-out**: multiple queries initially joined transactional
  tables (`order_items`, `returns`, `marketing_touchpoints`) on a
  partial key (e.g., `order_id` alone instead of `order_id` +
  `product_id`), which silently multiplied rows and inflated
  aggregates by orders of magnitude before being caught via sanity
  checks against known totals.
- **Window function partitioning**: an early budget-overspend query
  used `SUM() OVER (ORDER BY campaign_id)` with no `PARTITION BY`,
  producing a running total across *all* campaigns instead of each
  campaign's own total — caught because the resulting numbers were
  implausible at a glance.
- **`LEFT JOIN` + `WHERE` on the joined table**: a recurring trap where
  filtering on a right-hand-side column after a `LEFT JOIN` silently
  behaves like an `INNER JOIN`, dropping exactly the rows the `LEFT
  JOIN` was meant to preserve. Hit in the funnel analysis, the
  channel-value analysis, and the attribution model — resolved by
  moving the condition into the `JOIN ... ON` clause instead.

## Recommendations

See `findings.md` for the full list with supporting detail. Top three:

1. Re-evaluate SMS budget allocation — weakest performer on engagement
   and budget discipline.
2. Don't rely on a single attribution model for marketing budget
   decisions — weigh a channel's role (awareness vs. conversion).
3. Prioritize Electronics for return-cost control, not return-rate
   reduction.

## Limitations

- CPA (cost per acquisition) by channel was scoped but not completed.
- Attribution modeling uses only first-touch and last-touch; no credit
  is given to touchpoints in the middle of a customer's journey.
- Growth and retention metrics in the final months of the dataset are
  inflated by order-date generation mechanics — documented in detail
  in `findings.md`.
- This project intentionally did not pursue heavy data cleaning/ETL.

## How to Reproduce

1. Extract the CSVs from the 'data' folder to a local path of your choice.
2. Open 00_db_setup.sql, update the BULK INSERT file paths to match where you extracted the CSVs, and run the whole script — it creates the database, schema, all 10 tables, and loads the data in one pass.
3. Run 01_data_profiling.sql through 04_advanced_analytics.sql in order — each is commented with the business question, the query, and the finding it produced.

---

*"This was built as a portfolio project to demonstrate SQL
analysis, data quality auditing, and business-focused EDA for a data
analyst role transition." ~ Author: Chhavi Kakkar*
