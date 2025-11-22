/*
    Creates or recreates the ecommerce database.
    Run this script from the master database before executing the schema scripts.
*/
IF DB_ID('ecommerce') IS NOT NULL
BEGIN
    ALTER DATABASE ecommerce SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE ecommerce;
END;
GO

CREATE DATABASE ecommerce;
GO
