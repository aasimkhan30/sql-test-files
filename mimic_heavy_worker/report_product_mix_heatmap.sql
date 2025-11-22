/*
    Script: report_product_mix_heatmap.sql
    Purpose: Pivot product category share by region/month to feed heatmap visuals.
*/
USE OpsAnalytics;
GO

DECLARE @WindowStart DATE = DATEADD(MONTH, -5, DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1));

WITH base AS
(
    SELECT
        DATEFROMPARTS(YEAR(f.OrderDate), MONTH(f.OrderDate), 1) AS MonthStart,
        c.Region,
        p.Category,
        SUM(f.TotalAmount) AS Revenue
    FROM dbo.SalesOrderFact AS f
    INNER JOIN ref.Customer AS c ON c.CustomerID = f.CustomerID
    INNER JOIN ref.Product  AS p ON p.ProductID = f.ProductID
    WHERE f.OrderDate >= @WindowStart
    GROUP BY DATEFROMPARTS(YEAR(f.OrderDate), MONTH(f.OrderDate), 1), c.Region, p.Category
),
pct AS
(
    SELECT
        MonthStart,
        Region,
        Category,
        Revenue,
        SUM(Revenue) OVER (PARTITION BY MonthStart, Region) AS RegionRevenue
    FROM base
)
SELECT
    MonthStart,
    Region,
    Category,
    Revenue,
    RegionRevenue,
    Revenue / NULLIF(RegionRevenue,0) AS RevenueShare
FROM pct
ORDER BY MonthStart DESC, Region, RevenueShare DESC;
GO
