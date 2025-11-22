/*
    Daily DBA script part F: fulfillment SLA monitoring, warehouse exposure,
    and reverse logistics insights for ecommerce database.
*/
USE ecommerce;
GO

SET NOCOUNT ON;

DECLARE @snapshot DATETIME2 = SYSUTCDATETIME();

/********************************************************************
 * 14. Shipment SLA compliance
 ********************************************************************/ 
WITH shipping AS (
    SELECT s.order_id,
           o.order_number,
           s.carrier,
           s.status,
           s.shipped_at,
           s.delivered_at,
           DATEDIFF(HOUR, o.placed_at, s.shipped_at) AS hours_to_ship,
           DATEDIFF(HOUR, s.shipped_at, s.delivered_at) AS hours_in_transit
    FROM dbo.shipments s
    JOIN dbo.orders o ON o.order_id = s.order_id
)
SELECT carrier,
       COUNT(*) AS shipments,
       AVG(hours_to_ship) AS avg_hours_to_ship,
       AVG(hours_in_transit) AS avg_hours_in_transit,
       SUM(CASE WHEN hours_to_ship > 24 THEN 1 ELSE 0 END) AS late_fulfillment,
       SUM(CASE WHEN hours_in_transit > 96 THEN 1 ELSE 0 END) AS long_in_transit
FROM shipping
GROUP BY carrier
ORDER BY shipments DESC;

/********************************************************************
 * 15. Orders stuck in process
 ********************************************************************/ 
SELECT o.order_id,
       o.order_number,
       o.order_status,
       o.fulfillment_status,
       o.payment_status,
       o.placed_at,
       DATEDIFF(HOUR, o.placed_at, @snapshot) AS age_hours
FROM dbo.orders o
WHERE (o.order_status NOT IN ('COMPLETED','RETURNED') AND DATEDIFF(HOUR, o.placed_at, @snapshot) > 48)
   OR (o.fulfillment_status <> 'FULFILLED' AND DATEDIFF(HOUR, o.placed_at, @snapshot) > 24)
ORDER BY age_hours DESC;

/********************************************************************
 * 16. Warehouse availability stress test
 ********************************************************************/ 
WITH warehouse_summary AS (
    SELECT warehouse_code,
           SUM(quantity_on_hand) AS total_on_hand,
           SUM(quantity_reserved) AS total_reserved,
           SUM(quantity_on_hand - quantity_reserved) AS available,
           SUM(CASE WHEN quantity_on_hand - quantity_reserved < safety_stock THEN 1 ELSE 0 END) AS safety_violations
    FROM dbo.inventory
    GROUP BY warehouse_code
)
SELECT warehouse_code,
       total_on_hand,
       total_reserved,
       available,
       safety_violations,
       CAST(available * 1.0 / NULLIF(total_on_hand, 0) AS DECIMAL(10,4)) AS availability_ratio
FROM warehouse_summary
ORDER BY availability_ratio ASC;

-- Identify SKUs at risk by warehouse
SELECT TOP (50)
    i.warehouse_code,
    p.sku,
    p.name,
    i.quantity_on_hand,
    i.quantity_reserved,
    i.safety_stock,
    (i.quantity_on_hand - i.quantity_reserved) AS available
FROM dbo.inventory i
JOIN dbo.products p ON p.product_id = i.product_id
WHERE (i.quantity_on_hand - i.quantity_reserved) < i.safety_stock
ORDER BY available ASC;

/********************************************************************
 * 17. Reverse logistics queue
 ********************************************************************/ 
SELECT r.return_id,
       r.order_item_id,
       r.status,
       r.reason,
       r.requested_at,
       DATEDIFF(DAY, r.requested_at, @snapshot) AS days_open,
       oi.order_id,
       o.order_number,
       o.user_id
FROM dbo.return_requests r
JOIN dbo.order_items oi ON oi.order_item_id = r.order_item_id
JOIN dbo.orders o ON o.order_id = oi.order_id
WHERE r.status IN ('PENDING','APPROVED')
ORDER BY days_open DESC;

/********************************************************************
 * 18. Delivery performance by geography
 ********************************************************************/ 
WITH delivery AS (
    SELECT o.order_id,
           a.state,
           a.postal_code,
           DATEDIFF(DAY, o.placed_at, s.delivered_at) AS days_to_deliver
    FROM dbo.orders o
    JOIN dbo.addresses a ON a.address_id = o.shipping_address_id
    JOIN dbo.shipments s ON s.order_id = o.order_id
    WHERE s.delivered_at IS NOT NULL
)
SELECT state,
       AVG(days_to_deliver) AS avg_days,
       MAX(days_to_deliver) AS worst_case,
       COUNT(*) AS deliveries
FROM delivery
GROUP BY state
ORDER BY avg_days DESC;
GO
