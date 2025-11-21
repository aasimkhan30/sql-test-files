/*
    Script: report_monthly_sales_kpis.sql
    Purpose: Provide a quick KPI snapshot by month, region, and product category.
*/
USE OpsAnalytics;
GO

WITH sales AS
(
    SELECT
        DATEFROMPARTS(YEAR(OrderDate), MONTH(OrderDate), 1) AS MonthStart,
        c.Region,
        p.Category,
        COUNT(*) AS OrderCount,
        SUM(f.Quantity) AS UnitsSold,
        SUM(f.TotalAmount) AS Revenue,
        SUM(f.TotalAmount) / NULLIF(SUM(f.Quantity),0) AS AvgPrice
    FROM dbo.SalesOrderFact AS f
    INNER JOIN ref.Customer AS c ON c.CustomerID = f.CustomerID
    INNER JOIN ref.Product  AS p ON p.ProductID = f.ProductID
    GROUP BY DATEFROMPARTS(YEAR(OrderDate), MONTH(OrderDate), 1), c.Region, p.Category
)
SELECT
    MonthStart,
    Region,
    Category,
    OrderCount,
    UnitsSold,
    Revenue,
    AvgPrice,
    LAG(Revenue) OVER (PARTITION BY Region, Category ORDER BY MonthStart) AS RevenuePrevMonth,
    CASE WHEN LAG(Revenue) OVER (PARTITION BY Region, Category ORDER BY MonthStart) IS NULL THEN NULL
         ELSE (Revenue - LAG(Revenue) OVER (PARTITION BY Region, Category ORDER BY MonthStart))
                 / NULLIF(LAG(Revenue) OVER (PARTITION BY Region, Category ORDER BY MonthStart), 0)
    END AS RevenueGrowthPct
FROM sales
ORDER BY MonthStart DESC, Region, Category;
GO
