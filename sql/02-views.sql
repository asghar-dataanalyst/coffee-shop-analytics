-- ============================================================
-- COFFEE SHOP ANALYTICS PROJECT
-- 
-- FILE: 02_views.sql
-- PURPOSE: All analytical views for the Coffee Shop Analytics
--          Power BI dashboard.
--
-- USAGE: Run this script after `01_table_creation.sql`.
--        It creates 5 views that power the entire dashboard.
--
-- VIEWS INCLUDED:
--   1. v_customer_lifetime_value  → RFM Segmentation (Who are our best customers?)
--   2. v_price_optimization       → 10% Price Hike Simulation (Should we increase prices?)
--   3. v_bcg_matrix               → BCG Portfolio Strategy (Where to invest or divest?)
--   4. v_cohort_retention         → Customer Retention Analysis (Do customers come back?)
--   5. v_category_trend           → Year-over-Year Revenue Trends (Which categories are growing?)
--
-- ============================================================

-- ------------------------------------------------------------
-- VIEW 1: v_customer_lifetime_value
-- 
-- BUSINESS QUESTION: Who are our most valuable customers?
-- 
-- WHAT IT DOES:
--   Creates a complete customer profile including:
--   - Total spend, order count, average order value
--   - First and last order dates
--   - RFM Scores (Recency, Frequency, Monetary) ranked 1-4
-- 
-- HOW TO USE IN POWER BI:
--   Table: Customer details with RFM scores
--   Bar chart: Top 10 customers by total_spent
--   Scatter plot: recency_score vs monetary_score
--   Slicer: Filter by Region or RFM Scores
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW v_customer_lifetime_value AS
WITH customer_metrics AS (
    SELECT 
        c.CustomerID,
        c.Region,
        COUNT(DISTINCT o.OrderID) AS order_count,
        SUM(o.Revenue) AS total_spent,
        AVG(o.Revenue) AS avg_order_value,
        MAX(o.OrderDate) AS last_order_date,
        MIN(o.OrderDate) AS first_order_date,
        (MAX(o.OrderDate) - MIN(o.OrderDate)) AS customer_lifetime_days
    FROM customers c
    JOIN orders o ON c.CustomerID = o.CustomerID
    GROUP BY c.CustomerID, c.Region
)
SELECT 
    CustomerID,
    Region,
    order_count,
    total_spent,
    avg_order_value,
    last_order_date,
    customer_lifetime_days,
    NTILE(4) OVER (ORDER BY total_spent DESC) AS monetary_score,
    NTILE(4) OVER (ORDER BY (CURRENT_DATE - last_order_date) ASC) AS recency_score,
    NTILE(4) OVER (ORDER BY order_count DESC) AS frequency_score
FROM customer_metrics;

-- Quick test: Top 10 customers by spend
-- SELECT * FROM v_customer_lifetime_value ORDER BY total_spent DESC LIMIT 10;


-- ------------------------------------------------------------
-- VIEW 2: v_price_optimization
-- 
-- BUSINESS QUESTION: Should we increase prices? And on which products?
-- 
-- WHAT IT DOES:
--   Simulates a 10% price increase for each product using:
--   - Price elasticity (correlation between price and quantity)
--   - Projected units sold after price hike
--   - Profit change calculation
--   - Clear recommendation: "Increase Price" or "Hold Price"
-- 
-- HOW TO USE IN POWER BI:
--   Table: Product-level profit change with recommendation
--   Bar chart: Top 10 products by profit_change
--   Scatter plot: current_price vs profit_change
--   Slicer: Filter by recommendation (Increase Price / Hold Price)
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW v_price_optimization AS
WITH product_metrics AS (
    SELECT 
        p.ProductID,
        p.ProductName,
        p.ProductCategory,
        p.Price AS current_price,
        p.Base_Cost,
        SUM(o.Quantity) AS total_units_sold,
        SUM(o.Revenue) AS current_revenue,
        SUM(o.Revenue - o.COGS) AS current_profit,
        COALESCE(CORR(p.Price, o.Quantity)::numeric, -0.5) AS price_sensitivity
    FROM orders o
    JOIN products p ON o.ProductID = p.ProductID
    GROUP BY p.ProductID, p.ProductName, p.ProductCategory, p.Price, p.Base_Cost
)
SELECT 
    ProductName,
    ProductCategory,
    current_price,
    ROUND((current_price * 1.1)::numeric, 2) AS new_price,
    total_units_sold,
    ROUND((total_units_sold * (1 + price_sensitivity * 0.1))::numeric, 0) AS projected_units,
    current_profit,
    ROUND(((current_price * 1.1 - Base_Cost) * ROUND((total_units_sold * (1 + price_sensitivity * 0.1))::numeric, 0))::numeric, 2) AS projected_profit,
    ROUND(((current_price * 1.1 - Base_Cost) * ROUND((total_units_sold * (1 + price_sensitivity * 0.1))::numeric, 0))::numeric - current_profit, 2) AS profit_change,
    CASE 
        WHEN ROUND(((current_price * 1.1 - Base_Cost) * ROUND((total_units_sold * (1 + price_sensitivity * 0.1))::numeric, 0))::numeric, 2) > current_profit 
        THEN 'Increase Price' 
        ELSE 'Hold Price' 
    END AS recommendation
FROM product_metrics
ORDER BY profit_change DESC;

-- Quick test: Products with highest profit gain
-- SELECT * FROM v_price_optimization WHERE recommendation = 'Increase Price' ORDER BY profit_change DESC LIMIT 10;


