/*
    Script: initialize_opsanalytics_db.sql
    Purpose: Provision the OpsAnalytics database with schemas, tables, supporting objects, and base data
             that the heavy worker SQL scripts depend on.
*/
SET NOCOUNT ON;

------------------------------------------------------------
-- Drop and recreate the OpsAnalytics database
------------------------------------------------------------
IF DB_ID(N'OpsAnalytics') IS NOT NULL
BEGIN
    ALTER DATABASE OpsAnalytics SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE OpsAnalytics;
END;
GO
CREATE DATABASE OpsAnalytics;
GO
ALTER DATABASE OpsAnalytics SET RECOVERY SIMPLE;
GO

USE OpsAnalytics;
GO

------------------------------------------------------------
-- Schemas
------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'ref')
    EXEC('CREATE SCHEMA ref AUTHORIZATION dbo;');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'stage')
    EXEC('CREATE SCHEMA stage AUTHORIZATION dbo;');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'ops')
    EXEC('CREATE SCHEMA ops AUTHORIZATION dbo;');
GO

------------------------------------------------------------
-- Reference tables
------------------------------------------------------------
CREATE TABLE ref.Customer
(
    CustomerID         INT            IDENTITY(1,1) PRIMARY KEY,
    CustomerCode       NVARCHAR(25)   NOT NULL,
    CustomerName       NVARCHAR(120)  NOT NULL,
    Region             NVARCHAR(60)   NULL,
    Industry           NVARCHAR(80)   NULL,
    IsActive           BIT            NOT NULL DEFAULT (1),
    CreatedAt          DATETIME2(3)   NOT NULL DEFAULT (SYSUTCDATETIME()),
    UpdatedAt          DATETIME2(3)   NULL
);
GO
CREATE UNIQUE INDEX UX_Customer_Code ON ref.Customer(CustomerCode);
GO

CREATE TABLE ref.Product
(
    ProductID          INT            IDENTITY(1,1) PRIMARY KEY,
    ProductCode        NVARCHAR(25)   NOT NULL,
    ProductName        NVARCHAR(150)  NOT NULL,
    Category           NVARCHAR(80)   NULL,
    UnitPrice          DECIMAL(18,4)  NOT NULL,
    IsActive           BIT            NOT NULL DEFAULT (1),
    CreatedAt          DATETIME2(3)   NOT NULL DEFAULT (SYSUTCDATETIME()),
    UpdatedAt          DATETIME2(3)   NULL
);
GO
CREATE UNIQUE INDEX UX_Product_Code ON ref.Product(ProductCode);
GO

------------------------------------------------------------
-- Staging / landing tables
------------------------------------------------------------
CREATE TABLE stage.SalesOrderLanding
(
    LandingID          BIGINT         IDENTITY(1,1) PRIMARY KEY,
    OrderNumber        NVARCHAR(30)   NOT NULL,
    OrderDate          DATETIME2(0)   NOT NULL,
    CustomerCode       NVARCHAR(25)   NOT NULL,
    ProductCode        NVARCHAR(25)   NOT NULL,
    Quantity           INT            NOT NULL,
    UnitPrice          DECIMAL(18,4)  NULL
);
GO

CREATE TABLE stage.SalesOrderStaging
(
    StageSalesOrderID  BIGINT         IDENTITY(1,1) PRIMARY KEY,
    SourceFileName     NVARCHAR(260)  NOT NULL,
    LoadBatchId        UNIQUEIDENTIFIER NOT NULL,
    OrderNumber        NVARCHAR(30)   NOT NULL,
    OrderDate          DATETIME2(0)   NOT NULL,
    CustomerCode       NVARCHAR(25)   NOT NULL,
    ProductCode        NVARCHAR(25)   NOT NULL,
    Quantity           INT            NOT NULL,
    UnitPrice          DECIMAL(18,4)  NULL,
    LoadedAtUtc        DATETIME2(3)   NOT NULL DEFAULT (SYSUTCDATETIME()),
    ProcessedFlag      BIT            NOT NULL DEFAULT (0),
    ProcessedAtUtc     DATETIME2(3)   NULL
);
GO
CREATE INDEX IX_SalesOrderStaging_LoadBatch ON stage.SalesOrderStaging(LoadBatchId) INCLUDE(OrderNumber, CustomerCode, ProductCode);
GO

