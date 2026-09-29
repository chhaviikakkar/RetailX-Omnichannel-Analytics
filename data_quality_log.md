# Data Quality Log — RetailX Omnichannel Analytics

Findings from Level 1 profiling, before any KPI or dashboard work began.
Each finding states what was found, how it was verified, and the decision
made — since "found an anomaly and did nothing" is not the same as "found
an anomaly, quantified it, and made a documented call."

---

### 1. 47 customers acquired before the dataset's official window
`acquisition_date` for 47 of 30,000 customers (0.16%) falls before
2023-01-01, the dataset's stated start date.

**Decision:** Retained, not deleted. Deleting would cascade into their
orders, sessions, and touchpoints for a negligible-impact edge case.
Filter with `WHERE acquisition_date >= '2023-01-01'` at the query level
if a specific analysis needs a clean acquisition cohort.

### 2. Expected NULL patterns (verified at 100%, not assumed)
| Column | NULL when... | Verified split |
|---|---|---|
| `customers.acquisition_campaign_id` | channel is Organic/Direct | 100% NULL vs 100% populated by channel |
| `orders.store_id` | sales_channel is Online | 71,115/71,115 NULL (Online) vs 0/33,885 NULL (In-Store) |
| `sessions.campaign_id` | source is Direct/Organic Search | 100% NULL vs 100% populated by source |

No unexpected NULLs found elsewhere in `customers`, `orders`, or
`sessions` after a full column-by-column sweep.

### 3. Referential integrity — zero orphans
Verified via count comparison (`INNER JOIN` vs total row count) across:
`orders→customers`, `order_items→orders`, `order_items→products`,
`returns→orders`, `marketing_touchpoints→campaigns`. All five relationships
matched exactly.

### 4. Categorical values — no casing/whitespace issues
Checked `channel`, `sales_channel`, `order_status`, `payment_method`,
`device` using `LEN(x) <> LEN(TRIM(x))`. Zero rows returned across all
five — no hidden whitespace or casing splits.

### 5. Refund amount exceeds item/order value (material finding)
- **34.5%** of returns (6,889 / 19,971) have a `refund_amount` exceeding
  the specific returned item's own line value
  (`unit_price × quantity − discount_amount`).
- **7.2%** of returns (1,428 / 19,971) even exceed the *entire order's*
  `net_amount`.

**Root cause:** refund amounts were calculated pre-discount, while
item/order values are post-discount.

**Decision:** Retained and flagged rather than corrected, since the
underlying data-generation logic is now understood. Any refund-based KPI
(total refunded value, refund rate by category, etc.) should note this
limitation rather than treat `refund_amount` as fully reconciled.

### 6. Reconciliation gap: net_amount 
1,611 of 105,000 orders (1.53%) have a `net_amount` that doesn't equal
`gross_amount − discount_amount + shipping_amount`. `gross_amount` and
`discount_amount` themselves are unaffected. Flag when building revenue
KPIs from `net_amount`.

### 7. Right-censoring on returns near the dataset's end date
`orders` run through 2024-12-30, but `returns` run through 2025-01-19 —
returns can occur up to ~3 weeks after an order. This means return-rate
KPIs calculated for the final weeks of the dataset will systematically
understate true returns, since not all of their return windows have
closed within the data. Any month-over-month return-rate comparison
should exclude or caveat the last ~3 weeks of order data.

### 8. Touchpoint timestamps — validated against campaign windows
All 520,000 `marketing_touchpoints` timestamps fall within their
campaign's `start_date`/`end_date`. Zero violations.
