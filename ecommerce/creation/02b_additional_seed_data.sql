/*
    Supplements initial seed with additional customers, catalog entries,
    warehouses, and higher order volumes to stress reporting scripts.
*/
USE ecommerce;
GO

SET NOCOUNT ON;

/********************************************************************
 * Additional Users & Addresses
 ********************************************************************/ 
INSERT INTO dbo.users (email, password_hash, first_name, last_name, phone_number, marketing_opt_in, preferred_language, loyalty_points)
VALUES
('frida@example.com', REPLICATE('f', 64), 'Frida', 'Nolan', '+15555550006', 1, 'en', 650),
('gavin@example.com', REPLICATE('g', 64), 'Gavin', 'Obrien', '+15555550007', 1, 'en', 1220),
('hana@example.com', REPLICATE('h', 64), 'Hana', 'Perez', '+15555550008', 0, 'jp', 75),
('ivan@example.com', REPLICATE('i', 64), 'Ivan', 'Quinn', '+15555550009', 1, 'en', 980),
('jules@example.com', REPLICATE('j', 64), 'Jules', 'Reid', '+15555550010', 1, 'fr', 1450),
('karla@example.com', REPLICATE('k', 64), 'Karla', 'Stone', '+15555550011', 0, 'en', 315),
('liam@example.com', REPLICATE('l', 64), 'Liam', 'Trent', '+15555550012', 1, 'es', 1770),
('mia@example.com', REPLICATE('m', 64), 'Mia', 'Upton', '+15555550013', 0, 'en', 40),
('noah@example.com', REPLICATE('n', 64), 'Noah', 'Vega', '+15555550014', 1, 'en', 2010),
('olivia@example.com', REPLICATE('o', 64), 'Olivia', 'Watt', '+15555550015', 1, 'en', 950);

INSERT INTO dbo.addresses (user_id, type, line1, city, state, postal_code, country, is_default)
SELECT user_id,
       CASE WHEN user_id % 2 = 0 THEN 'billing' ELSE 'shipping' END,
       CONCAT('22', RIGHT('000' + CAST(user_id AS NVARCHAR(3)), 3), ' Commerce Ave'),
       'Capital City',
       'NY',
       CONCAT('10', RIGHT('00' + CAST((user_id % 50) AS NVARCHAR(2)), 2)),
       'USA',
       1
FROM dbo.users u
WHERE email IN ('frida@example.com','gavin@example.com','hana@example.com','ivan@example.com','jules@example.com','karla@example.com','liam@example.com','mia@example.com','noah@example.com','olivia@example.com');

/********************************************************************
 * Categories, Suppliers, Products
 ********************************************************************/ 
INSERT INTO dbo.categories (parent_id, name, description, display_order)
VALUES
(NULL, 'Apparel', 'Clothing and accessories', 6),
(105, 'Outdoor Gear', 'Camping and hiking essentials', 7);

INSERT INTO dbo.suppliers (name, contact, email, phone, rating)
VALUES
('Evergreen Apparel', 'Rose Sterling', 'contact@evergreen.test', '+15555550103', 4.6),
('Summit Outfitters', 'Kai Ridge', 'support@summit.test', '+15555550104', 4.5);

INSERT INTO dbo.products (sku, name, description, category_id, supplier_id, price, cost, currency, is_active)
VALUES
('APP-001', 'Performance Hoodie', 'Moisture wicking hoodie', 105, 4, 79.00, 35.00, 'USD', 1),
('APP-002', 'Trail Running Shoes', 'Lightweight trail runners', 105, 5, 139.00, 70.00, 'USD', 1),
('APP-003', 'Waterproof Jacket', '3-layer breathable shell', 105, 4, 199.00, 90.00, 'USD', 1),
('APP-004', 'Compression Tights', 'High stretch performance tights', 105, 4, 89.00, 40.00, 'USD', 1),
('OUT-001', 'Carbon Trekking Poles', 'Folding poles with cork grip', 106, 5, 159.00, 75.00, 'USD', 1),
('OUT-002', 'Ultralight Tent', 'Freestanding 2-person tent', 106, 5, 429.00, 210.00, 'USD', 1),
('OUT-003', '800-fill Sleeping Bag', 'Extreme weather mummy bag', 106, 5, 499.00, 250.00, 'USD', 1);

/********************************************************************
 * Warehouse inventory expansion
 ********************************************************************/ 
INSERT INTO dbo.inventory (product_id, warehouse_code, quantity_on_hand, quantity_reserved, safety_stock, reorder_point)
SELECT p.product_id,
       wh.warehouse_code,
       ABS(CHECKSUM(NEWID())) % 600 + 50,
       ABS(CHECKSUM(NEWID())) % 120,
       40,
       80
FROM dbo.products p
JOIN (VALUES ('WHS-SOUTH'), ('WHS-NORTH')) AS wh(warehouse_code) ON 1=1
WHERE p.sku LIKE 'APP-%' OR p.sku LIKE 'OUT-%';

/********************************************************************
 * Additional promotions
 ********************************************************************/ 
INSERT INTO dbo.promotions (name, description, promo_code, discount_type, discount_value, start_date, end_date, max_redemptions)
VALUES
('Gear Fest', '15% off outdoor category', 'GEAR15', 'percent', 15, DATEADD(DAY, -10, CAST(GETDATE() AS DATE)), DATEADD(DAY, 40, CAST(GETDATE() AS DATE)), 1000),
('Clearance Blast', 'Flat 50 off clearance items', 'CLEAR50', 'amount', 50, DATEADD(DAY, -5, CAST(GETDATE() AS DATE)), DATEADD(DAY, 5, CAST(GETDATE() AS DATE)), 200);

