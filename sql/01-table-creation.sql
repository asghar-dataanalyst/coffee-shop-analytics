-- Creating tables
CREATE TABLE customers (
    CustomerID VARCHAR(100) PRIMARY KEY,
    Region VARCHAR(50),
    CustomerJoinDate DATE
);

CREATE TABLE products (
    ProductID INT PRIMARY KEY,
    ProductName VARCHAR(200),
    ProductCategory VARCHAR(100),
    Price NUMERIC(10,2),
    Base_Cost NUMERIC(10,2)
);

CREATE TABLE orders (
    OrderID VARCHAR(100) PRIMARY KEY,
    CustomerID VARCHAR(100) REFERENCES customers(CustomerID),
    ProductID INT REFERENCES products(ProductID),
    OrderDate DATE,
    Quantity INT,
    Revenue NUMERIC(10,2),
    COGS NUMERIC(10,2),
    SourceFile VARCHAR(50)
); 

-- Handle Null Values
INSERT INTO customers (CustomerID, Region, CustomerJoinDate)
VALUES ('UNKNOWN', 'Unknown', '2000-01-01');

UPDATE orders SET CustomerID = 'UNKNOWN' WHERE CustomerID IS NULL;

UPDATE orders SET Revenue = 0 WHERE Revenue IS NULL;
UPDATE orders SET COGS = 0 WHERE COGS IS NULL;

SELECT COUNT(*) FROM orders WHERE CustomerID IS NULL;
SELECT COUNT(*) FROM orders WHERE Revenue IS NULL;
SELECT COUNT(*) FROM orders WHERE COGS IS NULL;

-- 1. Total rows in orders
SELECT COUNT(*) FROM orders;

-- 2. Total rows after join (should be same if every order has a customer)
SELECT COUNT(*) 
FROM orders o
JOIN customers c ON o.CustomerID = c.CustomerID;

-- Creating the view for dataset
CREATE VIEW sales_dataset AS
SELECT 
    o.OrderID,
    o.CustomerID,
    c.Region,
    o.ProductID,
    o.OrderDate,
    c.CustomerJoinDate,
    o.Quantity,
    o.Revenue,
    o.COGS,
    p.ProductName,
    p.ProductCategory,
    p.Price,
    p.Base_Cost
FROM orders o
JOIN customers c ON o.CustomerID = c.CustomerID
JOIN products p ON o.ProductID = p.ProductID;

SELECT COUNT(*) FROM sales_dataset;   -- same as orders count
SELECT * FROM sales_dataset LIMIT 5;  -- check columns


