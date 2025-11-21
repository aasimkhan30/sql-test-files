/*
    Script: daily_bulk_insert_sales_orders.sql
    Purpose: Land the daily sales CSV into staging, stamp metadata, and merge it into core tables.
    Notes:   Update @DataFile to point at the drop location for the current trading day's file.
*/
USE OpsAnalytics;
GO

DECLARE @DataFile        NVARCHAR(4000) = N'\\fileserver\\incoming\\sales_orders_2024-05-01.csv';
DECLARE @SourceFileName  NVARCHAR(260);
DECLARE @LoadBatchId     UNIQUEIDENTIFIER = NEWID();

SELECT @SourceFileName = RIGHT(@DataFile, CHARINDEX('\\', REVERSE(@DataFile) + '\\') - 1);

PRINT CONCAT('Loading file ', @SourceFileName, ' into batch ', CONVERT(NVARCHAR(36), @LoadBatchId));

TRUNCATE TABLE stage.SalesOrderLanding;

BULK INSERT stage.SalesOrderLanding
FROM @DataFile
WITH
(
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '0x0A',
    TABLOCK
);

EXEC ops.usp_PromoteLandingSalesOrders
    @SourceFileName = @SourceFileName,
    @LoadBatchId    = @LoadBatchId;

EXEC ops.usp_MergeSalesFromStage
    @LoadBatchId = @LoadBatchId;

SELECT TOP 10 *
FROM ops.LoadAudit
WHERE LoadBatchId = @LoadBatchId;
GO
