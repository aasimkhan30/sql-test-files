/*
    Daily DBA script part C: anomaly detection, regression checks, and
    advanced KPI windowing analyses for ecommerce database.
*/
USE ecommerce;
GO

SET NOCOUNT ON;

DECLARE @snapshot DATETIME2 = SYSUTCDATETIME();

/********************************************************************
 * 6. Regression and anomaly checks
 ********************************************************************/ 
-- Detect spikes in returns vs trailing 7-day average
WITH daily_returns AS (
    SELECT CAST(o.placed_at AS DATE) AS order_date,
           SUM(CASE WHEN o.order_status = 'RETURNED' THEN 1 ELSE 0 END) AS return_orders
    FROM dbo.orders o
    GROUP BY CAST(o.placed_at AS DATE)
), moving_avg AS (
    SELECT dr.order_date,
           dr.return_orders,
           AVG(dr.return_orders) OVER (ORDER BY dr.order_date ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING) AS trailing_avg
    FROM daily_returns dr
)
SELECT *
FROM moving_avg ma
WHERE ma.trailing_avg IS NOT NULL AND ma.return_orders > ma.trailing_avg * 1.5
ORDER BY ma.order_date DESC;

-- Orders without payment or shipment
SELECT o.order_id, o.order_number, o.order_status
FROM dbo.orders o
LEFT JOIN dbo.payments p ON p.order_id = o.order_id
LEFT JOIN dbo.shipments s ON s.order_id = o.order_id
WHERE p.order_id IS NULL OR s.order_id IS NULL;

-- Inventory negative or over-reserved situations
SELECT inventory_id, product_id, warehouse_code, quantity_on_hand, quantity_reserved
FROM dbo.inventory
WHERE quantity_on_hand < 0 OR quantity_reserved > quantity_on_hand;

/********************************************************************
 * 7. Heavier KPI cubes via windowing
 ********************************************************************/ 
-- Daily revenue with cumulative totals and 7-day trend
WITH day_stats AS (
    SELECT CAST(o.placed_at AS DATE) AS day_bucket,
           SUM(o.total_amount) AS revenue
    FROM dbo.orders o
    GROUP BY CAST(o.placed_at AS DATE)
)
SELECT day_bucket,
       revenue,
       SUM(revenue) OVER (ORDER BY day_bucket ROWS UNBOUNDED PRECEDING) AS cumulative_revenue,
       AVG(revenue) OVER (ORDER BY day_bucket ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS moving_avg_7d
FROM day_stats
ORDER BY day_bucket DESC;

-- RFM score distribution (Recency, Frequency, Monetary)
WITH base AS (
    SELECT u.user_id,
           DATEDIFF(DAY, MAX(o.placed_at), @snapshot) AS recency_days,
           COUNT(o.order_id) AS frequency,
           SUM(o.total_amount) AS monetary
    FROM dbo.users u
    LEFT JOIN dbo.orders o ON o.user_id = u.user_id
    GROUP BY u.user_id
), scored AS (
    SELECT *,
           NTILE(5) OVER (ORDER BY recency_days DESC) AS recency_score,
           NTILE(5) OVER (ORDER BY frequency ASC) AS frequency_score,
           NTILE(5) OVER (ORDER BY monetary ASC) AS monetary_score
    FROM base
)
SELECT recency_score, frequency_score, monetary_score, COUNT(*) AS users
FROM scored
GROUP BY recency_score, frequency_score, monetary_score
ORDER BY recency_score, frequency_score, monetary_score;
GO
