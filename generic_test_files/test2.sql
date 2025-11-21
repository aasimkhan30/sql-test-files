-- SQL Query that returns XML data
-- This query demonstrates various XML generation techniques in SQL Server

-- 1. Basic XML generation with FOR XML AUTO
SELECT TOP 10 
    ID,
    Name,
    Email,
    Department,
    Salary
FROM EmployeeData
FOR XML AUTO;

-- 2. XML with custom element names using FOR XML PATH
SELECT TOP 5
    ID as "Employee/@EmployeeID",
    Name as "Employee/FullName",
    Email as "Employee/EmailAddress", 
    Department as "Employee/Department",
    Salary as "Employee/Salary"
FOR XML PATH(''), ROOT('Employees');

-- 3. XML with nested structure and attributes
SELECT 
    Department as "@DepartmentName",
    COUNT(*) as "@TotalEmployees",
    AVG(Salary) as "@AverageSalary",
    (
        SELECT TOP 3
            Name as "@Name",
            Email as "@Email",
            Salary as "@Salary"
        FROM EmployeeData e2 
        WHERE e2.Department = e1.Department
        ORDER BY Salary DESC
        FOR XML PATH('Employee'), TYPE
    ) as "TopEmployees"
FROM EmployeeData e1
GROUP BY Department
FOR XML PATH('Department'), ROOT('CompanyData');

-- 4. Complex XML with multiple levels and CDATA
SELECT 
    'Company Employee Report' as "Report/@Title",
    GETDATE() as "Report/@GeneratedDate",
    (
        SELECT 
            Department as "@Name",
            COUNT(*) as "@Count",
            (
                SELECT 
                    ID as "@ID",
                    Name as "PersonalInfo/@FullName",
                    Email as "PersonalInfo/@Email",
                    Salary as "EmploymentInfo/@Salary",
                    CASE 
                        WHEN Salary >= 100000 THEN 'Senior'
                        WHEN Salary >= 70000 THEN 'Mid-Level'
                        ELSE 'Junior'
                    END as "EmploymentInfo/@Level"
                FROM EmployeeData emp
                WHERE emp.Department = dept.Department
                AND emp.ID <= 10  -- Limit for demo purposes
                FOR XML PATH('Employee'), TYPE
            )
        FROM (SELECT DISTINCT Department FROM EmployeeData) dept
        FOR XML PATH('Department'), TYPE
    )
FOR XML PATH(''), ROOT('EnterpriseReport');

-- 5. XML with text content and mixed elements
SELECT TOP 5
    ID as "@EmployeeID",
    CONCAT('Employee: ', Name, ' works in ', Department) as "Description",
    Name as "Contact/Name",
    Email as "Contact/Email",
    Department as "Position/Department",
    CONCAT('$', FORMAT(Salary, 'N2')) as "Position/Salary"
FOR XML PATH('Employee'), ROOT('EmployeeDirectory');

-- 6. XML using XMLELEMENT (alternative approach)
SELECT 
    (
        SELECT 
            ID,
            Name,
            Email,
            Department,
            Salary
        FROM EmployeeData
        WHERE Department = 'IT'
        AND ID <= 5
        FOR XML RAW('ITEmployee'), ELEMENTS
    ) as XMLData;
