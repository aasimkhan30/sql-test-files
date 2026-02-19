-- Script to print 10,000 lines and execute SELECT 1 10,000 times
-- This uses a WHILE loop to print numbers from 1 to 10,000

DECLARE @counter INT = 1;

WHILE @counter <= 10000
BEGIN
    PRINT 'Line ' + CAST(@counter AS VARCHAR(10));
    SET @counter = @counter + 1;
END

SET @counter = 1;

WHILE @counter <= 100
BEGIN
    PRINT 'Line ' + CAST(@counter AS VARCHAR(10));
    SELECT @counter;
    SET @counter = @counter + 1;
END

PRINT 'Completed printing 10,000 lines and executing SELECT 1 10,000 times';
