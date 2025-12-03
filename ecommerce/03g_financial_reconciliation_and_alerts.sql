/*
    Daily DBA script part G: payments reconciliation, tax exposure, and
    financial control checks for ecommerce database.
*/
USE ecommerce;
GO

SET NOCOUNT ON;

DECLARE @snapshot DATETIME2 = SYSUTCDATETIME();
DECLARE @today DATE = CAST(@snapshot AS DATE);

/********************************************************************
 * 19. Order vs payment reconciliation
 ********************************************************************/ 
WITH order_payments AS (
    SELECT o.order_id,
           o.order_number,
           o.total_amount,
           ISNULL(SUM(p.amount), 0) AS paid_amount
    FROM dbo.orders o
    LEFT JOIN dbo.payments p ON p.order_id = o.order_id AND p.status IN ('CAPTURED','SETTLED')
    GROUP BY o.order_id, o.order_number, o.total_amount
)
SELECT *
FROM order_payments
WHERE ABS(total_amount - paid_amount) > 1
ORDER BY order_id;

/********************************************************************
 * 20. Tax liability by state and day
 ********************************************************************/ 
WITH tax_rollup AS (
    SELECT CAST(o.placed_at AS DATE) AS tax_date,
           a.state,
           SUM(o.tax_amount) AS tax_amount
    FROM dbo.orders o
    JOIN dbo.addresses a ON a.address_id = o.shipping_address_id
    WHERE o.order_status NOT IN ('CANCELLED')
    GROUP BY CAST(o.placed_at AS DATE), a.state
)
MERGE reporting.daily_metrics AS target
USING (
    SELECT tax_date AS metric_date,
           CONCAT('tax.', a.state) AS metric_name,
           CAST(tax_amount AS DECIMAL(18,4)) AS metric_value
    FROM tax_rollup a
) AS src
ON target.metric_date = src.metric_date AND target.metric_name = src.metric_name
WHEN MATCHED THEN UPDATE SET metric_value = src.metric_value, captured_at = @snapshot
WHEN NOT MATCHED THEN INSERT (metric_date, metric_name, metric_value, captured_at)
VALUES (src.metric_date, src.metric_name, src.metric_value, @snapshot);

/********************************************************************
 * 21. Promotion liability tracking
 ********************************************************************/ 
SELECT pr.promotion_id,
       pr.name,
       SUM(o.discount_amount) AS discounts_taken,
       pr.max_redemptions,
       COUNT(o.order_id) AS redemption_count,
       CASE WHEN pr.max_redemptions IS NOT NULL AND COUNT(o.order_id) >= pr.max_redemptions * 0.9
            THEN 'NEAR_LIMIT'
            ELSE 'OK'
       END AS status
FROM dbo.promotions pr
LEFT JOIN dbo.orders o ON o.promotion_id = pr.promotion_id
GROUP BY pr.promotion_id, pr.name, pr.max_redemptions
ORDER BY discounts_taken DESC;

/********************************************************************
 * 22. Payment settlement latency
 ********************************************************************/ 
WITH payment_latency AS (
    SELECT p.payment_id,
           p.order_id,
           p.amount,
           p.status,
           DATEDIFF(HOUR, o.placed_at, p.processed_at) AS hours_to_payment
    FROM dbo.payments p
    JOIN dbo.orders o ON o.order_id = p.order_id
)
SELECT status,
       COUNT(*) AS payments,
       AVG(hours_to_payment) AS avg_hours,
       MAX(hours_to_payment) AS worst_case,
       SUM(amount) AS total_amount
FROM payment_latency
GROUP BY status
ORDER BY total_amount DESC;

/********************************************************************
 * 23. Daily cash summary snapshot
 ********************************************************************/ 
WITH cash_today AS (
    SELECT CAST(p.processed_at AS DATE) AS process_date,
           SUM(CASE WHEN p.status IN ('CAPTURED','SETTLED') THEN p.amount ELSE 0 END) AS cash_captured,
           SUM(CASE WHEN p.status = 'REFUNDED' THEN p.amount ELSE 0 END) AS refunds
    FROM dbo.payments p
    GROUP BY CAST(p.processed_at AS DATE)
), metrics AS (
    SELECT process_date AS metric_date,
           'cash.captured' AS metric_name,
           CAST(cash_captured AS DECIMAL(18,4)) AS metric_value
    FROM cash_today
    UNION ALL
    SELECT process_date, 'cash.refunds', CAST(refunds AS DECIMAL(18,4))
    FROM cash_today
)
MERGE reporting.daily_metrics AS t
USING metrics AS s
ON t.metric_date = s.metric_date AND t.metric_name = s.metric_name
WHEN MATCHED THEN UPDATE SET metric_value = s.metric_value, captured_at = @snapshot
WHEN NOT MATCHED THEN INSERT (metric_date, metric_name, metric_value, captured_at)
VALUES (s.metric_date, s.metric_name, s.metric_value, @snapshot);

