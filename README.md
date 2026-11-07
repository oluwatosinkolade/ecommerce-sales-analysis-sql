# E-Commerce Sales Analysis with SQL

**11 business questions answered with SQL: from basic KPIs to window functions, cohort retention, churn detection and market basket analysis.**

> **Tools:** SQL (SQLite, portable to PostgreSQL) · **Skills shown:** CTEs, window functions (`LAG`, `NTILE`, `ROW_NUMBER`, running totals, moving averages), self-joins, views, conditional aggregation, cohort analysis

---

## 1. Business Scenario

You are the data analyst for an online store selling Electronics, Fashion, Home and Beauty products across 8 Nigerian cities. Leadership wants to know:

- How healthy is the business (revenue, profit, margin)?
- What is the sales trend and which products drive profit?
- Who are our best customers, and which of them are about to churn?
- Where are we losing orders to cancellations and returns?
- Do discounts actually pay off?

## 2. Dataset

A synthetic dataset generated with a fixed random seed, so every result below is reproducible.

| Table | Rows | Description |
|---|---|---|
| `customers` | 300 | customer_id, full_name, city, signup_date |
| `products` | 16 | product_id, product_name, category, unit_price, unit_cost |
| `orders` | 2,600 | order_id, customer_id, order_date, status (Completed / Cancelled / Returned) |
| `order_items` | 5,649 | order_item_id, order_id, product_id, quantity, discount_pct |

Order dates span **Jan 2025 – Aug 2026**.

```
customers (1) ──< orders (1) ──< order_items >── (1) products
```

**Business rules**
- Revenue and profit count only orders with `status = 'Completed'`.
- Net line revenue = `quantity × unit_price × (1 − discount_pct / 100)`.
- Profit = net line revenue − `quantity × unit_cost`.

## 3. Project Files

| File | Purpose |
|---|---|
| `01_schema_and_data.sql` | Creates the tables, indexes and loads all data |
| `02_analysis_queries.sql` | All 11 problems and solutions |
| `ecommerce.db` | Ready-to-open SQLite database |

**Run it yourself**
```bash
sqlite3 ecommerce.db < 02_analysis_queries.sql
# or rebuild from scratch:
sqlite3 new.db < 01_schema_and_data.sql
```

---

## 4. Problems, Solutions and Findings

### Setup: a reusable view
To avoid repeating the same joins and filters in every query, I created one view with a clean row per completed order line, including revenue and profit.

```sql
CREATE VIEW v_completed_lines AS
SELECT o.order_id, o.customer_id, o.order_date,
       p.product_id, p.product_name, p.category, oi.quantity,
       ROUND(oi.quantity * p.unit_price * (1 - oi.discount_pct/100.0), 2) AS revenue,
       ROUND(oi.quantity * (p.unit_price * (1 - oi.discount_pct/100.0) - p.unit_cost), 2) AS profit
FROM orders o
JOIN order_items oi ON oi.order_id  = o.order_id
JOIN products    p  ON p.product_id = oi.product_id
WHERE o.status = 'Completed';
```

---

### Q1. Executive KPI snapshot
**Problem:** Give leadership one row summarising overall performance.

```sql
SELECT COUNT(DISTINCT order_id)                                AS completed_orders,
       COUNT(DISTINCT customer_id)                             AS active_customers,
       ROUND(SUM(revenue), 2)                                  AS total_revenue,
       ROUND(SUM(profit), 2)                                   AS total_profit,
       ROUND(100.0 * SUM(profit) / SUM(revenue), 1)            AS profit_margin_pct,
       ROUND(SUM(revenue) * 1.0 / COUNT(DISTINCT order_id), 2) AS avg_order_value
FROM v_completed_lines;
```

| completed_orders | active_customers | total_revenue | total_profit | profit_margin_pct | avg_order_value |
|---|---|---|---|---|---|
| 2,217 | 268 | 312,703.85 | 117,236.85 | 37.5 | 141.05 |

**Insight:** 2,217 of 2,600 orders (85%) completed, producing about 312.7K in revenue at a healthy 37.5% margin.

---

### Q2. Monthly revenue and month-over-month growth
**Problem:** Show the revenue trend and how each month compares to the previous one.
**Technique:** CTE + `LAG()`

```sql
WITH monthly AS (
    SELECT STRFTIME('%Y-%m', order_date) AS month, ROUND(SUM(revenue), 2) AS revenue
    FROM v_completed_lines GROUP BY 1
)
SELECT month, revenue,
       LAG(revenue) OVER (ORDER BY month) AS prev_month_revenue,
       ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY month))
             / LAG(revenue) OVER (ORDER BY month), 1) AS mom_growth_pct
FROM monthly ORDER BY month;
```

