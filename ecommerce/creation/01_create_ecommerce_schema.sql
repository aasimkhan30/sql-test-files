/*
    Creates schemas, tables, constraints, and supporting objects for the
    ecommerce sample. Run after 00_create_ecommerce_database.sql while
    connected to the ecommerce database.
*/
IF SCHEMA_ID('reporting') IS NULL
    EXEC('CREATE SCHEMA reporting;');
GO

CREATE TABLE dbo.users (
    user_id            INT IDENTITY(1,1) PRIMARY KEY,
    email              NVARCHAR(255) NOT NULL UNIQUE,
    password_hash      CHAR(64) NOT NULL,
    first_name         NVARCHAR(100) NOT NULL,
    last_name          NVARCHAR(100) NOT NULL,
    phone_number       NVARCHAR(25) NULL,
    registered_at      DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    marketing_opt_in   BIT NOT NULL DEFAULT 0,
    preferred_language NVARCHAR(10) NOT NULL DEFAULT 'en',
    loyalty_points     INT NOT NULL DEFAULT 0,
    CONSTRAINT CK_users_phone_valid CHECK (phone_number IS NULL OR LEN(phone_number) >= 7)
);

CREATE TABLE dbo.addresses (
    address_id   INT IDENTITY(1,1) PRIMARY KEY,
    user_id      INT NOT NULL,
    type         NVARCHAR(20) NOT NULL,
    line1        NVARCHAR(200) NOT NULL,
    line2        NVARCHAR(200) NULL,
    city         NVARCHAR(100) NOT NULL,
    state        NVARCHAR(100) NOT NULL,
    postal_code  NVARCHAR(20) NOT NULL,
    country      NVARCHAR(100) NOT NULL DEFAULT 'USA',
    is_default   BIT NOT NULL DEFAULT 0,
    CONSTRAINT FK_addresses_users FOREIGN KEY (user_id) REFERENCES dbo.users(user_id)
);

CREATE TABLE dbo.categories (
    category_id   INT IDENTITY(100,1) PRIMARY KEY,
    parent_id     INT NULL,
    name          NVARCHAR(200) NOT NULL UNIQUE,
    description   NVARCHAR(500) NULL,
    display_order INT NOT NULL DEFAULT 1,
    CONSTRAINT FK_categories_parent FOREIGN KEY (parent_id) REFERENCES dbo.categories(category_id)
);

CREATE TABLE dbo.suppliers (
    supplier_id INT IDENTITY(1,1) PRIMARY KEY,
    name        NVARCHAR(200) NOT NULL,
    contact     NVARCHAR(200) NULL,
    email       NVARCHAR(200) NULL,
    phone       NVARCHAR(50) NULL,
    rating      DECIMAL(3,2) NOT NULL DEFAULT 5.00
);

CREATE TABLE dbo.products (
    product_id     INT IDENTITY(1,1) PRIMARY KEY,
    sku            NVARCHAR(50) NOT NULL UNIQUE,
    name           NVARCHAR(200) NOT NULL,
    description    NVARCHAR(MAX) NULL,
    category_id    INT NOT NULL,
    supplier_id    INT NULL,
    price          DECIMAL(12,2) NOT NULL,
    cost           DECIMAL(12,2) NOT NULL,
    currency       CHAR(3) NOT NULL DEFAULT 'USD',
    is_active      BIT NOT NULL DEFAULT 1,
    created_at     DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at     DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT FK_products_category FOREIGN KEY (category_id) REFERENCES dbo.categories(category_id),
    CONSTRAINT FK_products_supplier FOREIGN KEY (supplier_id) REFERENCES dbo.suppliers(supplier_id)
);

CREATE TABLE dbo.inventory (
    inventory_id   INT IDENTITY(1,1) PRIMARY KEY,
    product_id     INT NOT NULL,
    warehouse_code NVARCHAR(20) NOT NULL,
    quantity_on_hand INT NOT NULL DEFAULT 0,
    quantity_reserved INT NOT NULL DEFAULT 0,
    safety_stock   INT NOT NULL DEFAULT 0,
    reorder_point  INT NOT NULL DEFAULT 0,
    last_counted   DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT FK_inventory_product FOREIGN KEY (product_id) REFERENCES dbo.products(product_id)
);

CREATE TABLE dbo.promotions (
    promotion_id  INT IDENTITY(1,1) PRIMARY KEY,
    name          NVARCHAR(200) NOT NULL,
    description   NVARCHAR(500) NULL,
    promo_code    NVARCHAR(50) NULL UNIQUE,
    discount_type NVARCHAR(10) NOT NULL,
    discount_value DECIMAL(10,2) NOT NULL,
    start_date    DATE NOT NULL,
    end_date      DATE NOT NULL,
    max_redemptions INT NULL,
    active        BIT NOT NULL DEFAULT 1
);