/********************************************************************
 * 24. Extended settlement exposure stress test (long runner)
 ********************************************************************/ 
DECLARE @financial_window INT = 60; -- days of history to scan

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
    WHERE o.placed_at >= DATEADD(DAY, -@financial_window, @snapshot)
), item_financials AS (
    SELECT bo.order_id,
           SUM(oi.line_total) AS recognized_revenue,
           SUM(oi.quantity) AS units_sold,
           SUM(oi.quantity * p.cost) AS estimated_cost,
           COUNT(DISTINCT oi.product_id) AS unique_products
    FROM base_orders bo
    JOIN dbo.order_items oi ON oi.order_id = bo.order_id
    JOIN dbo.products p ON p.product_id = oi.product_id
    GROUP BY bo.order_id
), payment_rollup AS (
    SELECT bo.order_id,
           SUM(CASE WHEN p.status IN ('CAPTURED','SETTLED') THEN p.amount ELSE 0 END) AS captured_amount,
           SUM(CASE WHEN p.status = 'REFUNDED' THEN p.amount ELSE 0 END) AS refunded_amount,
           SUM(CASE WHEN p.status IN ('AUTHORIZED','PENDING') THEN p.amount ELSE 0 END) AS pending_amount,
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
), returns_rollup AS (
    SELECT oi.order_id,
           SUM(rr.quantity * (oi.list_price - oi.discount_amount)) AS return_value,
           SUM(rr.quantity) AS return_units,
           MAX(rr.requested_at) AS last_return_request
    FROM dbo.return_requests rr
    JOIN dbo.order_items oi ON oi.order_item_id = rr.order_item_id
    WHERE rr.requested_at >= DATEADD(DAY, -@financial_window, @snapshot)
    GROUP BY oi.order_id
), exposure AS (
    SELECT bo.order_date,
           bo.order_id,
           bo.order_number,
           bo.order_status,
           bo.payment_status,
           bo.fulfillment_status,
           bo.placed_at,
           ISNULL(i.recognized_revenue, 0) AS recognized_revenue,
           ISNULL(i.estimated_cost, 0) AS estimated_cost,
           ISNULL(i.units_sold, 0) AS units_sold,
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
    LEFT JOIN item_financials i ON i.order_id = bo.order_id
    LEFT JOIN payment_rollup pr ON pr.order_id = bo.order_id
    LEFT JOIN returns_rollup rr ON rr.order_id = bo.order_id
    LEFT JOIN shipment_rollup sh ON sh.order_id = bo.order_id
), daily_rollup AS (
    SELECT e.order_date,
           DATENAME(WEEKDAY, e.order_date) AS weekday_name,
           COUNT(*) AS orders,
           SUM(e.units_sold) AS units,
           SUM(e.recognized_revenue) AS gross_revenue,
           SUM(e.estimated_cost) AS estimated_cost,
           SUM(e.recognized_revenue - e.estimated_cost) AS est_margin,
           SUM(e.captured_amount) AS captured_cash,
           SUM(e.refunded_amount) AS refunded_cash,
           SUM(e.pending_amount) AS pending_cash,
           SUM(e.return_value) AS pending_returns_value,
           SUM(e.unsettled_cash) AS unsettled_cash,
           SUM(CASE WHEN e.fulfillment_status NOT IN ('DELIVERED','CLOSED') THEN e.recognized_revenue ELSE 0 END) AS open_fulfillment_value,
           AVG(CASE WHEN e.final_delivery_date IS NOT NULL AND e.first_ship_date IS NOT NULL THEN DATEDIFF(HOUR, e.first_ship_date, e.final_delivery_date) END) AS avg_ship_to_delivery_hours,
           MAX(CASE WHEN e.last_payment_at IS NOT NULL THEN DATEDIFF(HOUR, e.placed_at, e.last_payment_at) END) AS max_payment_lag_hours
    FROM exposure e
    GROUP BY e.order_date
)
SELECT order_date,
       weekday_name,
       orders,
       units,
       gross_revenue,
       estimated_cost,
       est_margin,
       captured_cash,
       refunded_cash,
       pending_cash,
       pending_returns_value,
       unsettled_cash,
       open_fulfillment_value,
       avg_ship_to_delivery_hours,
       max_payment_lag_hours,
       SUM(gross_revenue) OVER (ORDER BY order_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS revenue_trailing_7d,
       SUM(est_margin) OVER (ORDER BY order_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS margin_trailing_7d,
       SUM(unsettled_cash) OVER (ORDER BY order_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS unsettled_trailing_7d
FROM daily_rollup
ORDER BY order_date;
GO
