/*
    Script: daily_bulk_insert_sales_orders.sql
    Purpose: Land the daily sales CSV into staging, stamp metadata, and merge it into core tables.
    Notes:   Update @DataFile to point at the drop location for the current trading day's file.
*/
USE OpsAnalytics;
GO

DECLARE @UseDemoData     BIT            = 1;  -- Set to 0 to load from a file share
DECLARE @DemoRowCount    INT            = 500;
DECLARE @DataFile        NVARCHAR(4000) = N'\\fileserver\\incoming\\sales_orders_2024-05-01.csv';
DECLARE @SourceFileName  NVARCHAR(260);
DECLARE @LoadBatchId     UNIQUEIDENTIFIER = NEWID();

DECLARE @DemoStartDate   DATE = DATEADD(DAY, -30, CAST(GETDATE() AS DATE));

SELECT @SourceFileName = RIGHT(@DataFile, CHARINDEX('\\', REVERSE(@DataFile) + '\\') - 1);

PRINT CONCAT('Loading file ', @SourceFileName, ' into batch ', CONVERT(NVARCHAR(36), @LoadBatchId));

TRUNCATE TABLE stage.SalesOrderLanding;

IF @UseDemoData = 1
BEGIN
    DECLARE @Customers TABLE (CustomerCode NVARCHAR(25) PRIMARY KEY);
    INSERT INTO @Customers(CustomerCode)
    VALUES (N'CUST-001'), (N'CUST-002'), (N'CUST-003'), (N'CUST-004'), (N'CUST-005');

    DECLARE @Products TABLE (ProductCode NVARCHAR(25) PRIMARY KEY, DefaultPrice DECIMAL(18,4));
    INSERT INTO @Products(ProductCode, DefaultPrice)
    VALUES
        (N'PROD-001', 49.99),
        (N'PROD-002', 199.99),
        (N'PROD-003', 999.00),
        (N'PROD-004', 1500.00),
        (N'PROD-005', 2500.00);

    ;WITH tally AS
    (
        SELECT TOP (@DemoRowCount)
               ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS rn
        FROM sys.all_objects
    )
    INSERT INTO stage.SalesOrderLanding
    (
        OrderNumber,
        OrderDate,
        CustomerCode,
        ProductCode,
        Quantity,
        UnitPrice
    )
    SELECT
        CONCAT(N'SO-', FORMAT(100000 + rn, '000000')),
        DATEADD(DAY, ABS(CHECKSUM(NEWID())) % 30, @DemoStartDate),
        c.CustomerCode,
        p.ProductCode,
        ABS(CHECKSUM(NEWID())) % 25 + 1,
        p.DefaultPrice
    FROM tally
    CROSS APPLY (SELECT TOP 1 CustomerCode FROM @Customers ORDER BY NEWID()) AS c
    CROSS APPLY (SELECT TOP 1 ProductCode, DefaultPrice FROM @Products ORDER BY NEWID()) AS p;
END
ELSE
BEGIN
    DECLARE @bulkSql NVARCHAR(MAX) = N'BULK INSERT stage.SalesOrderLanding '
        + N'FROM ''' + REPLACE(@DataFile, '''', '''''') + N''' WITH '
        + N'(FIRSTROW = 2, FIELDTERMINATOR = '','', ROWTERMINATOR = ''0x0A'', TABLOCK);';

    EXEC sp_executesql @bulkSql;
END;

EXEC ops.usp_PromoteLandingSalesOrders
    @SourceFileName = @SourceFileName,
    @LoadBatchId    = @LoadBatchId;

EXEC ops.usp_MergeSalesFromStage
    @LoadBatchId = @LoadBatchId;

SELECT TOP 10 *
FROM ops.LoadAudit
WHERE LoadBatchId = @LoadBatchId;
GO
