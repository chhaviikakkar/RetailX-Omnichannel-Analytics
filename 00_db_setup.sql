/*=====================================================================
RetailX — Omnichannel Analytics
An end-to-end SQL analysis identifying which marketing channels, product
categories, and customer segments actually drive profit for a simulated 
retail business — backed by a documented data quality audit and real 
analytical trade-off decisions.

Project scope: This project does not aggressively focus on data
cleaning or transformation (no ETL layers, no bronze/silver/gold
architecture). Data quality issues are identified, quantified, and
documented (see data_quality_log.md) rather than corrected upstream.
The aim is to answer business questions, analyze the data as-is, and
surface actionable insights and recommendations — an EDA-first project,
not a data engineering one.
=======================================================================*/

-- Switch to the system master database so we can create a new database.

USE master;
GO
  
-- Create a dedicated database for this project, isolated from any other databases on the server.
  
CREATE DATABASE retailx_db;
GO

-- Switch into the newly created database — every object created after this point (schemas, tables) will belong to retailx_db.

USE retailx_db;
GO

-- Create a "source" schema to hold all raw, as-loaded tables.
-- Using a named schema (rather than the default "dbo") keeps raw data clearly separated.

CREATE SCHEMA source;
GO
