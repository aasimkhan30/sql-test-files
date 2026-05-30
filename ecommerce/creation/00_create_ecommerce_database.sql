/*
    Creates or recreates the ecommerce database.
    Run this script from the master database before executing the schema scripts.
*/
-- Purpose: Creates a fresh ecommerce database for the ecommerce sample workload.
-- Tags: sqlserver, ecommerce, setup, database

IF DB_ID('ecommerce') IS NOT NULL
BEGIN
    ALTER DATABASE ecommerce SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE ecommerce;
END;
GO

CREATE DATABASE ecommerce;
GO