/********************************************************************
 * Additional orders and engagement
 ********************************************************************/ 
DECLARE @existingOrders INT = (SELECT COUNT(*) FROM dbo.orders);
DECLARE @newStart INT = @existingOrders + 1;
DECLARE @target INT = @existingOrders + 240;
DECLARE @i INT = @newStart;

WHILE @i <= @target
BEGIN
    DECLARE @userId INT = ((@i - 1) % (SELECT COUNT(*) FROM dbo.users)) + 1;
    DECLARE @promoId INT = CASE WHEN @i % 5 = 0 THEN 3 WHEN @i % 7 = 0 THEN 4 WHEN @i % 9 = 0 THEN 2 ELSE NULL END;
    DECLARE @orderNumber NVARCHAR(30) = CONCAT('ECX-', FORMAT(@i, '00000'));
    DECLARE @placed DATETIME2 = DATEADD(HOUR, -@i, SYSUTCDATETIME());

    INSERT INTO dbo.orders (user_id, order_number, order_status, payment_status, fulfillment_status, subtotal_amount, tax_amount, shipping_amount, discount_amount, promotion_id, shipping_address_id, placed_at, updated_at)
    VALUES (
        @userId,
        @orderNumber,
        CASE WHEN @i % 11 = 0 THEN 'RETURNED' WHEN @i % 13 = 0 THEN 'CANCELLED' ELSE 'COMPLETED' END,
        CASE WHEN @i % 13 = 0 THEN 'REFUNDED' ELSE 'PAID' END,
        CASE WHEN @i % 13 = 0 THEN 'NOT_FULFILLED' ELSE 'FULFILLED' END,
        0,
        0,
        20,
        0,
        @promoId,
        (SELECT TOP 1 address_id FROM dbo.addresses WHERE user_id = @userId),
        @placed,
        @placed
    );

    DECLARE @orderId BIGINT = SCOPE_IDENTITY();
    DECLARE @itemCount INT = ABS(CHECKSUM(NEWID())) % 5 + 1;
    DECLARE @item INT = 1;
    DECLARE @subTotal DECIMAL(14,2) = 0;

    WHILE @item <= @itemCount
    BEGIN
        DECLARE @productId INT = (ABS(CHECKSUM(NEWID())) % (SELECT COUNT(*) FROM dbo.products)) + 1;
        DECLARE @qty INT = ABS(CHECKSUM(NEWID())) % 4 + 1;
        DECLARE @price DECIMAL(12,2) = (SELECT price FROM dbo.products WHERE product_id = @productId);
        DECLARE @discount DECIMAL(12,2) = CASE WHEN @item % 4 = 0 THEN 10 ELSE 0 END;

        INSERT INTO dbo.order_items (order_id, product_id, quantity, list_price, discount_amount)
        VALUES (@orderId, @productId, @qty, @price, @discount);

        SET @subTotal += (@price - @discount) * @qty;
        SET @item += 1;
    END;

    UPDATE dbo.orders
    SET subtotal_amount = @subTotal,
        tax_amount = @subTotal * 0.09,
        shipping_amount = CASE WHEN @subTotal > 400 THEN 0 ELSE 20 END,
        discount_amount = CASE WHEN @promoId IS NOT NULL THEN CASE WHEN @promoId IN (4) THEN 50 ELSE @subTotal * 0.15 END ELSE 0 END
    WHERE order_id = @orderId;

    INSERT INTO dbo.payments (order_id, payment_method, transaction_id, amount, status, processed_at)
    VALUES (@orderId, 'credit_card', CONCAT('TXE-', @orderNumber), @subTotal, CASE WHEN @i % 13 = 0 THEN 'REFUNDED' ELSE 'CAPTURED' END, DATEADD(MINUTE, 7, @placed));

    INSERT INTO dbo.shipments (order_id, carrier, tracking_code, shipped_at, delivered_at, status)
    VALUES (
        @orderId,
        CASE WHEN @i % 4 = 0 THEN 'NationalExpress' ELSE 'FastShip' END,
        CONCAT('XTRK', RIGHT('000000' + CAST(@orderId AS NVARCHAR(10)), 6)),
        DATEADD(HOUR, 6, @placed),
        CASE WHEN @i % 11 = 0 THEN DATEADD(DAY, 6, @placed) WHEN @i % 13 = 0 THEN NULL ELSE DATEADD(DAY, 2, @placed) END,
        CASE WHEN @i % 13 = 0 THEN 'PENDING' WHEN @i % 11 = 0 THEN 'DELIVERED' ELSE 'DELIVERED' END
    );

    IF @i % 8 = 0
    BEGIN
        INSERT INTO dbo.return_requests (order_item_id, quantity, reason, status, requested_at)
        SELECT TOP 1 oi.order_item_id, 1, 'Sizing issue', CASE WHEN @i % 16 = 0 THEN 'APPROVED' ELSE 'PENDING' END, DATEADD(DAY, 4, @placed)
        FROM dbo.order_items oi
        WHERE oi.order_id = @orderId
        ORDER BY oi.order_item_id;
    END;

    IF @i % 5 = 0
    BEGIN
        INSERT INTO dbo.product_reviews (product_id, user_id, rating, title, review_text, created_at)
        SELECT TOP 1 oi.product_id, @userId, ABS(CHECKSUM(NEWID())) % 5 + 1, 'User feedback', 'Automated review entry', DATEADD(DAY, 10, @placed)
        FROM dbo.order_items oi
        WHERE oi.order_id = @orderId
        ORDER BY oi.order_item_id;
    END;

    SET @i += 1;
END;
GO