Sample of results:

| month | revenue | prev_month_revenue | mom_growth_pct |
|---|---|---|---|
| 2025-03 | 15,694.90 | 9,025.55 | 73.9 |
| 2025-08 | 20,440.15 | 20,311.40 | 0.6 |
| 2025-10 | 13,293.80 | 17,062.00 | -22.1 |
| 2026-01 | 19,511.75 | 16,135.45 | 20.9 |
| 2026-04 | 13,531.45 | 18,905.50 | -28.4 |
| 2026-08 | 13,656.95 | 14,539.70 | -6.1 |

**Insight:** Revenue peaked in Jul–Aug 2025 (about 20.4K) and has been trending lower since, with 2026 months mostly between 13.5K and 19.5K.

---

### Q3. Top 3 most profitable products per category
**Problem:** Which products should each category team prioritise?
**Technique:** CTE + `ROW_NUMBER() OVER (PARTITION BY ...)`

```sql
WITH product_profit AS (
    SELECT category, product_name, SUM(quantity) AS units_sold,
           ROUND(SUM(revenue),2) AS revenue, ROUND(SUM(profit),2) AS profit
    FROM v_completed_lines GROUP BY category, product_name
),
ranked AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY category ORDER BY profit DESC) AS rn
    FROM product_profit
)
SELECT category, rn AS rank, product_name, units_sold, revenue, profit
FROM ranked WHERE rn <= 3 ORDER BY category, rn;
```

| category | rank | product_name | units_sold | revenue | profit |
|---|---|---|---|---|---|
| Beauty | 1 | Perfume | 482 | 22,865.00 | 11,297.00 |
| Electronics | 1 | Smart Watch | 509 | 43,254.00 | 12,714.00 |
| Fashion | 1 | Sneakers | 477 | 27,075.00 | 10,380.00 |
| Home | 1 | Air Fryer | 552 | 44,280.75 | 12,264.75 |

*(Top pick per category shown; the query returns the top 3 for each.)*

**Insight:** Smart Watch and Air Fryer lead on profit and revenue. Perfume is Beauty's standout: it earns about 11.3K profit on 22.9K revenue, roughly a 49% margin.

---

### Q4. Customer segmentation by spend quartile
**Problem:** Split customers into four value tiers and measure how much revenue each contributes.
**Technique:** `NTILE(4)` + a window total for percent-of-revenue

```sql
WITH customer_spend AS (
    SELECT customer_id, COUNT(DISTINCT order_id) AS orders, ROUND(SUM(revenue), 2) AS total_spend
    FROM v_completed_lines GROUP BY customer_id
),
segmented AS (
    SELECT *, NTILE(4) OVER (ORDER BY total_spend DESC) AS quartile FROM customer_spend
)
SELECT CASE quartile WHEN 1 THEN 'Platinum (top 25%)' WHEN 2 THEN 'Gold'
                     WHEN 3 THEN 'Silver' ELSE 'Bronze' END AS segment,
       COUNT(*) AS customers,
       ROUND(AVG(orders), 1) AS avg_orders,
       ROUND(AVG(total_spend), 2) AS avg_spend,
       ROUND(SUM(total_spend), 2) AS segment_revenue,
       ROUND(100.0 * SUM(total_spend) / SUM(SUM(total_spend)) OVER (), 1) AS pct_of_revenue
FROM segmented GROUP BY quartile ORDER BY quartile;
```

| segment | customers | avg_orders | avg_spend | segment_revenue | pct_of_revenue |
|---|---|---|---|---|---|
| Platinum (top 25%) | 67 | 17.9 | 2,620.31 | 175,561.00 | 56.1 |
| Gold | 67 | 8.6 | 1,230.15 | 82,420.05 | 26.4 |
| Silver | 67 | 4.6 | 616.07 | 41,276.85 | 13.2 |
| Bronze | 67 | 2.0 | 200.69 | 13,445.95 | 4.3 |

**Insight:** The top quartile of customers generates **56.1%** of revenue and spends about 13x more than the bottom quartile. These are the customers worth protecting with loyalty perks.

---

### Q5. Pareto analysis: the 80/20 rule
**Problem:** How many customers does it take to reach 80% of revenue?
**Technique:** Cumulative `SUM() OVER (ORDER BY ... ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)`

