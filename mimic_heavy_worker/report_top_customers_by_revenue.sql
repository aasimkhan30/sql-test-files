/*
    Script: report_top_customers_by_revenue.sql
    Purpose: Surface the top customers by trailing revenue with contribution metrics and retention flags.
*/
USE OpsAnalytics;
GO

DECLARE @TrailingMonths INT = 3;
DECLARE @AsOfDate DATE = CAST(GETDATE() AS DATE);

WITH sales AS
(
    SELECT
        f.CustomerID,
        c.CustomerCode,
        c.CustomerName,
        SUM(f.TotalAmount) AS Revenue,
        SUM(f.Quantity) AS UnitsSold,
        COUNT(DISTINCT f.SalesOrderNumber) AS OrderCount
    FROM dbo.SalesOrderFact AS f
    INNER JOIN ref.Customer AS c ON c.CustomerID = f.CustomerID
    WHERE f.OrderDate >= DATEADD(MONTH, -@TrailingMonths, DATEFROMPARTS(YEAR(@AsOfDate), MONTH(@AsOfDate), 1))
    GROUP BY f.CustomerID, c.CustomerCode, c.CustomerName
),
pct AS
(
    SELECT
        *,
        SUM(Revenue) OVER () AS TotalRevenue,
        ROW_NUMBER() OVER (ORDER BY Revenue DESC) AS rn,
        SUM(Revenue) OVER (ORDER BY Revenue DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS RunningRevenue
    FROM sales
)
SELECT
    CustomerCode,
    CustomerName,
    Revenue,
    UnitsSold,
    OrderCount,
    Revenue / NULLIF(TotalRevenue,0) AS RevenuePct,
    RunningRevenue / NULLIF(TotalRevenue,0) AS CumulativeRevenuePct,
    CASE WHEN EXISTS (
            SELECT 1
            FROM dbo.SalesOrderFact AS fPrev
            WHERE fPrev.CustomerID = pct.CustomerID
              AND fPrev.OrderDate BETWEEN DATEADD(MONTH, -2*@TrailingMonths, DATEFROMPARTS(YEAR(@AsOfDate), MONTH(@AsOfDate), 1))
                                  AND DATEADD(MONTH, -@TrailingMonths, @AsOfDate)
        ) THEN 1 ELSE 0 END AS RetainedFromPriorWindow,
    rn
FROM pct
ORDER BY Revenue DESC;
GO
