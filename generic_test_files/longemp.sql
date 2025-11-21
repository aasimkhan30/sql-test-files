SELECT top 500  [ID]  
      ,[Name]
      ,[Email]
      ,[Department]
      ,[Salary]
      , [NAME] as [NAME2]
      , [Email] as [Email2]
      , [Department] as [Department2]
      , [Salary] as [Salary2]
      
  FROM [TestData_1M].[dbo].[EmployeeData]

SELECT top 500  [ID]
      ,[Name]
      ,[Email]
      ,[Department]
      ,[Salary]
  FROM [TestData_1M].[dbo].[EmployeeData]

SELECT top 500  [ID]
      ,[Name]
      ,[Email]
      ,[Department]
      ,[Salary]
  FROM [TestData_1M].[dbo].[EmployeeData]

-- Print lol 1000 times
DECLARE @i INT = 0
WHILE @i < 1000
BEGIN
    PRINT 'lol'
    SET @i = @i + 1
END