```sql
WITH customer_spend AS (
    SELECT customer_id, SUM(revenue) AS spend FROM v_completed_lines GROUP BY customer_id
),
cumulative AS (
    SELECT customer_id, spend,
           SUM(spend) OVER (ORDER BY spend DESC
                            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_spend,
           SUM(spend) OVER ()                         AS total_spend,
           ROW_NUMBER() OVER (ORDER BY spend DESC)    AS customer_rank,
           COUNT(*) OVER ()                           AS total_customers
    FROM customer_spend
)
SELECT MAX(customer_rank) AS customers_needed_for_80pct,
       MAX(total_customers) AS total_customers,
       ROUND(100.0 * MAX(customer_rank) / MAX(total_customers), 1) AS pct_of_customers
FROM cumulative
WHERE running_spend - spend < 0.8 * total_spend;
```

| customers_needed_for_80pct | total_customers | pct_of_customers |
|---|---|---|
| 126 | 268 | 47.0 |

**Insight:** Revenue is less concentrated than the classic 80/20 rule: it takes 47% of customers to reach 80% of revenue. Growth depends on a broad base, not just a few big spenders.

---

### Q6. 3-month moving average and cumulative revenue
**Problem:** Smooth out monthly noise to see the real trend.
**Technique:** Window frame `ROWS BETWEEN 2 PRECEDING AND CURRENT ROW`

```sql
WITH monthly AS (
    SELECT STRFTIME('%Y-%m', order_date) AS month, SUM(revenue) AS revenue
    FROM v_completed_lines GROUP BY 1
)
SELECT month, ROUND(revenue, 2) AS revenue,
       ROUND(AVG(revenue) OVER (ORDER BY month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2) AS moving_avg_3m,
       ROUND(SUM(revenue) OVER (ORDER BY month), 2) AS cumulative_revenue
FROM monthly ORDER BY month;
```

| month | revenue | moving_avg_3m | cumulative_revenue |
|---|---|---|---|
| 2025-08 | 20,440.15 | 19,275.47 | 126,156.75 |
| 2026-01 | 19,511.75 | 16,853.33 | 207,072.55 |
| 2026-06 | 13,549.35 | 14,413.40 | 284,507.20 |
| 2026-08 | 13,656.95 | 13,915.33 | 312,703.85 |

**Insight:** The 3-month average peaked at about 19.3K in Aug 2025 and fell to about 13.9K by Aug 2026, a decline of roughly 28%. This is a clear signal for the growth team to act on.

---

### Q7. Cancellation and return rates by city
**Problem:** Which cities lose the most orders, and why (cancelled vs returned)?
**Technique:** Conditional aggregation

```sql
SELECT c.city, COUNT(*) AS total_orders,
       ROUND(100.0 * SUM(o.status = 'Cancelled') / COUNT(*), 1) AS cancel_rate_pct,
       ROUND(100.0 * SUM(o.status = 'Returned')  / COUNT(*), 1) AS return_rate_pct,
       ROUND(100.0 * SUM(o.status <> 'Completed') / COUNT(*), 1) AS failed_order_pct
FROM orders o JOIN customers c ON c.customer_id = o.customer_id
GROUP BY c.city ORDER BY failed_order_pct DESC;
```

| city | total_orders | cancel_rate_pct | return_rate_pct | failed_order_pct |
|---|---|---|---|---|
| Ibadan | 346 | 8.7 | 7.2 | 15.9 |
| Port Harcourt | 278 | 8.3 | 7.2 | 15.5 |
| Kano | 304 | 8.2 | 6.9 | 15.1 |
| Warri | 344 | 8.7 | 5.8 | 14.5 |
| Enugu | 411 | 7.8 | 6.6 | 14.4 |
| Benin City | 329 | 7.3 | 7.0 | 14.3 |
| Abuja | 343 | 11.1 | 3.2 | 14.3 |
| Lagos | 245 | 6.1 | 7.8 | 13.9 |

**Insight:** Failure rates are similar across cities (13.9% to 15.9%), but the *reasons* differ. Abuja has the highest cancellation rate (11.1%) with the lowest returns (3.2%), pointing to a checkout or delivery-promise issue. Lagos is the opposite (lowest cancellations, highest returns at 7.8%), which suggests product quality or expectation problems.

---

### Q8. Cohort retention analysis
**Problem:** Of the customers who made their first purchase in a given month, what share came back 1, 2 and 3 months later?
**Technique:** Multiple CTEs, month-offset arithmetic, `COUNT(DISTINCT CASE WHEN ...)`

