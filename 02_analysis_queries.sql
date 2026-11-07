-- ============================================================
-- E-COMMERCE SALES ANALYSIS: SQL QUERIES
-- Dialect: SQLite 3.25+ (window functions). Portable to PostgreSQL
-- with minor changes (noted inline).
-- Business rule: revenue counts ONLY orders with status = 'Completed'.
-- Net line revenue = quantity * unit_price * (1 - discount_pct/100)
-- ============================================================

-- ### Q0 | Helper view: one clean row per completed order line
DROP VIEW IF EXISTS v_completed_lines;
CREATE VIEW v_completed_lines AS
SELECT
    o.order_id,
    o.customer_id,
    o.order_date,
    p.product_id,
    p.product_name,
    p.category,
    oi.quantity,
    ROUND(oi.quantity * p.unit_price * (1 - oi.discount_pct / 100.0), 2)            AS revenue,
    ROUND(oi.quantity * (p.unit_price * (1 - oi.discount_pct / 100.0) - p.unit_cost), 2) AS profit
FROM orders o
JOIN order_items oi ON oi.order_id   = o.order_id
JOIN products    p  ON p.product_id  = oi.product_id
WHERE o.status = 'Completed';

-- ### Q1 | Executive KPI snapshot: revenue, profit, margin, AOV
SELECT
    COUNT(DISTINCT order_id)                                  AS completed_orders,
    COUNT(DISTINCT customer_id)                               AS active_customers,
    ROUND(SUM(revenue), 2)                                    AS total_revenue,
    ROUND(SUM(profit), 2)                                     AS total_profit,
    ROUND(100.0 * SUM(profit) / SUM(revenue), 1)              AS profit_margin_pct,
    ROUND(SUM(revenue) * 1.0 / COUNT(DISTINCT order_id), 2)   AS avg_order_value
FROM v_completed_lines;

-- ### Q2 | Monthly revenue with month-over-month growth (LAG)
WITH monthly AS (
    SELECT STRFTIME('%Y-%m', order_date) AS month,
           ROUND(SUM(revenue), 2)        AS revenue
    FROM v_completed_lines
    GROUP BY 1
)
SELECT
    month,
    revenue,
    LAG(revenue) OVER (ORDER BY month)                                    AS prev_month_revenue,
    ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY month))
          / LAG(revenue) OVER (ORDER BY month), 1)                        AS mom_growth_pct
FROM monthly
ORDER BY month;

-- ### Q3 | Top 3 products by profit in each category (ROW_NUMBER + CTE)
WITH product_profit AS (
    SELECT category, product_name,
           SUM(quantity)         AS units_sold,
           ROUND(SUM(revenue),2) AS revenue,
           ROUND(SUM(profit),2)  AS profit
    FROM v_completed_lines
    GROUP BY category, product_name
),
ranked AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY category ORDER BY profit DESC) AS rn
    FROM product_profit
)
SELECT category, rn AS rank, product_name, units_sold, revenue, profit
FROM ranked
WHERE rn <= 3
ORDER BY category, rn;

-- ### Q4 | Customer value segmentation using spend quartiles (NTILE)
WITH customer_spend AS (
    SELECT customer_id,
           COUNT(DISTINCT order_id) AS orders,
           ROUND(SUM(revenue), 2)   AS total_spend
    FROM v_completed_lines
    GROUP BY customer_id
),
segmented AS (
    SELECT *,
           NTILE(4) OVER (ORDER BY total_spend DESC) AS quartile
    FROM customer_spend
)
SELECT
    CASE quartile WHEN 1 THEN 'Platinum (top 25%)'
                  WHEN 2 THEN 'Gold'
                  WHEN 3 THEN 'Silver'
                  ELSE 'Bronze' END                          AS segment,
    COUNT(*)                                                 AS customers,
    ROUND(AVG(orders), 1)                                    AS avg_orders,
    ROUND(AVG(total_spend), 2)                               AS avg_spend,
    ROUND(SUM(total_spend), 2)                               AS segment_revenue,
    ROUND(100.0 * SUM(total_spend) / SUM(SUM(total_spend)) OVER (), 1) AS pct_of_revenue
FROM segmented
GROUP BY quartile
ORDER BY quartile;