------------------------------------------------------------
-- Core fact table
------------------------------------------------------------
CREATE TABLE dbo.SalesOrderFact
(
    FactSalesOrderID   BIGINT         IDENTITY(1,1) PRIMARY KEY,
    SalesOrderNumber   NVARCHAR(30)   NOT NULL,
    OrderDate          DATE           NOT NULL,
    CustomerID         INT            NOT NULL,
    ProductID          INT            NOT NULL,
    Quantity           INT            NOT NULL,
    UnitPrice          DECIMAL(18,4)  NOT NULL,
    TotalAmount        AS (Quantity * UnitPrice) PERSISTED,
    CreatedAtUtc       DATETIME2(3)   NOT NULL DEFAULT (SYSUTCDATETIME()),
    UpdatedAtUtc       DATETIME2(3)   NULL
);
GO
ALTER TABLE dbo.SalesOrderFact
    ADD CONSTRAINT FK_SalesOrderFact_Customer FOREIGN KEY(CustomerID) REFERENCES ref.Customer(CustomerID);
ALTER TABLE dbo.SalesOrderFact
    ADD CONSTRAINT FK_SalesOrderFact_Product FOREIGN KEY(ProductID) REFERENCES ref.Product(ProductID);
GO
CREATE UNIQUE INDEX UX_SalesOrderFact_OrderNumber ON dbo.SalesOrderFact(SalesOrderNumber);
CREATE INDEX IX_SalesOrderFact_OrderDate ON dbo.SalesOrderFact(OrderDate);
GO

------------------------------------------------------------
-- Operational helper tables
------------------------------------------------------------
CREATE TABLE ops.LoadAudit
(
    LoadAuditId        INT IDENTITY(1,1) PRIMARY KEY,
    LoadBatchId        UNIQUEIDENTIFIER NOT NULL,
    ProcedureName      SYSNAME         NOT NULL,
    RowsInserted       INT             NOT NULL DEFAULT (0),
    RowsUpdated        INT             NOT NULL DEFAULT (0),
    LoadStartedAtUtc   DATETIME2(3)    NOT NULL,
    LoadCompletedAtUtc DATETIME2(3)    NOT NULL,
    Status             NVARCHAR(25)    NOT NULL,
    Message            NVARCHAR(4000)  NULL
);
GO
CREATE INDEX IX_LoadAudit_LoadBatch ON ops.LoadAudit(LoadBatchId);
GO

CREATE TABLE ops.BlockingLog
(
    BlockingLogId      BIGINT IDENTITY(1,1) PRIMARY KEY,
    CapturedAtUtc      DATETIME2(3)   NOT NULL DEFAULT (SYSUTCDATETIME()),
    SessionId          INT            NOT NULL,
    BlockingSessionId  INT            NULL,
    WaitType           NVARCHAR(120)  NULL,
    WaitResource       NVARCHAR(256)  NULL,
    WaitDurationMs     BIGINT         NULL,
    StatementText      NVARCHAR(MAX)  NULL,
    HostName           NVARCHAR(128)  NULL,
    LoginName          NVARCHAR(128)  NULL
);
GO
CREATE INDEX IX_BlockingLog_CapturedSession ON ops.BlockingLog(CapturedAtUtc, SessionId);
GO

------------------------------------------------------------
-- Views
------------------------------------------------------------
CREATE VIEW dbo.vw_DailySalesKpi
AS
SELECT
    OrderDate,
    COUNT(*) AS OrderCount,
    SUM(Quantity) AS UnitsSold,
    SUM(TotalAmount) AS Revenue
FROM dbo.SalesOrderFact
GROUP BY OrderDate;
GO

------------------------------------------------------------
-- Stored procedures
------------------------------------------------------------
GO
CREATE OR ALTER PROCEDURE ops.usp_PromoteLandingSalesOrders
    @SourceFileName NVARCHAR(260),
    @LoadBatchId    UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @LoadBatchId IS NULL
        SET @LoadBatchId = NEWID();

    INSERT INTO stage.SalesOrderStaging
    (
        SourceFileName,
        LoadBatchId,
        OrderNumber,
        OrderDate,
        CustomerCode,
        ProductCode,
        Quantity,
        UnitPrice
    )
    SELECT
        @SourceFileName,
        @LoadBatchId,
        l.OrderNumber,
        l.OrderDate,
        l.CustomerCode,
        l.ProductCode,
        l.Quantity,
        l.UnitPrice
    FROM stage.SalesOrderLanding AS l;

    TRUNCATE TABLE stage.SalesOrderLanding;

    SELECT @LoadBatchId AS LoadBatchId, @@ROWCOUNT AS RowsPromoted;
END;
GO