```sql
WITH first_order AS (
    SELECT customer_id, MIN(STRFTIME('%Y-%m-01', order_date)) AS cohort_month
    FROM orders WHERE status = 'Completed' GROUP BY customer_id
),
activity AS (
    SELECT DISTINCT f.cohort_month, f.customer_id,
           (CAST(STRFTIME('%Y', o.order_date) AS INT) - CAST(STRFTIME('%Y', f.cohort_month) AS INT)) * 12
         + (CAST(STRFTIME('%m', o.order_date) AS INT) - CAST(STRFTIME('%m', f.cohort_month) AS INT)) AS month_offset
    FROM first_order f
    JOIN orders o ON o.customer_id = f.customer_id AND o.status = 'Completed'
),
cohort_size AS (SELECT cohort_month, COUNT(*) AS size FROM first_order GROUP BY cohort_month)
SELECT a.cohort_month, cs.size AS cohort_size,
       ROUND(100.0 * COUNT(DISTINCT CASE WHEN a.month_offset = 1 THEN a.customer_id END) / cs.size, 1) AS m1_pct,
       ROUND(100.0 * COUNT(DISTINCT CASE WHEN a.month_offset = 2 THEN a.customer_id END) / cs.size, 1) AS m2_pct,
       ROUND(100.0 * COUNT(DISTINCT CASE WHEN a.month_offset = 3 THEN a.customer_id END) / cs.size, 1) AS m3_pct
FROM activity a JOIN cohort_size cs ON cs.cohort_month = a.cohort_month
GROUP BY a.cohort_month, cs.size
HAVING a.cohort_month <= '2026-03-01'
ORDER BY a.cohort_month;
```

Sample of results (larger cohorts):

| cohort_month | cohort_size | m1_pct | m2_pct | m3_pct |
|---|---|---|---|---|
| 2025-01-01 | 57 | 36.8 | 42.1 | 36.8 |
| 2025-02-01 | 31 | 45.2 | 35.5 | 32.3 |
| 2025-03-01 | 36 | 50.0 | 50.0 | 38.9 |
| 2025-07-01 | 29 | 51.7 | 34.5 | 31.0 |

**Insight:** Early cohorts bring back roughly 30% to 50% of customers in each of the following months. Cohorts from late 2025 onward are tiny (1 to 9 customers), which points to a **customer acquisition slowdown**, consistent with the falling revenue trend in Q6.

**Note:** The January 2025 cohort also includes existing customers whose first purchase happened before the data window starts, so its size is inflated. The `HAVING` clause excludes cohorts without a full 3-month follow-up window.

---

### Q9. Churn risk: valuable customers who went quiet
**Problem:** Build a win-back list of above-average customers with no completed order in the last 90 days.
**Technique:** CTE, `CROSS JOIN` to a reference date, `JULIANDAY` date maths, scalar subquery

```sql
WITH ref AS (SELECT MAX(order_date) AS ref_date FROM orders),
customer_summary AS (
    SELECT customer_id, COUNT(DISTINCT order_id) AS orders,
           ROUND(SUM(revenue), 2) AS lifetime_value, MAX(order_date) AS last_order
    FROM v_completed_lines GROUP BY customer_id
)
SELECT c.customer_id, c.full_name, c.city, s.orders, s.lifetime_value, s.last_order,
       CAST(JULIANDAY(r.ref_date) - JULIANDAY(s.last_order) AS INT) AS days_inactive
FROM customer_summary s
JOIN customers c ON c.customer_id = s.customer_id
CROSS JOIN ref r
WHERE JULIANDAY(r.ref_date) - JULIANDAY(s.last_order) > 90
  AND s.lifetime_value >= (SELECT AVG(lifetime_value) FROM customer_summary)
ORDER BY s.lifetime_value DESC
LIMIT 10;
```

| customer_id | full_name | city | orders | lifetime_value | last_order | days_inactive |
|---|---|---|---|---|---|---|
| 254 | Halima Musa | Lagos | 19 | 2,532.15 | 2026-05-03 | 113 |
| 257 | Femi Bello | Ibadan | 12 | 2,498.30 | 2026-03-29 | 148 |
| 143 | Bola Nwosu | Enugu | 15 | 2,135.85 | 2026-05-22 | 94 |
| 60 | Zainab Eze | Warri | 12 | 1,970.70 | 2026-05-02 | 114 |
| 107 | Sade Okafor | Abuja | 8 | 1,651.15 | 2026-05-14 | 102 |

*(Top 5 of 10 shown.)*

