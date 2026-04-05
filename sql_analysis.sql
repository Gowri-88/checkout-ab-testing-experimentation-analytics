
CREATE DATABASE IF NOT EXISTS checkout_ab_test;
USE checkout_ab_test;

CREATE TABLE IF NOT EXISTS checkout_sessions (
id INT AUTO_INCREMENT PRIMARY KEY,
user_id VARCHAR(20) NOT NULL,
session_id VARCHAR(20) NOT NULL UNIQUE,
variant CHAR(1) NOT NULL, -- A, B, C, D
device VARCHAR(10) NOT NULL, -- mobile, desktop, tablet
cart_value DECIMAL(8,2) NOT NULL,
discount_applied TINYINT(1) NOT NULL DEFAULT 0, -- 0 or 1
shipping_type VARCHAR(20) NOT NULL,
checkout_steps INT NOT NULL,
time_on_checkout INT NOT NULL, -- seconds
purchase TINYINT(1) NOT NULL DEFAULT 0, -- 0 or 1 (target)
session_date DATE NOT NULL,
INDEX idx_variant (variant),
INDEX idx_device (device),
INDEX idx_date (session_date),
INDEX idx_purchase (purchase)
);
DESCRIBE checkout_sessions;


SELECT * FROM checkout_sessions
LIMIT 10;

-- Conversion Rate by Variant (with uplift vs control)
WITH variant_stats AS (
SELECT
variant,
COUNT(*) AS total_sessions,
SUM(purchase) AS total_purchases,
ROUND(SUM(purchase)*100.0/COUNT(*), 2) AS conv_rate_pct
FROM checkout_sessions
GROUP BY variant
),
control_rate AS (
SELECT conv_rate_pct AS ctrl_rate
FROM variant_stats
WHERE variant = 'A'
)
SELECT
v.variant,
v.total_sessions,
v.total_purchases,
v.conv_rate_pct,
ROUND(v.conv_rate_pct - c.ctrl_rate, 2) AS abs_uplift_pp,
ROUND((v.conv_rate_pct - c.ctrl_rate)/c.ctrl_rate*100, 1) AS rel_uplift_pct
FROM variant_stats v
CROSS JOIN control_rate c
ORDER BY v.conv_rate_pct DESC;


-- Device x Variant breakdown
SELECT
variant,
device,
COUNT(*) AS sessions,
SUM(purchase) AS purchases,
ROUND(SUM(purchase)*100.0/COUNT(*), 2) AS conv_rate_pct
FROM checkout_sessions
GROUP BY variant, device
ORDER BY variant, conv_rate_pct DESC;


-- AOV by variant (only for actual purchasers)
SELECT
variant,
COUNT(*) AS purchasers,
ROUND(AVG(cart_value), 2) AS avg_order_value,
ROUND(SUM(cart_value), 2) AS total_revenue,
ROUND(MIN(cart_value), 2) AS min_order,
ROUND(MAX(cart_value), 2) AS max_order
FROM checkout_sessions
WHERE purchase = 1
GROUP BY variant
ORDER BY avg_order_value DESC;

-- Weekly conversion trend per variant using window functions
WITH weekly_stats AS (
SELECT
variant,
WEEK(session_date, 1) AS week_num,
MIN(session_date) AS week_start,
COUNT(*) AS sessions,
SUM(purchase) AS purchases,
ROUND(SUM(purchase)*100.0/COUNT(*), 2) AS conv_rate
FROM checkout_sessions
GROUP BY variant, WEEK(session_date, 1)
),
weekly_with_rank AS (
SELECT *,
ROW_NUMBER() OVER (PARTITION BY variant ORDER BY week_num) AS week_rank,
AVG(conv_rate) OVER (PARTITION BY variant) AS avg_conv_rate
FROM weekly_stats
)
SELECT
variant,
week_rank AS week,
week_start,
sessions,
purchases,
conv_rate,
ROUND(avg_conv_rate, 2) AS overall_avg
FROM weekly_with_rank
ORDER BY variant, week_rank;


-- Friction analysis by variant
SELECT
variant,
ROUND(AVG(checkout_steps), 2) AS avg_steps,
ROUND(AVG(time_on_checkout), 0) AS avg_time_sec,
ROUND(AVG(time_on_checkout)/60, 1) AS avg_time_min,-- Conditional aggregates
ROUND(AVG(CASE WHEN purchase=1 THEN time_on_checkout END), 0) AS avg_time_converters,
ROUND(AVG(CASE WHEN purchase=0 THEN time_on_checkout END), 0) AS avg_time_non_converters
FROM checkout_sessions
GROUP BY variant
ORDER BY avg_steps;


-- SRM Check using window functions
WITH variant_counts AS (
SELECT variant, COUNT(*) AS n
FROM checkout_sessions
GROUP BY variant
),
totals AS (
SELECT SUM(n) AS grand_total FROM variant_counts
)
SELECT
v.variant,
v.n AS observed,
t.grand_total / 4 AS expected,
ROUND(v.n * 100.0 / t.grand_total, 2) AS observed_pct,
ROUND(ABS(v.n - t.grand_total/4) / (t.grand_total/4) * 100, 2) AS deviation_pct
FROM variant_counts v
CROSS JOIN totals t
ORDER BY v.variant;