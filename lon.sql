-- Artificial delay using WAITFOR
WAITFOR DELAY '00:10:00';  -- 10 minutes

-- Optionally add a meaningless computation to simulate CPU usage
;WITH E1(N) AS (
    SELECT 1 UNION ALL SELECT 1 UNION ALL SELECT 1 UNION ALL
    SELECT 1 UNION ALL SELECT 1 UNION ALL SELECT 1 UNION ALL
    SELECT 1 UNION ALL SELECT 1 UNION ALL SELECT 1 UNION ALL SELECT 1
), -- 10
E2(N) AS (SELECT 1 FROM E1 a, E1 b),        -- 100
E4(N) AS (SELECT 1 FROM E2 a, E2 b),        -- 10,000
E8(N) AS (SELECT 1 FROM E4 a, E4 b)         -- 100,000
SELECT COUNT(*) FROM E8;


select * from [sys].[all_objects]. 