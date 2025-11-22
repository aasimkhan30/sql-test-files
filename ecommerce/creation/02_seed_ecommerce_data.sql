/*
    Seeds ecommerce database with representative lookup values and
    deterministic dummy data to make reporting queries more realistic.
*/
USE ecommerce;
GO

SET NOCOUNT ON;

-- Users
INSERT INTO dbo.users (email, password_hash, first_name, last_name, phone_number, marketing_opt_in, preferred_language, loyalty_points)
VALUES
('alex@example.com', REPLICATE('a', 64), 'Alex', 'Rivera', '+15555550001', 1, 'en', 1200),
('bianca@example.com', REPLICATE('b', 64), 'Bianca', 'Stone', '+15555550002', 1, 'en', 800),
('carl@example.com', REPLICATE('c', 64), 'Carl', 'Young', '+15555550003', 0, 'es', 450),
('danielle@example.com', REPLICATE('d', 64), 'Danielle', 'Green', '+15555550004', 1, 'en', 2400),
('elliot@example.com', REPLICATE('e', 64), 'Elliot', 'James', '+15555550005', 0, 'fr', 130);

-- Addresses
INSERT INTO dbo.addresses (user_id, type, line1, city, state, postal_code, country, is_default)
SELECT user_id,
       CASE WHEN user_id % 2 = 0 THEN 'shipping' ELSE 'billing' END,
       CONCAT('10', user_id, ' Market St'),
       'Metropolis',
       'CA',
       CONCAT('90', RIGHT('00' + CAST(user_id AS VARCHAR(2)), 2)),
       'USA',
       1
FROM dbo.users;

-- Categories
INSERT INTO dbo.categories (parent_id, name, description, display_order)
VALUES
(NULL, 'Electronics', 'Phones, laptops, and gadgets', 1),
(100, 'Smartphones', 'Devices for communication', 2),
(100, 'Laptops', 'Portable computers', 3),
(NULL, 'Home & Kitchen', 'Appliances and decor', 4),
(NULL, 'Sports', 'Fitness and sports equipment', 5);

-- Suppliers
INSERT INTO dbo.suppliers (name, contact, email, phone, rating)
VALUES
('Northwind Imports', 'Jamie Cruz', 'sales@northwind.test', '+15555550100', 4.3),
('Pacific Wholesale', 'Morgan Chen', 'hello@pacific.test', '+15555550101', 4.8),
('Sunrise Goods', 'Taylor Sky', 'team@sunrise.test', '+15555550102', 4.0);

-- Products
INSERT INTO dbo.products (sku, name, description, category_id, supplier_id, price, cost, is_active)
VALUES
('ELEC-001', '5G Smartphone', 'Flagship phone with OLED display', 101, 1, 899.00, 500.00, 1),
('ELEC-002', 'Ultrabook Laptop', 'Lightweight laptop with long battery life', 102, 2, 1299.00, 800.00, 1),
('HOME-001', 'Smart Blender', 'Wi-Fi enabled blender', 103, 3, 199.00, 90.00, 1),
('SPORT-001', 'Fitness Tracker', 'Waterproof fitness wearable', 104, 1, 149.00, 60.00, 1),
('ELEC-003', 'Noise Cancelling Headphones', 'Premium over-ear headphones', 101, 2, 349.00, 150.00, 1),
('HOME-002', 'Air Purifier', 'HEPA purifier with app control', 103, 3, 299.00, 160.00, 1);

-- Inventory snapshots
INSERT INTO dbo.inventory (product_id, warehouse_code, quantity_on_hand, quantity_reserved, safety_stock, reorder_point)
SELECT p.product_id,
       wh.warehouse_code,
       ABS(CHECKSUM(NEWID())) % 500 + 25,
       ABS(CHECKSUM(NEWID())) % 100,
       25,
       50
FROM dbo.products p
CROSS JOIN (VALUES ('WHS-WEST'), ('WHS-EAST'), ('WHS-CENTRAL')) AS wh(warehouse_code);

-- Promotions
INSERT INTO dbo.promotions (name, description, promo_code, discount_type, discount_value, start_date, end_date, max_redemptions)
VALUES
('Spring Sale', 'Sitewide 10% off', 'SPRING10', 'percent', 10, DATEADD(DAY, -30, CAST(GETDATE() AS DATE)), DATEADD(DAY, 30, CAST(GETDATE() AS DATE)), NULL),
('VIP Exclusive', '20 dollar off orders over 200', 'VIP20', 'amount', 20, DATEADD(DAY, -60, CAST(GETDATE() AS DATE)), DATEADD(DAY, 60, CAST(GETDATE() AS DATE)), 500);

