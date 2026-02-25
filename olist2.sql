SELECT * FROM customers LIMIT 10;
SELECT * FROM sellers LIMIT 10;
SELECT * FROM products LIMIT 10;

SELECT * FROM orders LIMIT 10;
SELECT * FROM order_items LIMIT 10;
SELECT * FROM order_payments LIMIT 10;
SELECT * FROM order_reviews LIMIT 10;

SELECT * FROM geolocation LIMIT 10;
--------------------
SELECT * FROM view_logistics_performance LIMIT 10;
SELECT * FROM view_products_master LIMIT 10;
SELECT * FROM view_geo_clean LIMIT 10;
SELECT * FROM view_shipping_map LIMIT 10;
SELECT * FROM view_customer_feedback LIMIT 10;
---------------------
CREATE OR REPLACE VIEW view_logistics_performance AS
SELECT 
    o.ord_id,
    o.cust_id,
    oi.sell_id, -- Added so you can rank sellers by speed
    o.status,
    o.purchased_at,
    o.delivered_at,
    o.estim_date,
    c.state AS cust_state,
    s.state AS sell_state,
    -- 1. Total Lead Time (Days)
    (o.delivered_at::date - o.purchased_at::date) AS total_lead_time,
    -- 2. Seller Processing Time (Warehouse Speed)
    (o.carrier_date::date - o.purchased_at::date) AS warehouse_time,
    -- 3. Carrier Shipping Time (Last Mile Speed)
    (o.delivered_at::date - o.carrier_date::date) AS shipping_time,
    -- 4. SLA Difference (Positive = Early, Negative = Late)
    (o.estim_date::date - o.delivered_at::date) AS sla_diff,
    CASE 
        WHEN o.delivered_at > o.estim_date THEN 'Late'
        ELSE 'On-Time'
    END AS delivery_status
FROM orders o
JOIN customers c ON o.cust_id = c.cust_id
JOIN order_items oi ON o.ord_id = oi.ord_id
JOIN sellers s ON oi.sell_id = s.sell_id
WHERE o.status = 'delivered' 
  AND o.delivered_at IS NOT NULL 
  AND o.carrier_date IS NOT NULL;

-- First, clean the geo data (average coords per zip)
CREATE OR REPLACE VIEW view_geo_clean AS
SELECT 
	zip, 
	AVG(lat) as lat, 
	AVG(lng) as lng
FROM geolocation
GROUP BY zip;

-- Create the master distance view
CREATE OR REPLACE VIEW view_shipping_map AS
SELECT 
    oi.ord_id,
    s.state AS sell_state,
    c.state AS cust_state,
    sg.lat AS sell_lat, sg.lng AS sell_lng,
    cg.lat AS cust_lat, cg.lng AS cust_lng,
    oi.freight_value,
    oi.price
FROM order_items oi
JOIN sellers s ON oi.sell_id = s.sell_id
JOIN orders o ON oi.ord_id = o.ord_id
JOIN customers c ON o.cust_id = c.cust_id
LEFT JOIN view_geo_clean sg ON s.zip = sg.zip
LEFT JOIN view_geo_clean cg ON c.zip = cg.zip;


CREATE OR REPLACE VIEW view_customer_feedback AS
SELECT 
    ord_id,
    score,
    (answered_at::date - created_at::date) AS response_time_days
FROM order_reviews;
---------------------
SELECT 
    l.ord_id, 
    l.delivery_status, 
    p.category, 
    f.score u
FROM view_logistics_performance l
JOIN view_products_master p ON l.ord_id = p.prod_id
JOIN view_customer_feedback f ON l.ord_id = f.ord_id;

SELECT COUNT(*) FROM view_logistics_performance;
SELECT COUNT(*) FROM view_products_master;
SELECT COUNT(*) FROM view_customer_feedback;

SELECT l.ord_id, f.score
FROM view_logistics_performance l
LEFT JOIN view_customer_feedback f ON l.ord_id = f.ord_id
LIMIT 10;

CREATE OR REPLACE VIEW view_products_master AS
SELECT 
    oi.ord_id, -- ADDED THIS LINE
    p.prod_id,
    COALESCE(t.cat_name_en, p.cat_name, 'other') AS category,
    p.weight_g,
    ROUND((p.len_cm * p.width_cm * p.height_cm) / 6000.0, 2) AS vol_weight_kg,
    p.photos_qty
FROM products p
JOIN order_items oi ON p.prod_id = oi.prod_id -- JOINED TO ORDER_ITEMS
LEFT JOIN prod_cat_trans t ON p.cat_name = t.cat_name;

SELECT 
    l.ord_id, 
    l.delivery_status, 
    p.category, 
    f.score 
FROM view_logistics_performance l
JOIN view_products_master p ON l.ord_id = p.ord_id
JOIN view_customer_feedback f ON l.ord_id = f.ord_id
LIMIT 10;
