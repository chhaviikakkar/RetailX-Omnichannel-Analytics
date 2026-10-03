# Findings — RetailX Omnichannel Analytics

Plain-language summary of the key insights across all four levels of
analysis (Data Quality, Core KPIs, Trends & Behavior, Advanced
Analysis). Every number below has been verified against actual query
output, not estimated. For the full data quality investigation (NULLs,
orphans, reconciliation checks), see `data_quality_log.md` — this file
focuses on business insights.

**Scope note**: this project does not aggressively focus on data
cleaning or transformation. Data quality issues are identified,
quantified, and documented rather than corrected upstream. CPA
(cost per acquisition) was scoped alongside ROAS but not completed —
see `04_advanced_analysis.sql` for details.

---

## Headline Finding: Attribution Model Choice Changes Everything

The single most important result in this project: **the "best
marketing channel" completely flips depending on which attribution
model you trust.**

| Channel | ROAS (First-touch) | ROAS (Last-touch) |
|---|---|---|
| Paid Search | **165.54** (rank 1) | 27.17 (rank 6) |
| Social Media | 154.95 (rank 2) | **107.30** (rank 1) |
| Affiliate | 89.59 (rank 3) | 25.65 (rank 7, last) |
| Display | 46.79 (rank 4) | 33.38 (rank 5) |
| SMS | 17.75 (rank 5) | 59.38 (rank 4) |
| Email | 14.08 (rank 6) | **100.33** (rank 2) |
| Influencer | 0.93 (rank 7, last) | 78.63 (rank 3) |

Paid Search drops from the clear #1 channel (first-touch) to #6
(last-touch). Influencer rises from dead-last (barely breaking even at
0.93) to a strong #3. This suggests Paid Search and Affiliate excel at
**introducing** new customers (winning the first touch), while Social
Media and Email are more effective at **closing** the sale (winning the
last touch). Influencer's apparent first-touch weakness is largely
explained by it running far fewer campaigns than other channels (7, vs.
21 for Display/SMS) — fewer campaigns means fewer chances to ever be
anyone's literal first contact, not necessarily lower quality.

**Both models are extremes** — only one touchpoint per order gets any
credit, and every touchpoint in between gets none. Budget decisions
should weigh a channel's *role* in the customer journey (awareness vs.
conversion), not a single ROAS figure from one model in isolation. 517
orders (₹1.40 Cr) have no attributable touchpoint under either model and
are excluded from these figures — a small (~0.5%) but documented gap.

## Channel Performance

- **Online drives more volume; In-Store has a marginally higher AOV.**
  Online generates ~68% of revenue (₹168.66 Cr) across 66,191 orders;
  In-Store generates ~32% (₹80.69 Cr) across 31,456 orders — 2.1x the
  order volume for Online. Excluding Cancelled orders shifted AOV by
  only 0.07% (Online) and 0.26% (In-Store).

- **Influencer marketing is the standout channel for efficiency**,
  independent of the attribution question above: best CTR (3.40%,
  tied-highest) and lowest CPC (₹9.99) of any channel, plus a 0%
  campaign overspend rate.

- **SMS underperforms on cost and engagement**: lowest CTR (2.40%),
  highest CPC (₹15.94), despite the second-highest spend allocation.
  Tied with Display for the highest campaign overspend rate (19% each).

- **14 of 100 campaigns (14%) exceeded their allocated budget**,
  concentrated in Display and SMS (19% each); Influencer had 0%
  overspend.

- **Only 51.1% of customers were ever touched by the specific channel
  they were credited with for acquisition.** For 48.9%, the
  `acquisition_channel` label doesn't match anything in their real
  touchpoint history — despite most customers being touched by 6-7 of
  the 7 available channels overall. This single static label is an
  unreliable substitute for real attribution modeling (see headline
  finding above).

## Category & Brand Profitability

- **Electronics dominates revenue (~74.7% of total category revenue)**
  almost entirely due to price, not volume — it ranks only 5th of 7
  categories in units sold, driven by an average selling price (₹39,056)
  roughly 4.4x the next-highest category.

- **Highest revenue ≠ highest margin.** Electronics has the
  second-lowest profit margin of any category (32.51%); Sports is the
  most efficient (36.84%), despite a fraction of Electronics' revenue.
  The margin spread across all categories is fairly tight (32.1%-36.8%).

- **At brand level, Electronics brands mostly sit in the bottom half by
  margin** — only Samsung (38.38%) cracks the top 5 most-efficient
  brands; Decathlon, Levis, and IKEA lead on margin despite lower
  absolute revenue. (Brand cost/price ratios were randomly assigned in
  this synthetic dataset — not representative of real brand economics.)

