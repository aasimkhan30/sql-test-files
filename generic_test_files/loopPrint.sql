-- Query that prints tons of messages
DECLARE @j INT = 0;
DECLARE @message NVARCHAR(100);
WHILE @j < 10000 -- Adjust this number to control how many messages are printed
BEGIN
    SET @message = 'Message ' + CAST(@j AS NVARCHAR(10)) + ': ' + CAST(NEWID() AS NVARCHAR(36));
    PRINT @message;
    SET @j = @j + 1;
END