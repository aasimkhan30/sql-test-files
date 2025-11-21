/*
    Script: daily_refresh_reference_data.sql
    Purpose: Refresh customer and product reference data from an upstream system snapshot.
*/
USE OpsAnalytics;
GO

DECLARE @CustomerSnapshot TABLE
(
    CustomerCode NVARCHAR(25) PRIMARY KEY,
    CustomerName NVARCHAR(120),
    Region       NVARCHAR(60),
    Industry     NVARCHAR(80),
    IsActive     BIT
);

INSERT INTO @CustomerSnapshot(CustomerCode, CustomerName, Region, Industry, IsActive)
VALUES
    (N'CUST-001', N'Acme Retail', N'North America', N'Retail', 1),
    (N'CUST-004', N'Initech', N'North America', N'Technology', 1),
    (N'CUST-005', N'Vector Corp', N'EMEA', N'Logistics', 1);

MERGE ref.Customer AS tgt
USING @CustomerSnapshot AS src
    ON tgt.CustomerCode = src.CustomerCode
WHEN MATCHED THEN
    UPDATE SET
        tgt.CustomerName = src.CustomerName,
        tgt.Region       = src.Region,
        tgt.Industry     = src.Industry,
        tgt.IsActive     = src.IsActive,
        tgt.UpdatedAt    = SYSUTCDATETIME()
WHEN NOT MATCHED BY TARGET THEN
    INSERT (CustomerCode, CustomerName, Region, Industry, IsActive)
    VALUES (src.CustomerCode, src.CustomerName, src.Region, src.Industry, src.IsActive)
WHEN NOT MATCHED BY SOURCE AND tgt.IsActive = 1 THEN
    UPDATE SET IsActive = 0, UpdatedAt = SYSUTCDATETIME();

PRINT 'Customer reference synchronized';

DECLARE @ProductSnapshot TABLE
(
    ProductCode NVARCHAR(25) PRIMARY KEY,
    ProductName NVARCHAR(150),
    Category    NVARCHAR(80),
    UnitPrice   DECIMAL(18,4),
    IsActive    BIT
);

INSERT INTO @ProductSnapshot(ProductCode, ProductName, Category, UnitPrice, IsActive)
VALUES
    (N'PROD-001', N'Standard Widget', N'Widgets', 49.99, 1),
    (N'PROD-004', N'On-site Consulting', N'Services', 1500.00, 1),
    (N'PROD-005', N'Premium Support', N'Services', 2500.00, 1);

MERGE ref.Product AS tgt
USING @ProductSnapshot AS src
    ON tgt.ProductCode = src.ProductCode
WHEN MATCHED
    AND (tgt.ProductName <> src.ProductName OR tgt.UnitPrice <> src.UnitPrice OR tgt.Category <> src.Category OR tgt.IsActive <> src.IsActive)
    THEN UPDATE SET
        tgt.ProductName = src.ProductName,
        tgt.Category    = src.Category,
        tgt.UnitPrice   = src.UnitPrice,
        tgt.IsActive    = src.IsActive,
        tgt.UpdatedAt   = SYSUTCDATETIME()
WHEN NOT MATCHED BY TARGET THEN
    INSERT (ProductCode, ProductName, Category, UnitPrice, IsActive)
    VALUES (src.ProductCode, src.ProductName, src.Category, src.UnitPrice, src.IsActive)
WHEN NOT MATCHED BY SOURCE AND tgt.IsActive = 1 THEN
    UPDATE SET IsActive = 0, UpdatedAt = SYSUTCDATETIME();

PRINT 'Product reference synchronized';
GO