CREATE TABLE dbo.orders (
    order_id          BIGINT IDENTITY(1,1) PRIMARY KEY,
    user_id           INT NOT NULL,
    order_number      NVARCHAR(30) NOT NULL UNIQUE,
    order_status      NVARCHAR(20) NOT NULL,
    payment_status    NVARCHAR(20) NOT NULL,
    fulfillment_status NVARCHAR(20) NOT NULL,
    subtotal_amount   DECIMAL(14,2) NOT NULL,
    tax_amount        DECIMAL(14,2) NOT NULL,
    shipping_amount   DECIMAL(14,2) NOT NULL,
    discount_amount   DECIMAL(14,2) NOT NULL DEFAULT 0,
    total_amount      AS (subtotal_amount + tax_amount + shipping_amount - discount_amount) PERSISTED,
    promotion_id      INT NULL,
    shipping_address_id INT NULL,
    placed_at         DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at        DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT FK_orders_user FOREIGN KEY (user_id) REFERENCES dbo.users(user_id),
    CONSTRAINT FK_orders_promo FOREIGN KEY (promotion_id) REFERENCES dbo.promotions(promotion_id),
    CONSTRAINT FK_orders_address FOREIGN KEY (shipping_address_id) REFERENCES dbo.addresses(address_id)
);

CREATE TABLE dbo.order_items (
    order_item_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    order_id      BIGINT NOT NULL,
    product_id    INT NOT NULL,
    quantity      INT NOT NULL,
    list_price    DECIMAL(12,2) NOT NULL,
    discount_amount DECIMAL(12,2) NOT NULL DEFAULT 0,
    line_total    AS ((list_price - discount_amount) * quantity) PERSISTED,
    CONSTRAINT FK_order_items_order FOREIGN KEY (order_id) REFERENCES dbo.orders(order_id),
    CONSTRAINT FK_order_items_product FOREIGN KEY (product_id) REFERENCES dbo.products(product_id)
);

CREATE TABLE dbo.payments (
    payment_id     BIGINT IDENTITY(1,1) PRIMARY KEY,
    order_id       BIGINT NOT NULL,
    payment_method NVARCHAR(50) NOT NULL,
    transaction_id NVARCHAR(100) NOT NULL,
    amount         DECIMAL(14,2) NOT NULL,
    status         NVARCHAR(20) NOT NULL,
    processed_at   DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT FK_payments_order FOREIGN KEY (order_id) REFERENCES dbo.orders(order_id)
);

CREATE TABLE dbo.shipments (
    shipment_id   BIGINT IDENTITY(1,1) PRIMARY KEY,
    order_id      BIGINT NOT NULL,
    carrier       NVARCHAR(100) NOT NULL,
    tracking_code NVARCHAR(100) NULL,
    shipped_at    DATETIME2 NULL,
    delivered_at  DATETIME2 NULL,
    status        NVARCHAR(20) NOT NULL,
    CONSTRAINT FK_shipments_order FOREIGN KEY (order_id) REFERENCES dbo.orders(order_id)
);

CREATE TABLE dbo.return_requests (
    return_id     BIGINT IDENTITY(1,1) PRIMARY KEY,
    order_item_id BIGINT NOT NULL,
    quantity      INT NOT NULL,
    reason        NVARCHAR(200) NOT NULL,
    status        NVARCHAR(20) NOT NULL,
    requested_at  DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    processed_at  DATETIME2 NULL,
    CONSTRAINT FK_return_requests_order_item FOREIGN KEY (order_item_id) REFERENCES dbo.order_items(order_item_id)
);

CREATE TABLE dbo.product_reviews (
    review_id   BIGINT IDENTITY(1,1) PRIMARY KEY,
    product_id  INT NOT NULL,
    user_id     INT NOT NULL,
    rating      INT NOT NULL,
    title       NVARCHAR(200) NULL,
    review_text NVARCHAR(MAX) NULL,
    created_at  DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT FK_reviews_product FOREIGN KEY (product_id) REFERENCES dbo.products(product_id),
    CONSTRAINT FK_reviews_user FOREIGN KEY (user_id) REFERENCES dbo.users(user_id),
    CONSTRAINT CK_reviews_rating CHECK (rating BETWEEN 1 AND 5)
);

CREATE TABLE reporting.daily_metrics (
    metric_date DATE NOT NULL,
    metric_name NVARCHAR(100) NOT NULL,
    metric_value DECIMAL(18,4) NOT NULL,
    captured_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    PRIMARY KEY (metric_date, metric_name)
);

GO

CREATE OR ALTER VIEW reporting.vw_order_item_detail AS
SELECT
    o.order_id,
    o.order_number,
    o.user_id,
    oi.order_item_id,
    oi.product_id,
    p.name AS product_name,
    oi.quantity,
    oi.line_total,
    o.total_amount,
    o.placed_at
FROM dbo.orders o
JOIN dbo.order_items oi ON oi.order_id = o.order_id
JOIN dbo.products p ON p.product_id = oi.product_id;
GO

CREATE NONCLUSTERED INDEX IX_orders_status ON dbo.orders(order_status, placed_at);
CREATE NONCLUSTERED INDEX IX_order_items_product ON dbo.order_items(product_id);
CREATE NONCLUSTERED INDEX IX_inventory_product_warehouse ON dbo.inventory(product_id, warehouse_code);
CREATE NONCLUSTERED INDEX IX_payments_processed_at ON dbo.payments(processed_at);
CREATE NONCLUSTERED INDEX IX_shipments_status ON dbo.shipments(status);
GO
