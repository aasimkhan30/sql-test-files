/*
    Script: report_sales_trend_vs_prior_year.sql
    Purpose: Compare current-year revenue vs prior-year by month and highlight deltas.
*/
USE OpsAnalytics;
GO

DECLARE @MonthsBack INT = 12;
DECLARE @AsOf DATE = CAST(GETDATE() AS DATE);

WITH month_fact AS
(
    SELECT
        DATEFROMPARTS(YEAR(OrderDate), MONTH(OrderDate), 1) AS MonthStart,
        SUM(TotalAmount) AS Revenue
    FROM dbo.SalesOrderFact
    WHERE OrderDate >= DATEADD(MONTH, -@MonthsBack, DATEADD(YEAR, -1, DATEFROMPARTS(YEAR(@AsOf), MONTH(@AsOf), 1)))
    GROUP BY DATEFROMPARTS(YEAR(OrderDate), MONTH(OrderDate), 1)
),
cur AS
(
    SELECT MonthStart, Revenue
    FROM month_fact
    WHERE MonthStart >= DATEADD(MONTH, -@MonthsBack, DATEFROMPARTS(YEAR(@AsOf), MONTH(@AsOf), 1))
),
prior AS
(
    SELECT DATEADD(YEAR, 1, MonthStart) AS MonthStart, Revenue AS RevenuePriorYear
    FROM month_fact
    WHERE MonthStart < DATEADD(MONTH, -@MonthsBack, DATEFROMPARTS(YEAR(@AsOf), MONTH(@AsOf), 1))
)
SELECT
    cur.MonthStart,
    cur.Revenue AS RevenueCurrent,
    prior.RevenuePriorYear,
    cur.Revenue - prior.RevenuePriorYear AS Delta,
    CASE WHEN prior.RevenuePriorYear = 0 OR prior.RevenuePriorYear IS NULL THEN NULL
         ELSE (cur.Revenue - prior.RevenuePriorYear) / prior.RevenuePriorYear END AS DeltaPct
FROM cur
LEFT JOIN prior ON prior.MonthStart = cur.MonthStart
ORDER BY cur.MonthStart;
GO
