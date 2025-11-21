/*
    Script: maintenance_rebuild_fragmented_indexes.sql
    Purpose: Identify indexes with high fragmentation in OpsAnalytics and rebuild or reorganize them.
*/
USE OpsAnalytics;
GO

DECLARE @FragmentationThresholdRebuild FLOAT = 30.0;
DECLARE @FragmentationThresholdReorg   FLOAT = 10.0;
DECLARE @sql NVARCHAR(MAX);

DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
SELECT
    QUOTENAME(s.name) + '.' + QUOTENAME(o.name) AS TableName,
    QUOTENAME(i.name) AS IndexName,
    ips.avg_fragmentation_in_percent,
    ips.page_count
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'SAMPLED') AS ips
INNER JOIN sys.indexes AS i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
INNER JOIN sys.objects AS o ON i.object_id = o.object_id AND o.is_ms_shipped = 0
INNER JOIN sys.schemas AS s ON o.schema_id = s.schema_id
WHERE ips.page_count > 100
  AND i.index_id > 0
  AND ips.avg_fragmentation_in_percent >= @FragmentationThresholdReorg
ORDER BY ips.avg_fragmentation_in_percent DESC;

OPEN cur;
DECLARE @TableName SYSNAME,
        @IndexName SYSNAME,
        @Fragment FLOAT,
        @Pages BIGINT;

FETCH NEXT FROM cur INTO @TableName, @IndexName, @Fragment, @Pages;

WHILE @@FETCH_STATUS = 0
BEGIN
    IF @Fragment >= @FragmentationThresholdRebuild
    BEGIN
        SET @sql = N'ALTER INDEX ' + @IndexName + N' ON ' + @TableName + N' REBUILD WITH (ONLINE = ON, SORT_IN_TEMPDB = ON);';
        PRINT CONCAT('Rebuilding ', @TableName, '.', @IndexName, ' (', FORMAT(@Fragment,'N2'), '%).');
    END
    ELSE
    BEGIN
        SET @sql = N'ALTER INDEX ' + @IndexName + N' ON ' + @TableName + N' REORGANIZE;';
        PRINT CONCAT('Reorganizing ', @TableName, '.', @IndexName, ' (', FORMAT(@Fragment,'N2'), '%).');
    END

    EXEC sp_executesql @sql;

    FETCH NEXT FROM cur INTO @TableName, @IndexName, @Fragment, @Pages;
END

CLOSE cur;
DEALLOCATE cur;
GO