**Insight:** The reference date is the latest order in the data (not today's date), so the result is reproducible. The marketing team can start a win-back campaign with this list, prioritised by lifetime value.

---

### Q10. Market basket analysis
**Problem:** Which products are most often bought together? (Useful for bundles and recommendations.)
**Technique:** Self-join on `order_items` with `a.product_id < b.product_id` to avoid duplicate and mirrored pairs

```sql
SELECT p1.product_name AS product_a, p2.product_name AS product_b,
       COUNT(*) AS times_bought_together
FROM order_items a
JOIN order_items b ON a.order_id = b.order_id AND a.product_id < b.product_id
JOIN orders o      ON o.order_id = a.order_id AND o.status = 'Completed'
JOIN products p1   ON p1.product_id = a.product_id
JOIN products p2   ON p2.product_id = b.product_id
GROUP BY p1.product_name, p2.product_name
ORDER BY times_bought_together DESC
LIMIT 5;
```

| product_a | product_b | times_bought_together |
|---|---|---|
| Smart Watch | Air Fryer | 49 |
| Wireless Earbuds | Bluetooth Speaker | 49 |
| Bluetooth Speaker | Air Fryer | 46 |
| Phone Case | Perfume | 46 |
| Phone Case | Air Fryer | 45 |

**Insight:** Wireless Earbuds + Bluetooth Speaker is a natural bundle. Several top pairs include the Air Fryer, our highest-revenue Home product, which makes it a good anchor for cross-category promotions.

---

### Q11. Do discounts pay off?
**Problem:** Does discounting lift units sold per line, and what does it do to profit?

```sql
SELECT oi.discount_pct, COUNT(*) AS lines_sold,
       ROUND(AVG(oi.quantity), 2) AS avg_units_per_line,
       ROUND(SUM(oi.quantity * (p.unit_price * (1 - oi.discount_pct/100.0) - p.unit_cost)), 2) AS total_profit,
       ROUND(AVG(oi.quantity * (p.unit_price * (1 - oi.discount_pct/100.0) - p.unit_cost)), 2) AS profit_per_line
FROM order_items oi
JOIN orders   o ON o.order_id   = oi.order_id AND o.status = 'Completed'
JOIN products p ON p.product_id = oi.product_id
GROUP BY oi.discount_pct ORDER BY oi.discount_pct;
```

| discount_pct | lines_sold | avg_units_per_line | total_profit | profit_per_line |
|---|---|---|---|---|
| 0 | 2,371 | 1.65 | 64,943.00 | 27.39 |
| 5 | 809 | 1.64 | 19,759.05 | 24.42 |
| 10 | 816 | 1.66 | 17,441.70 | 21.37 |
| 15 | 824 | 1.67 | 15,093.10 | 18.32 |

**Insight:** Units per line barely move (1.65 to 1.67) while profit per line drops from 27.39 to 18.32 at a 15% discount. In this dataset, discounts reduce profit without lifting volume.

**Caveat:** The data is synthetic and discounts were assigned at random, so this reflects the dataset, not a real-world conclusion. With real data, I would also compare against the order counts a discount drives, not only basket size.

---

## 5. Summary of Findings

1. **Healthy margins:** 37.5% profit margin on 312.7K revenue.
2. **Revenue is slowing:** the 3-month average dropped about 28% from its Aug 2025 peak, and new-customer cohorts have shrunk sharply.
3. **Top customers matter:** the top 25% generate 56% of revenue, and a win-back list of high-value churn risks is ready to use.
4. **City problems differ:** Abuja loses orders to cancellations, Lagos to returns.
5. **Discounts hurt profit** in this dataset without growing basket size.

## 6. Recommendations

- Invest in acquisition: new-customer cohorts have almost dried up since late 2025.
- Launch a win-back campaign for the high-value inactive customers (Q9).
- Investigate checkout and delivery in Abuja, and product quality in Lagos.
- Test bundles such as Earbuds + Speaker, and run discount experiments before rolling discounts out widely.

## 7. What I Learned / Skills Demonstrated

- Structuring analysis with CTEs and a reusable view
- Window functions: `LAG`, `NTILE`, `ROW_NUMBER`, running totals, moving averages
- Cohort retention and Pareto analysis in pure SQL
- Self-joins for market basket analysis
- Turning query output into business recommendations

## 8. Dialect Notes (PostgreSQL)

- `STRFTIME('%Y-%m', d)` → `TO_CHAR(d, 'YYYY-MM')`
- `JULIANDAY(a) - JULIANDAY(b)` → `a - b` (on dates)
- `SUM(status = 'x')` → `COUNT(*) FILTER (WHERE status = 'x')`
