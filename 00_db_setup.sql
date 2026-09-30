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

/*===================================================================
Tables & Load script (plain BULK INSERT, no stored procedure/ETL layers
by design — this project is SQL/EDA-focused, not pipeline-focused).

ID formats:
  campaign_id   CAMP001
  customer_id   CUS00001
  product_id    PROD001
  store_id      STR01
  order_id      ORD000001
  session_id    SES0000001
  touchpoint_id TP0000001
  return_id     RET000001
=====================================================================*/

CREATE SCHEMA source;
GO

CREATE TABLE source.campaigns (
    campaign_id   VARCHAR(50) PRIMARY KEY,
    campaign_name VARCHAR(50),
    channel       VARCHAR(50),
    campaign_type VARCHAR(50),
    objective     VARCHAR(50),
    start_date    DATE,
    end_date      DATE,
    budget        INT
);

CREATE TABLE source.customers (
    customer_id             VARCHAR(50) PRIMARY KEY,
    signup_date             DATE,
    gender                  VARCHAR(50),
    age_group               VARCHAR(50),
    city                    VARCHAR(50),
    state                   VARCHAR(50),
    acquisition_date        DATE,
    acquisition_channel     VARCHAR(50),
    acquisition_campaign_id VARCHAR(50)
        REFERENCES source.campaigns(campaign_id)
);

CREATE TABLE source.products (
    product_id   VARCHAR(50) PRIMARY KEY,
    product_name VARCHAR(50),
    category     VARCHAR(50),
    subcategory  VARCHAR(50),
    brand        VARCHAR(50),
    price        DECIMAL(8, 2),
    cost         DECIMAL(8, 2)
);

CREATE TABLE source.stores (
    store_id     VARCHAR(50) PRIMARY KEY,
    store_name   VARCHAR(50),
    city         VARCHAR(50),
    state        VARCHAR(50),
    store_type   VARCHAR(50),
    opening_date DATE
);

CREATE TABLE source.marketing_spend (
    date        DATE,
    campaign_id VARCHAR(50) REFERENCES source.campaigns(campaign_id),
    spend       INT,
    impressions INT,
    clicks      INT,
    PRIMARY KEY (date, campaign_id)
);

CREATE TABLE source.marketing_touchpoints (
    touchpoint_id    VARCHAR(50) PRIMARY KEY,
    customer_id      VARCHAR(50) REFERENCES source.customers(customer_id),
    campaign_id      VARCHAR(50) REFERENCES source.campaigns(campaign_id),
    timestamp        DATETIME,
    channel          VARCHAR(50),
    interaction_type VARCHAR(50),
    device           VARCHAR(50)
);

CREATE TABLE source.sessions (
    session_id           VARCHAR(50) PRIMARY KEY,
    customer_id          VARCHAR(50) REFERENCES source.customers(customer_id),
    session_start        DATETIME,
    device                VARCHAR(50),
    source                VARCHAR(50),
    campaign_id           VARCHAR(50) REFERENCES source.campaigns(campaign_id),
    landing_page          VARCHAR(50),
    session_duration_sec  INT,
    pages_viewed          INT
);

CREATE TABLE source.orders (
    order_id        VARCHAR(50) PRIMARY KEY,
    customer_id     VARCHAR(50) REFERENCES source.customers(customer_id),
    order_date      DATE,
    sales_channel   VARCHAR(50),
    store_id        VARCHAR(50) REFERENCES source.stores(store_id),
    payment_method  VARCHAR(50),
    order_status    VARCHAR(50),
    gross_amount    DECIMAL(8, 2),
    discount_amount DECIMAL(8, 2),
    shipping_amount DECIMAL(8, 2),
    net_amount      DECIMAL(8, 2)
);

CREATE TABLE source.order_items (
    order_id        VARCHAR(50) REFERENCES source.orders(order_id),
    product_id      VARCHAR(50) REFERENCES source.products(product_id),
    quantity        INT,
    unit_price      DECIMAL(8, 2),
    discount_amount DECIMAL(8, 2),
    PRIMARY KEY (order_id, product_id)
);

CREATE TABLE source.returns (
    return_id       VARCHAR(50) PRIMARY KEY,
    order_id        VARCHAR(50),
    product_id      VARCHAR(50),
    return_date     DATE,
    return_quantity INT,
    return_reason   VARCHAR(50),
    refund_amount   DECIMAL(8, 2),
    FOREIGN KEY (order_id, product_id) REFERENCES source.order_items(order_id, product_id)
);
GO

BULK INSERT source.campaigns FROM 'C:\RetailX Dataset\campaigns.csv'
    WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', TABLOCK);

BULK INSERT source.products FROM 'C:\RetailX Dataset\products.csv'
    WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', TABLOCK);

BULK INSERT source.stores FROM 'C:\RetailX Dataset\stores.csv'
    WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', TABLOCK);

BULK INSERT source.customers FROM 'C:\RetailX Dataset\customers.csv'
    WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', TABLOCK);

BULK INSERT source.marketing_spend FROM 'C:\RetailX Dataset\marketing_spend.csv'
    WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', TABLOCK);

BULK INSERT source.marketing_touchpoints FROM 'C:\RetailX Dataset\marketing_touchpoints.csv'
    WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', TABLOCK);

BULK INSERT source.sessions FROM 'C:\RetailX Dataset\sessions.csv'
    WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', TABLOCK);

BULK INSERT source.orders FROM 'C:\RetailX Dataset\orders.csv'
    WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', TABLOCK);

BULK INSERT source.order_items FROM 'C:\RetailX Dataset\order_items.csv'
    WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', TABLOCK);

BULK INSERT source.returns FROM 'C:\RetailX Dataset\returns.csv'
    WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', TABLOCK);


