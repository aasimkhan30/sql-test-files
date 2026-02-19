/*
    Long-running settlement exposure and reconciliation script for the
    ecommerce sample database. This script intentionally performs heavy
    analytics across multiple fact tables to simulate workload.
*/
USE ecommerce;
GO

SET NOCOUNT ON;

DECLARE @as_of DATETIME2 = SYSUTCDATETIME();
DECLARE @window_days INT = 60; -- lookback horizon for stress period
DECLARE @orders_cutoff DATETIME2 = DATEADD(DAY, -@window_days, @as_of);

/********************************************************************
 * Extended financial exposure aggregation
 ********************************************************************/
WITH base_orders AS (
    SELECT o.order_id,
           o.order_number,
           o.user_id,
           o.order_status,
           o.payment_status,
           o.fulfillment_status,
           o.promotion_id,
           o.subtotal_amount,
           o.tax_amount,
           o.shipping_amount,
           o.discount_amount,
           o.total_amount,
           CAST(o.placed_at AS DATE) AS order_date,
           o.placed_at
    FROM dbo.orders o
    WHERE o.placed_at >= @orders_cutoff
), item_rollup AS (
    SELECT bo.order_id,
           SUM(oi.line_total) AS recognized_revenue,
           SUM(oi.quantity) AS units_sold,
           SUM(oi.quantity * p.cost) AS estimated_cost,
           COUNT(DISTINCT oi.product_id) AS unique_products,
           MAX(p.category_id) AS sample_category
    FROM base_orders bo
    JOIN dbo.order_items oi ON oi.order_id = bo.order_id
    JOIN dbo.products p ON p.product_id = oi.product_id
    GROUP BY bo.order_id
), payment_rollup AS (
    SELECT bo.order_id,
           SUM(CASE WHEN p.status IN ('CAPTURED','SETTLED') THEN p.amount ELSE 0 END) AS captured_amount,
           SUM(CASE WHEN p.status IN ('AUTHORIZED','PENDING') THEN p.amount ELSE 0 END) AS pending_amount,
           SUM(CASE WHEN p.status = 'REFUNDED' THEN p.amount ELSE 0 END) AS refunded_amount,
           MAX(p.processed_at) AS last_payment_at
    FROM base_orders bo
    LEFT JOIN dbo.payments p ON p.order_id = bo.order_id
    GROUP BY bo.order_id
), shipment_rollup AS (
    SELECT bo.order_id,
           MIN(s.shipped_at) AS first_ship_date,
           MAX(s.delivered_at) AS final_delivery_date,
           MAX(CASE WHEN s.status = 'DELIVERED' THEN 1 ELSE 0 END) AS delivered_flag
    FROM base_orders bo
    LEFT JOIN dbo.shipments s ON s.order_id = bo.order_id
    GROUP BY bo.order_id
), return_rollup AS (
    SELECT oi.order_id,
           SUM(rr.quantity * (oi.list_price - oi.discount_amount)) AS return_value,
           SUM(rr.quantity) AS return_units,
           MAX(rr.requested_at) AS last_return_request
    FROM dbo.return_requests rr
    JOIN dbo.order_items oi ON oi.order_item_id = rr.order_item_id
    WHERE rr.requested_at >= @orders_cutoff
    GROUP BY oi.order_id
), exposure AS (
    SELECT bo.order_id,
           bo.order_number,
           bo.order_date,
           bo.placed_at,
           bo.order_status,
           bo.payment_status,
           bo.fulfillment_status,
           bo.total_amount,
           ISNULL(ir.recognized_revenue, 0) AS recognized_revenue,
           ISNULL(ir.estimated_cost, 0) AS estimated_cost,
           ISNULL(ir.units_sold, 0) AS units_sold,
           ISNULL(ir.unique_products, 0) AS unique_products,
           ISNULL(pr.captured_amount, 0) AS captured_amount,
           ISNULL(pr.pending_amount, 0) AS pending_amount,
           ISNULL(pr.refunded_amount, 0) AS refunded_amount,
           pr.last_payment_at,
           ISNULL(rr.return_value, 0) AS return_value,
           ISNULL(rr.return_units, 0) AS return_units,
           rr.last_return_request,
           sh.first_ship_date,
           sh.final_delivery_date,
           sh.delivered_flag,
           CASE
               WHEN ISNULL(pr.captured_amount, 0) > ISNULL(pr.refunded_amount, 0)
                    AND (ISNULL(sh.delivered_flag, 0) = 0 OR ISNULL(rr.return_value, 0) > 0)
               THEN ISNULL(pr.captured_amount, 0) - ISNULL(pr.refunded_amount, 0)
               ELSE 0
           END AS unsettled_cash
    FROM base_orders bo
    LEFT JOIN item_rollup ir ON ir.order_id = bo.order_id
    LEFT JOIN payment_rollup pr ON pr.order_id = bo.order_id
    LEFT JOIN shipment_rollup sh ON sh.order_id = bo.order_id
    LEFT JOIN return_rollup rr ON rr.order_id = bo.order_id
), daily_rollup AS (
    SELECT e.order_date,
           DATENAME(WEEKDAY, e.order_date) AS weekday_name,
           COUNT(*) AS orders,
           SUM(e.units_sold) AS units,
           SUM(e.unique_products) AS unique_products,
           SUM(e.recognized_revenue) AS gross_revenue,
           SUM(e.estimated_cost) AS estimated_cost,
           SUM(e.recognized_revenue - e.estimated_cost) AS est_margin,
           SUM(e.captured_amount) AS captured_cash,
           SUM(e.pending_amount) AS pending_cash,
           SUM(e.refunded_amount) AS refunded_cash,
           SUM(e.return_value) AS returns_value,
           SUM(e.unsettled_cash) AS unsettled_cash,
           SUM(CASE WHEN e.fulfillment_status NOT IN ('DELIVERED','CLOSED') THEN e.recognized_revenue ELSE 0 END) AS open_fulfillment_value,
           AVG(CASE WHEN e.final_delivery_date IS NOT NULL AND e.first_ship_date IS NOT NULL THEN DATEDIFF(HOUR, e.first_ship_date, e.final_delivery_date) END) AS avg_ship_to_delivery_hours,
           MAX(CASE WHEN e.last_payment_at IS NOT NULL THEN DATEDIFF(HOUR, e.placed_at, e.last_payment_at) END) AS max_payment_lag_hours
    FROM exposure e
    GROUP BY e.order_date
), moving_windows AS (
    SELECT dr.*,
           SUM(gross_revenue) OVER (ORDER BY order_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS revenue_trailing_7d,
           SUM(est_margin) OVER (ORDER BY order_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS margin_trailing_7d,
           SUM(unsettled_cash) OVER (ORDER BY order_date ROWS BETWEEN 29 PRECEDING AND CURRENT ROW) AS unsettled_trailing_30d,
           SUM(open_fulfillment_value) OVER (ORDER BY order_date ROWS BETWEEN 13 PRECEDING AND CURRENT ROW) AS open_fulfillment_trailing_14d
    FROM daily_rollup dr
)
SELECT order_date,
       weekday_name,
       orders,
       units,
       unique_products,
       gross_revenue,
       estimated_cost,
       est_margin,
       captured_cash,
       pending_cash,
       refunded_cash,
       returns_value,
       unsettled_cash,
       open_fulfillment_value,
       avg_ship_to_delivery_hours,
       max_payment_lag_hours,
       revenue_trailing_7d,
       margin_trailing_7d,
       unsettled_trailing_30d,
       open_fulfillment_trailing_14d
FROM moving_windows
ORDER BY order_date;
