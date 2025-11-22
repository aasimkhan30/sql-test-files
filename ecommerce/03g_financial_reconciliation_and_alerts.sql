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
GO