-- ### Q5 | Pareto analysis: how many customers generate 80% of revenue?
WITH customer_spend AS (
    SELECT customer_id, SUM(revenue) AS spend
    FROM v_completed_lines
    GROUP BY customer_id
),
cumulative AS (
    SELECT customer_id, spend,
           SUM(spend) OVER (ORDER BY spend DESC
                            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_spend,
           SUM(spend) OVER ()                                                 AS total_spend,
           ROW_NUMBER() OVER (ORDER BY spend DESC)                            AS customer_rank,
           COUNT(*) OVER ()                                                   AS total_customers
    FROM customer_spend
)
SELECT
    MAX(customer_rank)                                                     AS customers_needed_for_80pct,
    MAX(total_customers)                                                   AS total_customers,
    ROUND(100.0 * MAX(customer_rank) / MAX(total_customers), 1)            AS pct_of_customers
FROM cumulative
WHERE running_spend - spend < 0.8 * total_spend;

-- ### Q6 | 3-month moving average of revenue (window frame)
WITH monthly AS (
    SELECT STRFTIME('%Y-%m', order_date) AS month,
           SUM(revenue)                  AS revenue
    FROM v_completed_lines
    GROUP BY 1
)
SELECT
    month,
    ROUND(revenue, 2) AS revenue,
    ROUND(AVG(revenue) OVER (ORDER BY month
                             ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2) AS moving_avg_3m,
    ROUND(SUM(revenue) OVER (ORDER BY month), 2)                           AS cumulative_revenue
FROM monthly
ORDER BY month;

-- ### Q7 | Cancellation and return rates by city
SELECT
    c.city,
    COUNT(*)                                                                AS total_orders,
    ROUND(100.0 * SUM(o.status = 'Cancelled') / COUNT(*), 1)                AS cancel_rate_pct,
    ROUND(100.0 * SUM(o.status = 'Returned')  / COUNT(*), 1)                AS return_rate_pct,
    ROUND(100.0 * SUM(o.status <> 'Completed') / COUNT(*), 1)               AS failed_order_pct
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
GROUP BY c.city
ORDER BY failed_order_pct DESC;
-- PostgreSQL: replace SUM(o.status = 'x') with COUNT(*) FILTER (WHERE o.status = 'x')

-- ### Q8 | Cohort retention: % of customers returning in months 1, 2, 3 after first purchase
WITH first_order AS (
    SELECT customer_id,
           MIN(STRFTIME('%Y-%m-01', order_date)) AS cohort_month
    FROM orders
    WHERE status = 'Completed'
    GROUP BY customer_id
),
activity AS (
    SELECT DISTINCT
           f.cohort_month,
           f.customer_id,
           (CAST(STRFTIME('%Y', o.order_date) AS INT) - CAST(STRFTIME('%Y', f.cohort_month) AS INT)) * 12
         + (CAST(STRFTIME('%m', o.order_date) AS INT) - CAST(STRFTIME('%m', f.cohort_month) AS INT)) AS month_offset
    FROM first_order f
    JOIN orders o ON o.customer_id = f.customer_id AND o.status = 'Completed'
),
cohort_size AS (
    SELECT cohort_month, COUNT(*) AS size FROM first_order GROUP BY cohort_month
)
SELECT
    a.cohort_month,
    cs.size AS cohort_size,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN a.month_offset = 1 THEN a.customer_id END) / cs.size, 1) AS m1_pct,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN a.month_offset = 2 THEN a.customer_id END) / cs.size, 1) AS m2_pct,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN a.month_offset = 3 THEN a.customer_id END) / cs.size, 1) AS m3_pct
FROM activity a
JOIN cohort_size cs ON cs.cohort_month = a.cohort_month
GROUP BY a.cohort_month, cs.size
HAVING a.cohort_month <= '2026-03-01'
ORDER BY a.cohort_month;

-- ### Q9 | Churn risk: high-value customers with no completed order in the last 90 days
-- Reference date = latest order date in the data (so the query is reproducible)
WITH ref AS (
    SELECT MAX(order_date) AS ref_date FROM orders
),
customer_summary AS (
    SELECT customer_id,
           COUNT(DISTINCT order_id) AS orders,
           ROUND(SUM(revenue), 2)   AS lifetime_value,
           MAX(order_date)          AS last_order
    FROM v_completed_lines
    GROUP BY customer_id
)
SELECT
    c.customer_id,
    c.full_name,
    c.city,
    s.orders,
    s.lifetime_value,
    s.last_order,
    CAST(JULIANDAY(r.ref_date) - JULIANDAY(s.last_order) AS INT) AS days_inactive
FROM customer_summary s
JOIN customers c ON c.customer_id = s.customer_id
CROSS JOIN ref r
WHERE JULIANDAY(r.ref_date) - JULIANDAY(s.last_order) > 90
  AND s.lifetime_value >= (SELECT AVG(lifetime_value) FROM customer_summary)
ORDER BY s.lifetime_value DESC
LIMIT 10;

-- ### Q10 | Market basket analysis: top product pairs bought together (self-join)
SELECT
    p1.product_name AS product_a,
    p2.product_name AS product_b,
    COUNT(*)        AS times_bought_together
FROM order_items a
JOIN order_items b  ON a.order_id = b.order_id AND a.product_id < b.product_id
JOIN orders o       ON o.order_id = a.order_id AND o.status = 'Completed'
JOIN products p1    ON p1.product_id = a.product_id
JOIN products p2    ON p2.product_id = b.product_id
GROUP BY p1.product_name, p2.product_name
ORDER BY times_bought_together DESC
LIMIT 5;

-- ### Q11 | Discount effectiveness: does discounting increase basket size and profit?
SELECT
    oi.discount_pct                                              AS discount_pct,
    COUNT(*)                                                     AS lines_sold,
    ROUND(AVG(oi.quantity), 2)                                   AS avg_units_per_line,
    ROUND(SUM(oi.quantity * (p.unit_price * (1 - oi.discount_pct/100.0) - p.unit_cost)), 2) AS total_profit,
    ROUND(AVG(oi.quantity * (p.unit_price * (1 - oi.discount_pct/100.0) - p.unit_cost)), 2) AS profit_per_line
FROM order_items oi
JOIN orders   o ON o.order_id   = oi.order_id AND o.status = 'Completed'
JOIN products p ON p.product_id = oi.product_id
GROUP BY oi.discount_pct
ORDER BY oi.discount_pct;
