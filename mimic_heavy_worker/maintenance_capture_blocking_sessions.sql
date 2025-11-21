/*
    Script: maintenance_capture_blocking_sessions.sql
    Purpose: Snapshot current blocking chains so DBAs can correlate workload slowdowns.
*/
USE OpsAnalytics;
GO

EXEC ops.usp_CaptureBlockingSessions;

SELECT TOP 20 *
FROM ops.BlockingLog
ORDER BY BlockingLogId DESC;
GO
