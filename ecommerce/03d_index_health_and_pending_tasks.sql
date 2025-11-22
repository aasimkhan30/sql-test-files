/*
    Daily DBA script part D: index health, IO-heavy query review, and
    outstanding operational task rollups for ecommerce database.
*/
USE ecommerce;
GO

SET NOCOUNT ON;

DECLARE @snapshot DATETIME2 = SYSUTCDATETIME();

/********************************************************************
 * 8. Index health & IO heavy queries
 ********************************************************************/ 
SELECT
    OBJECT_SCHEMA_NAME(ips.object_id) AS schema_name,
    OBJECT_NAME(ips.object_id) AS table_name,
    i.name AS index_name,
    ips.avg_fragmentation_in_percent,
    ips.page_count
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'SAMPLED') ips
JOIN sys.indexes i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
WHERE ips.avg_fragmentation_in_percent > 20 AND ips.page_count > 1000
ORDER BY ips.avg_fragmentation_in_percent DESC;

-- Top IO consumers in the last day based on query stats
SELECT TOP (20)
    DB_NAME(st.dbid) AS db_name,
    qs.execution_count,
    qs.total_logical_reads / NULLIF(qs.execution_count, 0) AS avg_logical_reads,
    qs.total_worker_time / NULLIF(qs.execution_count, 0) AS avg_cpu,
    SUBSTRING(st.text, (qs.statement_start_offset/2) + 1,
              ((CASE qs.statement_end_offset WHEN -1 THEN DATALENGTH(st.text) ELSE qs.statement_end_offset END - qs.statement_start_offset)/2) + 1) AS query_text
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
WHERE qs.last_execution_time >= DATEADD(DAY, -1, @snapshot)
ORDER BY qs.total_logical_reads DESC;

/********************************************************************
 * 9. Pending tasks summary
 ********************************************************************/ 
PRINT '===== Outstanding follow-ups =====';
SELECT 'orders_without_payment' AS issue_type, COUNT(*) AS occurrences
FROM dbo.orders o
LEFT JOIN dbo.payments p ON p.order_id = o.order_id
WHERE p.order_id IS NULL
UNION ALL
SELECT 'orders_without_shipment', COUNT(*)
FROM dbo.orders o
LEFT JOIN dbo.shipments s ON s.order_id = o.order_id
WHERE s.order_id IS NULL
UNION ALL
SELECT 'low_inventory_skus', COUNT(*)
FROM dbo.inventory
WHERE (quantity_on_hand - quantity_reserved) < safety_stock;
GO