-- ------------------------------------------------------------
-- VIEW 3: v_bcg_matrix
-- 
-- BUSINESS QUESTION: Which product categories are worth investing in?
-- 
-- WHAT IT DOES:
--   Builds a BCG (Growth-Share) Matrix for each product category:
--   - Current revenue (latest year)
--   - Growth rate (year-over-year)
--   - Market share (category revenue / total revenue)
--   - Strategic label: Star, Cash Cow, Question Mark, Dog
-- 
-- HOW TO USE IN POWER BI:
--   Scatter plot: X = market_share, Y = growth_rate
--   Legend = bcg_category, Size = current_revenue
--   Table: Category list with revenue, growth, share, and category
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW v_bcg_matrix AS
WITH yearly_revenue AS (
    SELECT 
        p.ProductCategory,
        EXTRACT(YEAR FROM o.OrderDate) AS year,
        SUM(o.Revenue) AS revenue
    FROM orders o
    JOIN products p ON o.ProductID = p.ProductID
    GROUP BY p.ProductCategory, year
),
growth AS (
    SELECT 
        curr.ProductCategory,
        curr.revenue AS current_revenue,
        prev.revenue AS previous_revenue,
        CASE 
            WHEN prev.revenue IS NULL OR prev.revenue = 0 THEN 0
            ELSE (curr.revenue - prev.revenue) / prev.revenue
        END AS growth_rate
    FROM yearly_revenue curr
    LEFT JOIN yearly_revenue prev 
        ON curr.ProductCategory = prev.ProductCategory 
        AND curr.year = prev.year + 1
    WHERE curr.year = (SELECT MAX(year) FROM yearly_revenue)
),
total_revenue AS (
    SELECT SUM(revenue) AS total FROM yearly_revenue WHERE year = (SELECT MAX(year) FROM yearly_revenue)
)
SELECT 
    g.ProductCategory,
    g.current_revenue,
    g.growth_rate,
    ROUND(g.current_revenue / t.total, 4) AS market_share,
    CASE 
        WHEN g.growth_rate >= 0.1 AND g.current_revenue / t.total >= 0.1 THEN 'Star'
        WHEN g.growth_rate < 0.1 AND g.current_revenue / t.total >= 0.1 THEN 'Cash Cow'
        WHEN g.growth_rate >= 0.1 AND g.current_revenue / t.total < 0.1 THEN 'Question Mark'
        ELSE 'Dog'
    END AS bcg_category
FROM growth g
CROSS JOIN total_revenue t
ORDER BY current_revenue DESC;

-- Quick test: BCG categories
-- SELECT * FROM v_bcg_matrix ORDER BY current_revenue DESC;


-- ------------------------------------------------------------
-- VIEW 4: v_cohort_retention
-- 
-- BUSINESS QUESTION: Do customers come back after their first purchase?
-- 
-- WHAT IT DOES:
--   Groups customers by their first purchase month (cohort).
--   Tracks how many return in each subsequent month.
--   Calculates retention rate for each cohort over time.
-- 
-- HOW TO USE IN POWER BI:
--   Matrix: Rows = cohort_month, Columns = months_since
--            Values = retention_rate (conditional formatting: dark green = high)
--   Line chart: Retention trend for a selected cohort
--   Tooltip: Customer count per segment
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW v_cohort_retention AS
WITH cohorts AS (
    SELECT 
        CustomerID,
        DATE_TRUNC('month', MIN(OrderDate)) AS cohort_month
    FROM orders
    GROUP BY CustomerID
),
cohort_data AS (
    SELECT 
        c.cohort_month,
        DATE_TRUNC('month', o.OrderDate) AS order_month,
        EXTRACT(MONTH FROM AGE(DATE_TRUNC('month', o.OrderDate), c.cohort_month)) AS months_since,
        COUNT(DISTINCT o.CustomerID) AS customers
    FROM cohorts c
    JOIN orders o ON c.CustomerID = o.CustomerID
    GROUP BY c.cohort_month, order_month
)
SELECT 
    cohort_month,
    order_month,
    months_since,
    customers,
    ROUND(customers * 1.0 / FIRST_VALUE(customers) OVER (PARTITION BY cohort_month ORDER BY order_month), 4) AS retention_rate
FROM cohort_data
ORDER BY cohort_month, order_month;

-- Quick test: Recent cohorts
-- SELECT * FROM v_cohort_retention WHERE cohort_month >= '2024-01-01' ORDER BY cohort_month, months_since LIMIT 20;


-- ------------------------------------------------------------
-- VIEW 5: v_category_trend
-- 
-- BUSINESS QUESTION: Which categories are growing or declining?
-- 
-- WHAT IT DOES:
--   Shows yearly revenue for each product category from 2023 to 2025.
--   Helps track category performance over time.
-- 
-- HOW TO USE IN POWER BI:
--   Line chart: X = year, Y = revenue, Legend = ProductCategory
--   Table: Annual revenue by category with data bars
--   Tooltip: Year-over-year growth percentage
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW v_category_trend AS
SELECT 
    p.ProductCategory,
    EXTRACT(YEAR FROM o.OrderDate) AS year,
    SUM(o.Revenue) AS revenue
FROM orders o
JOIN products p ON o.ProductID = p.ProductID
GROUP BY p.ProductCategory, year
ORDER BY year, revenue DESC;

-- Quick test: 2025 revenue by category
-- SELECT * FROM v_category_trend WHERE year = 2025 ORDER BY revenue DESC;


-- ============================================================
-- END OF VIEWS
-- 
-- NEXT STEPS:
-- 1. Connect Power BI to PostgreSQL
-- 2. Import these views as tables
-- 3. Build the 6-page dashboard
-- 
-- TROUBLESHOOTING:
-- If a view fails to create, check:
--   - Tables (customers, orders, products) exist in public schema
--   - Column names match (OrderID, CustomerID, ProductID, etc.)
--   - Date columns have proper data types (DATE or TIMESTAMP)
-- ============================================================