-- Orders and items
DECLARE @userCount INT = (SELECT COUNT(1) FROM dbo.users);
DECLARE @i INT = 1;
WHILE @i <= 120
BEGIN
    DECLARE @userId INT = ((@i - 1) % @userCount) + 1;
    DECLARE @promoId INT = CASE WHEN @i % 4 = 0 THEN 1 WHEN @i % 7 = 0 THEN 2 ELSE NULL END;
    DECLARE @orderNumber NVARCHAR(30) = CONCAT('ECOM-', FORMAT(@i, '00000'));
    DECLARE @placed DATETIME2 = DATEADD(HOUR, -@i, SYSUTCDATETIME());

    INSERT INTO dbo.orders (user_id, order_number, order_status, payment_status, fulfillment_status, subtotal_amount, tax_amount, shipping_amount, discount_amount, promotion_id, shipping_address_id, placed_at, updated_at)
    VALUES (
        @userId,
        @orderNumber,
        CASE WHEN @i % 5 = 0 THEN 'CANCELLED' WHEN @i % 6 = 0 THEN 'RETURNED' ELSE 'COMPLETED' END,
        CASE WHEN @i % 5 = 0 THEN 'REFUNDED' ELSE 'PAID' END,
        CASE WHEN @i % 5 = 0 THEN 'NOT_FULFILLED' ELSE 'FULFILLED' END,
        0,
        0,
        15,
        0,
        @promoId,
        (SELECT TOP 1 address_id FROM dbo.addresses WHERE user_id = @userId),
        @placed,
        @placed
    );

    DECLARE @orderId BIGINT = SCOPE_IDENTITY();
    DECLARE @itemCount INT = ABS(CHECKSUM(NEWID())) % 4 + 1;
    DECLARE @item INT = 1;
    DECLARE @subTotal DECIMAL(14,2) = 0;

    WHILE @item <= @itemCount
    BEGIN
        DECLARE @productId INT = (ABS(CHECKSUM(NEWID())) % (SELECT COUNT(*) FROM dbo.products)) + 1;
        DECLARE @qty INT = ABS(CHECKSUM(NEWID())) % 3 + 1;
        DECLARE @price DECIMAL(12,2) = (SELECT price FROM dbo.products WHERE product_id = @productId);
        DECLARE @discount DECIMAL(12,2) = CASE WHEN @item % 3 = 0 THEN 5 ELSE 0 END;

        INSERT INTO dbo.order_items (order_id, product_id, quantity, list_price, discount_amount)
        VALUES (@orderId, @productId, @qty, @price, @discount);

        SET @subTotal += (@price - @discount) * @qty;
        SET @item += 1;
    END;

    UPDATE dbo.orders
    SET subtotal_amount = @subTotal,
        tax_amount = @subTotal * 0.085,
        shipping_amount = CASE WHEN @subTotal > 500 THEN 0 ELSE 15 END,
        discount_amount = CASE WHEN @promoId IS NOT NULL THEN @subTotal * 0.1 ELSE 0 END
    WHERE order_id = @orderId;

    INSERT INTO dbo.payments (order_id, payment_method, transaction_id, amount, status, processed_at)
    VALUES (@orderId, 'credit_card', CONCAT('TX-', @orderNumber), @subTotal, CASE WHEN @i % 5 = 0 THEN 'REFUNDED' ELSE 'CAPTURED' END, DATEADD(MINUTE, 5, @placed));

    INSERT INTO dbo.shipments (order_id, carrier, tracking_code, shipped_at, delivered_at, status)
    VALUES (
        @orderId,
        'FastShip',
        CONCAT('TRK', RIGHT('000000' + CAST(@orderId AS NVARCHAR(10)), 6)),
        DATEADD(HOUR, 4, @placed),
        CASE WHEN @i % 6 = 0 THEN NULL ELSE DATEADD(DAY, 3, @placed) END,
        CASE WHEN @i % 6 = 0 THEN 'IN_TRANSIT' ELSE 'DELIVERED' END
    );

    IF @i % 9 = 0
    BEGIN
        INSERT INTO dbo.return_requests (order_item_id, quantity, reason, status, requested_at)
        SELECT TOP 1 oi.order_item_id, 1, 'Damaged item', 'PENDING', DATEADD(DAY, 5, @placed)
        FROM dbo.order_items oi
        WHERE oi.order_id = @orderId
        ORDER BY oi.order_item_id;
    END;

    IF @i % 3 = 0
    BEGIN
        INSERT INTO dbo.product_reviews (product_id, user_id, rating, title, review_text, created_at)
        SELECT TOP 1 oi.product_id, @userId, ABS(CHECKSUM(NEWID())) % 5 + 1, 'Auto review', 'Great product!', DATEADD(DAY, 7, @placed)
        FROM dbo.order_items oi
        WHERE oi.order_id = @orderId
        ORDER BY oi.order_item_id;
    END;

    SET @i += 1;
END;

-- Sync reporting view into snapshot table for baseline metrics
INSERT INTO reporting.daily_metrics (metric_date, metric_name, metric_value)
SELECT CAST(o.placed_at AS DATE) AS metric_date,
       'orders.count' AS metric_name,
       COUNT(1) AS metric_value
FROM dbo.orders o
GROUP BY CAST(o.placed_at AS DATE);
GO
