/*
    Daily DBA script part B: operational KPIs and heavy leadership reporting
    for ecommerce database.
*/
USE ecommerce;
GO

SET NOCOUNT ON;

DECLARE @snapshot DATETIME2 = SYSUTCDATETIME();

/********************************************************************
 * 4. Operational KPIs
 ********************************************************************/ 
PRINT '===== Operational KPIs =====';
SELECT
    SUM(CASE WHEN o.order_status = 'COMPLETED' THEN o.total_amount ELSE 0 END) AS revenue_last_24h,
    SUM(CASE WHEN o.order_status = 'RETURNED' THEN o.total_amount ELSE 0 END) AS returns_last_24h,
    AVG(o.total_amount) AS avg_order_value,
    COUNT(*) AS total_orders,
    COUNT(DISTINCT o.user_id) AS purchasing_users
FROM dbo.orders o
WHERE o.placed_at >= DATEADD(HOUR, -24, @snapshot);

-- Inventory exposure by warehouse
SELECT
    i.warehouse_code,
    SUM(i.quantity_on_hand - i.quantity_reserved) AS available_units,
    SUM(CASE WHEN (i.quantity_on_hand - i.quantity_reserved) < i.safety_stock THEN 1 ELSE 0 END) AS below_safety_skus,
    SUM(CASE WHEN i.quantity_on_hand < i.reorder_point THEN 1 ELSE 0 END) AS below_reorder_skus
FROM dbo.inventory i
GROUP BY i.warehouse_code
ORDER BY available_units DESC;

/********************************************************************
 * 5. Heavy reporting queries for leadership dashboards
 ********************************************************************/ 
-- Monthly cohort revenue breakdown
WITH cohort AS (
    SELECT u.user_id,
           MIN(CAST(o.placed_at AS DATE)) AS first_purchase_date,
           DATEFROMPARTS(YEAR(MIN(o.placed_at)), MONTH(MIN(o.placed_at)), 1) AS cohort_month
    FROM dbo.orders o
    JOIN dbo.users u ON u.user_id = o.user_id
    GROUP BY u.user_id
), revenue AS (
    SELECT c.cohort_month,
           DATEFROMPARTS(YEAR(o.placed_at), MONTH(o.placed_at), 1) AS revenue_month,
           SUM(o.total_amount) AS cohort_revenue
    FROM dbo.orders o
    JOIN cohort c ON c.user_id = o.user_id
    GROUP BY c.cohort_month, DATEFROMPARTS(YEAR(o.placed_at), MONTH(o.placed_at), 1)
)
SELECT cohort_month,
       revenue_month,
       cohort_revenue,
       ROW_NUMBER() OVER (PARTITION BY cohort_month ORDER BY revenue_month) AS cohort_age_month
FROM revenue
ORDER BY cohort_month, revenue_month;

-- Product performance KPIs
SELECT TOP (25)
    p.product_id,
    p.name,
    SUM(oi.quantity) AS units_sold,
    SUM(oi.line_total) AS line_revenue,
    AVG(pr.rating) AS avg_rating,
    SUM(CASE WHEN r.return_id IS NOT NULL THEN 1 ELSE 0 END) AS return_lines
FROM dbo.products p
JOIN dbo.order_items oi ON oi.product_id = p.product_id
JOIN dbo.orders o ON o.order_id = oi.order_id AND o.order_status NOT IN ('CANCELLED')
LEFT JOIN dbo.product_reviews pr ON pr.product_id = p.product_id
LEFT JOIN dbo.return_requests r ON r.order_item_id = oi.order_item_id
GROUP BY p.product_id, p.name
ORDER BY line_revenue DESC;

-- Promotion effectiveness
SELECT
    pr.promotion_id,
    pr.name,
    COUNT(DISTINCT o.order_id) AS orders,
    SUM(o.discount_amount) AS total_discount,
    SUM(o.total_amount) AS revenue,
    SUM(o.total_amount) / NULLIF(COUNT(DISTINCT o.order_id), 0) AS avg_order_value
FROM dbo.promotions pr
LEFT JOIN dbo.orders o ON o.promotion_id = pr.promotion_id
GROUP BY pr.promotion_id, pr.name
ORDER BY revenue DESC;
GO