GO
CREATE OR ALTER PROCEDURE ops.usp_MergeSalesFromStage
    @LoadBatchId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @started DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @rowsInserted INT = 0, @rowsUpdated INT = 0;

    DECLARE @mergeOutput TABLE
    (
        ActionName NVARCHAR(10),
        SalesOrderNumber NVARCHAR(30)
    );

    MERGE dbo.SalesOrderFact AS tgt
    USING
    (
        SELECT
            s.OrderNumber,
            CAST(s.OrderDate AS DATE) AS OrderDate,
            c.CustomerID,
            p.ProductID,
            s.Quantity,
            ISNULL(s.UnitPrice, p.UnitPrice) AS UnitPrice
        FROM stage.SalesOrderStaging AS s
        INNER JOIN ref.Customer AS c ON c.CustomerCode = s.CustomerCode AND c.IsActive = 1
        INNER JOIN ref.Product  AS p ON p.ProductCode = s.ProductCode AND p.IsActive = 1
        WHERE s.LoadBatchId = @LoadBatchId
    ) AS src
    ON tgt.SalesOrderNumber = src.OrderNumber
    WHEN MATCHED AND (tgt.Quantity <> src.Quantity OR tgt.UnitPrice <> src.UnitPrice OR tgt.ProductID <> src.ProductID)
        THEN UPDATE SET
            tgt.OrderDate = src.OrderDate,
            tgt.CustomerID = src.CustomerID,
            tgt.ProductID = src.ProductID,
            tgt.Quantity = src.Quantity,
            tgt.UnitPrice = src.UnitPrice,
            tgt.UpdatedAtUtc = SYSUTCDATETIME()
    WHEN NOT MATCHED BY TARGET
        THEN INSERT
        (
            SalesOrderNumber,
            OrderDate,
            CustomerID,
            ProductID,
            Quantity,
            UnitPrice
        )
        VALUES
        (
            src.OrderNumber,
            src.OrderDate,
            src.CustomerID,
            src.ProductID,
            src.Quantity,
            src.UnitPrice
        )
    OUTPUT $action, inserted.SalesOrderNumber INTO @mergeOutput;

    SELECT
        @rowsInserted = SUM(CASE WHEN ActionName = 'INSERT' THEN 1 ELSE 0 END),
        @rowsUpdated  = SUM(CASE WHEN ActionName = 'UPDATE' THEN 1 ELSE 0 END)
    FROM @mergeOutput;

    UPDATE stage.SalesOrderStaging
        SET ProcessedFlag = 1,
            ProcessedAtUtc = SYSUTCDATETIME()
    WHERE LoadBatchId = @LoadBatchId;

    INSERT INTO ops.LoadAudit
    (
        LoadBatchId,
        ProcedureName,
        RowsInserted,
        RowsUpdated,
        LoadStartedAtUtc,
        LoadCompletedAtUtc,
        Status,
        Message
    )
    VALUES
    (
        @LoadBatchId,
        N'ops.usp_MergeSalesFromStage',
        ISNULL(@rowsInserted,0),
        ISNULL(@rowsUpdated,0),
        @started,
        SYSUTCDATETIME(),
        N'Completed',
        CONCAT(N'Rows inserted: ', ISNULL(@rowsInserted,0), N', rows updated: ', ISNULL(@rowsUpdated,0))
    );
END;
GO

GO
CREATE OR ALTER PROCEDURE ops.usp_CaptureBlockingSessions
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO ops.BlockingLog
    (
        CapturedAtUtc,
        SessionId,
        BlockingSessionId,
        WaitType,
        WaitResource,
        WaitDurationMs,
        StatementText,
        HostName,
        LoginName
    )
    SELECT
        SYSUTCDATETIME(),
        wt.session_id,
        wt.blocking_session_id,
        wt.wait_type,
        wt.resource_description,
        wt.wait_duration_ms,
        SUBSTRING(t.text, (r.statement_start_offset/2)+1, ((CASE r.statement_end_offset WHEN -1 THEN DATALENGTH(t.text) ELSE r.statement_end_offset END - r.statement_start_offset)/2) + 1) AS statement_text,
        s.host_name,
        s.login_name
    FROM sys.dm_os_waiting_tasks AS wt
    INNER JOIN sys.dm_exec_sessions AS s ON s.session_id = wt.session_id
    INNER JOIN sys.dm_exec_requests AS r ON r.session_id = wt.session_id
    CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) AS t
    WHERE wt.blocking_session_id IS NOT NULL;
END;
GO

------------------------------------------------------------
-- Seed reference data
------------------------------------------------------------
INSERT INTO ref.Customer (CustomerCode, CustomerName, Region, Industry)
VALUES
    (N'CUST-001', N'Acme Retail', N'North America', N'Retail'),
    (N'CUST-002', N'Contoso Manufacturing', N'Europe', N'Manufacturing'),
    (N'CUST-003', N'Globex Services', N'APAC', N'Services');

INSERT INTO ref.Product (ProductCode, ProductName, Category, UnitPrice)
VALUES
    (N'PROD-001', N'Standard Widget', N'Widgets', 49.99),
    (N'PROD-002', N'Industrial Widget', N'Widgets', 199.99),
    (N'PROD-003', N'Support Subscription', N'Services', 999.00);
GO

PRINT 'OpsAnalytics database is ready.';
