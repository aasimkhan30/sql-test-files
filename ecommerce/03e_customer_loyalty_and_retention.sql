/*
    Daily DBA script part E: customer loyalty monitoring, churn detection,
    and retention-focused KPIs for ecommerce database.
*/
USE ecommerce;
GO

SET NOCOUNT ON;

DECLARE @snapshot DATETIME2 = SYSUTCDATETIME();
DECLARE @today DATE = CAST(@snapshot AS DATE);

IF OBJECT_ID('tempdb..#loyalty_scored') IS NOT NULL DROP TABLE #loyalty_scored;

SELECT lb.*,
       CASE
           WHEN lb.lifetime_value >= 10000 THEN 'ELITE'
           WHEN lb.lifetime_value >= 5000 THEN 'PLATINUM'
           WHEN lb.lifetime_value >= 2000 THEN 'GOLD'
           WHEN lb.lifetime_value >= 500 THEN 'SILVER'
           ELSE 'BRONZE'
       END AS loyalty_tier
INTO #loyalty_scored
FROM (
    SELECT u.user_id,
           SUM(o.total_amount) AS lifetime_value,
           SUM(CASE WHEN o.placed_at >= DATEADD(DAY, -90, @snapshot) THEN o.total_amount ELSE 0 END) AS ninety_day_spend,
           MAX(o.placed_at) AS last_purchase_at,
           COUNT(o.order_id) AS total_orders
    FROM dbo.users u
    LEFT JOIN dbo.orders o ON o.user_id = u.user_id
    GROUP BY u.user_id
) AS lb;

/********************************************************************
 * 10. Loyalty tier computations
 ********************************************************************/ 
MERGE reporting.daily_metrics AS target
USING (
    SELECT @today AS metric_date,
           CONCAT('loyalty.tier.', loyalty_tier) AS metric_name,
           CAST(COUNT(*) AS DECIMAL(18,4)) AS metric_value
    FROM #loyalty_scored
    GROUP BY loyalty_tier
) AS src
ON target.metric_date = src.metric_date AND target.metric_name = src.metric_name
WHEN MATCHED THEN UPDATE SET metric_value = src.metric_value, captured_at = @snapshot
WHEN NOT MATCHED THEN INSERT (metric_date, metric_name, metric_value, captured_at)
VALUES (src.metric_date, src.metric_name, src.metric_value, @snapshot);

/********************************************************************
 * 11. Churn risk and retention opportunities
 ********************************************************************/ 
PRINT '===== Churn Risk (no purchase > 60 days) =====';
SELECT TOP (50)
    s.user_id,
    u.email,
    DATEDIFF(DAY, s.last_purchase_at, @snapshot) AS days_since_purchase,
    s.lifetime_value,
    s.loyalty_tier
FROM #loyalty_scored s
JOIN dbo.users u ON u.user_id = s.user_id
WHERE s.last_purchase_at IS NULL OR DATEDIFF(DAY, s.last_purchase_at, @snapshot) > 60
ORDER BY days_since_purchase DESC;

PRINT '===== High value customers needing outreach (AOV high, last order 15-45 days) =====';
WITH customer_spend AS (
    SELECT o.user_id,
           AVG(o.total_amount) AS avg_order_value,
           MAX(o.placed_at) AS last_order,
           COUNT(*) AS frequency_90d
    FROM dbo.orders o
    WHERE o.placed_at >= DATEADD(DAY, -180, @snapshot)
    GROUP BY o.user_id
)
SELECT TOP (50)
    cs.user_id,
    u.email,
    cs.avg_order_value,
    cs.frequency_90d,
    cs.last_order
FROM customer_spend cs
JOIN dbo.users u ON u.user_id = cs.user_id
WHERE cs.avg_order_value > 400 AND cs.frequency_90d >= 2 AND DATEDIFF(DAY, cs.last_order, @snapshot) BETWEEN 15 AND 45
ORDER BY cs.avg_order_value DESC;

/********************************************************************
 * 12. Loyalty point adjustments audit
 ********************************************************************/ 
WITH recent_orders AS (
    SELECT o.user_id,
           SUM(o.total_amount) AS revenue_last_7d
    FROM dbo.orders o
    WHERE o.placed_at >= DATEADD(DAY, -7, @snapshot)
    GROUP BY o.user_id
)
SELECT ro.user_id,
       u.email,
       ro.revenue_last_7d,
       u.loyalty_points,
       CASE WHEN ro.revenue_last_7d > 0 THEN (ro.revenue_last_7d * 0.1) ELSE 0 END AS suggested_bonus_points
FROM recent_orders ro
JOIN dbo.users u ON u.user_id = ro.user_id
ORDER BY ro.revenue_last_7d DESC;

/********************************************************************
 * 13. Segment-level contribution
 ********************************************************************/ 
SELECT loyalty_tier,
       COUNT(*) AS users,
       SUM(lifetime_value) AS total_value,
       AVG(lifetime_value) AS avg_value,
       SUM(CASE WHEN last_purchase_at >= DATEADD(DAY, -30, @snapshot) THEN lifetime_value ELSE 0 END) AS active_value_30d
FROM #loyalty_scored
GROUP BY loyalty_tier
ORDER BY total_value DESC;
GO
