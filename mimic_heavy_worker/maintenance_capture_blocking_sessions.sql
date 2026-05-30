/*
    Script: maintenance_capture_blocking_sessions.sql
    Purpose: Snapshot current blocking chains so DBAs can correlate workload slowdowns.
*/
-- Purpose: Captures blocking-session maintenance diagnostics for OpsAnalytics.
-- Tags: sqlserver, opsanalytics, maintenance, blocking

USE OpsAnalytics;
GO

EXEC ops.usp_CaptureBlockingSessions;

SELECT TOP 20 *
FROM ops.BlockingLog
ORDER BY BlockingLogId DESC;
GO