- **Revenue concentration at the product level is extreme**: the #1
  product in Electronics generates ~89x the revenue of the #1 product
  in Grocery. Some categories show heavy single-brand dependency in
  their top 3 (Books' top 3 are all HarperCollins).

## Returns

- **Return reasons are evenly distributed** (3,277-3,413 per reason) —
  no single cause dominates.

- **Return rate is consistent across categories (6.57%-7.03%), but
  refund value is not** — Electronics accounts for ~74% of total refund
  value despite an unremarkable return rate, purely due to its high
  price point. Return-reduction efforts should prioritize Electronics
  for cost impact, not return frequency.

- **Known limitation**: `refund_amount` is not reliably reconciled
  against item/order value for ~34.5% of returns at the item level
  (root cause: refunds calculated pre-discount, order/item values
  post-discount). Return rate and count are unaffected; refund value
  figures should be read with this caveat.

## Growth, Trends & a Shared Data Limitation

- **Month-over-month revenue growth (Q14) and cohort retention (Q22)
  both show a dramatic, suspicious climb in later periods that is NOT
  real business improvement.** Both are driven by the same
  data-generation artifact: each customer's order dates were randomly
  distributed between their signup date and the dataset's fixed end
  date (2024-12-30). Customers who signed up early have their orders
  spread thin across up to two years; customers who signed up late have
  almost no remaining window, so any order they place is mechanically
  compressed close to signup. This inflates both late-period growth
  rates and late-cohort short-term retention. Order volume growth
  (~200x over the dataset) substantially outpaces customer base growth
  (~25x), confirming the effect. **Any metric in this dataset measured
  relative to signup or order recency should be treated with this
  caveat for the final few months of the window.**

## Customer Behavior

- **Session → order conversion is ~84-85%, with no meaningful
  difference by device** (Desktop 84.4%, Mobile 84.5%, Tablet 85.0%).

- **Session → touchpoint is a saturated, non-filtering funnel stage**:
  100% of customers have at least one touchpoint on record (verified
  directly: 0 of 30,000 customers have zero), reflecting the dataset's
  high touchpoint volume (~17/customer) rather than a meaningful
  behavioral filter.

- **Average gap between a customer's consecutive orders: 54 days** —
  usable as a retention/win-back benchmark (customers past ~90 days
  since last order likely warrant outreach).

- **Channel diversity shows diminishing returns on customer value.**
  Conversion rate (~80-83%) and average customer value (~₹77K-84K) are
  essentially flat across customers touched by 4-7 channels (97%+ of
  the customer base). True low-channel customers are too rare (1-86
  customers) to draw reliable conclusions from. Reaching a customer
  through more channels beyond a baseline of ~4 does not appear to
  meaningfully increase their value in this dataset.

## Customer Segmentation (RFM)

- Customers were scored 1-5 on Recency, Frequency, and Monetary value
  (all three consistently excluding Cancelled orders) and combined into
  an overall segment: Champions, Loyal Customers, At Risk, or Lost.
  Customers whose entire order history is Cancelled are absent from
  this segmentation by design (verified: no silent drop beyond this
  group — 24,913 of 24,913 eligible customers accounted for).

---

## Recommendations

1. **Re-evaluate SMS budget.** Weakest CTR/CPC combination and tied for
   highest campaign overspend rate — the strongest single candidate for
   budget reduction or campaign redesign.
2. **Don't rely on a single attribution model for budget decisions.**
   Paid Search and Affiliate appear to drive awareness (first-touch);
   Social Media and Email appear to drive conversion (last-touch).
   Allocate budget by the role a channel plays, not one ROAS number.
3. **Prioritize Electronics for return-cost control**, not return-rate
   reduction — its return *rate* is average, but its return *value* is
   disproportionate due to price.
4. **Treat growth and retention trends from the final quarter of this
   dataset (Oct-Dec 2024) with caution** — they are substantially
   inflated by a data-generation artifact, not genuine acceleration.
5. **Use the 54-day average repeat-purchase gap as a churn-risk
   trigger** for retention campaigns.

## Limitations

- Refund value data is unreliable for ~34.5% of returns at the item
  level (see data_quality_log.md).
- Growth and retention metrics in the final months of the dataset are
  inflated by order-date generation mechanics, not real trends.
- Attribution modeling here uses only first-touch and last-touch
  (both extremes); no credit is given to touchpoints in the middle of
  a customer's journey.
- CPA by channel was not completed.
- This project intentionally did not pursue heavy data cleaning/ETL —
  issues are documented and worked around, not corrected at the source.
