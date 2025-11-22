/*
    Daily DBA script part A: environment metadata, statistics maintenance,
    and reporting snapshot refresh for ecommerce database.
*/
USE ecommerce;
GO

SET NOCOUNT ON;

DECLARE @snapshot DATETIME2 = SYSUTCDATETIME();
DECLARE @today DATE = CAST(@snapshot AS DATE);

/********************************************************************
 * 1. Capture environment metadata
 ********************************************************************/ 
SELECT DB_NAME() AS database_name,
       @snapshot AS captured_at,
       SUM(size) * 8 / 1024 AS database_size_mb
FROM sys.database_files;

/********************************************************************
 * 2. Rebuild statistics selectively for heavily modified tables
 ********************************************************************/ 
DECLARE @statsSql NVARCHAR(MAX) = N'';
SELECT @statsSql += N'UPDATE STATISTICS ' + QUOTENAME(SCHEMA_NAME(t.schema_id)) + '.' + QUOTENAME(t.name) + ';'
FROM sys.dm_db_stats_properties (NULL, NULL) sp
JOIN sys.stats s ON sp.object_id = s.object_id AND sp.stats_id = s.stats_id
JOIN sys.tables t ON s.object_id = t.object_id
WHERE sp.modification_counter > 1000;

IF (@statsSql <> N'')
BEGIN
    PRINT 'Refreshing heavily modified stats...';
    EXEC sp_executesql @statsSql;
END;

/********************************************************************
 * 3. Refresh reporting snapshot with KPIs
 ********************************************************************/ 
WITH order_facts AS (
    SELECT CAST(o.placed_at AS DATE) AS order_date,
           SUM(o.total_amount) AS gross_revenue,
           COUNT(DISTINCT o.order_id) AS orders,
           COUNT(DISTINCT CASE WHEN o.order_status = 'RETURNED' THEN o.order_id END) AS returns,
           AVG(o.total_amount) AS avg_order_value
    FROM dbo.orders o
    WHERE o.placed_at >= DATEADD(DAY, -30, @snapshot)
    GROUP BY CAST(o.placed_at AS DATE)
)
MERGE reporting.daily_metrics AS target
USING (
    SELECT order_date, 'revenue.gross' AS metric_name, CAST(gross_revenue AS DECIMAL(18,4)) AS metric_value FROM order_facts
    UNION ALL
    SELECT order_date, 'orders.count', CAST(orders AS DECIMAL(18,4)) FROM order_facts
    UNION ALL
    SELECT order_date, 'returns.count', CAST(returns AS DECIMAL(18,4)) FROM order_facts
    UNION ALL
    SELECT order_date, 'orders.aov', CAST(avg_order_value AS DECIMAL(18,4)) FROM order_facts
) AS src
ON target.metric_date = src.order_date AND target.metric_name = src.metric_name
WHEN MATCHED THEN UPDATE SET metric_value = src.metric_value, captured_at = @snapshot
WHEN NOT MATCHED THEN INSERT (metric_date, metric_name, metric_value, captured_at)
VALUES (src.order_date, src.metric_name, src.metric_value, @snapshot);
GO
