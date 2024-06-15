SELECT *
FROM sales;

SELECT *
FROM members;

SELECT *
FROM menu;

# What is the total amount each customer spent at the restaurant?
SELECT customer_id, SUM(price) AS total_amount
FROM (
	SELECT *
	FROM sales
	JOIN menu
	USING (product_id)
) AS temp
GROUP BY customer_id;

# How many days has each customer visited the restaurant?
SELECT customer_id, COUNT(DISTINCT(order_date)) AS total_days
FROM sales
GROUP BY customer_id;

# What was the first item from the menu purchased by each customer?
WITH temp AS
(
	SELECT customer_id, 
    order_date, 
    sales.product_id, 
    product_name, 
    price, 
    DENSE_RANK() OVER (PARTITION BY customer_id ORDER BY order_date) AS `rank`,
    ROW_NUMBER() OVER (PARTITION BY customer_id, order_date, product_name) AS duplicates
	FROM sales
	JOIN menu
	ON sales.product_id = menu.product_id
)
SELECT customer_id, product_name
FROM temp
WHERE `rank`=1 AND duplicates<2;

# What is the most purchased item on the menu and how many times was it purchased by all customers?
WITH temp AS
(
	SELECT *
	FROM sales
	JOIN menu
	USING (product_id)
)
SELECT product_name, COUNT(product_name) AS count
FROM temp
GROUP BY product_name
ORDER BY count DESC
LIMIT 1;

# Which item was the most popular for each customer?
WITH temp2 AS
(
	SELECT *, DENSE_RANK() OVER (PARTITION BY customer_id ORDER BY count DESC) AS ranking
	FROM (
		SELECT customer_id, product_name, COUNT(product_name) AS count
		FROM sales
		JOIN menu
		USING (product_id)
		GROUP BY customer_id, product_name
	) AS temp
)
SELECT customer_id, product_name
FROM temp2
WHERE ranking=1;

# Which item was purchased first by the customer after they became a member?
WITH cte AS
(
	SELECT sales.customer_id, order_date, product_name, DENSE_RANK() OVER (PARTITION BY sales.customer_id ORDER BY order_date) AS ranking
	FROM sales
	JOIN menu
	USING (product_id)
	JOIN members
	ON sales.customer_id=members.customer_id AND sales.order_date>=members.join_date
)
SELECT customer_id, product_name
FROM cte
WHERE ranking=1;

# Which item was purchased just before the customer became a member?
WITH cte AS
(
	SELECT customer_id, order_date, product_name, join_date, DENSE_RANK() OVER (PARTITION BY customer_id ORDER BY order_date DESC) AS ranking
	FROM sales
	JOIN menu
	USING (product_id)
	JOin members
	USING (customer_id)
	WHERE sales.order_date<members.join_date
)
SELECT customer_id, product_name
FROM cte
WHERE ranking=1;

# What is the total items and amount spent for each member before they became a member?
WITH cte AS
(
	SELECT customer_id, order_date, product_name, join_date, price, DENSE_RANK() OVER (PARTITION BY customer_id ORDER BY order_date DESC) AS ranking
	FROM sales
	JOIN menu
	USING (product_id)
	JOin members
	USING (customer_id)
	WHERE sales.order_date<members.join_date
)
SELECT customer_id, COUNT(customer_id) AS total_items, SUM(price) AS total_spend
FROM cte
GROUP BY customer_id;

# If each $1 spent equates to 10 points and sushi has a 2x points multiplier - how many points would each customer have?
WITH cte AS
(
	SELECT *, IF(product_name = 'sushi', price*20, price*10) AS points
	FROM sales
	JOIN menu
	USING (product_id)
)
SELECT customer_id, SUM(points)
FROM cte
GROUP BY customer_id;

# In the first week after a customer joins the program (including their join date) they earn 2x points on all items, not just sushi
# how many points do customer A and B have at the end of January?
WITH cte AS
(
	SELECT customer_id, order_date, product_name, price,
	CASE
		WHEN DATEDIFF(order_date, join_date)<=6 THEN price*20  # including their join date, so 6 not 7
		WHEN DATEDIFF(order_date, join_date)>6 AND product_name='sushi' THEN price*20
		WHEN DATEDIFF(order_date, join_date)>6 AND product_name!='sushi' THEN price*10
	END AS points
	FROM sales
	JOIN menu
	USING (product_id)
	JOIN members
	USING (customer_id)
	WHERE sales.order_date >= members.join_date
)
SELECT customer_id, SUM(points)
FROM cte
WHERE MONTH(order_date)=1
GROUP BY customer_id
ORDER BY customer_id;

# Join All The Things, Recreate the table with: customer_id, order_date, product_name, price, member (Y/N)
SELECT sales.customer_id, sales.order_date, menu.product_name, menu.price,
CASE
	WHEN members.join_date<=sales.order_date=0 OR members.join_date<=sales.order_date IS NULL THEN 'N'
    ELSE 'Y'
END AS members
FROM sales
LEFT JOIN menu
ON sales.product_id = menu.product_id
LEFT JOIN members
ON sales.customer_id = members.customer_id;

# Rank All The Things, 
# Danny also requires further information about the ranking of customer products, 
# but he purposely does not need the ranking for non-member purchases 
# so he expects null ranking values for the records when customers are not yet part of the loyalty program.
WITH cte AS (
	SELECT sales.customer_id, sales.order_date, menu.product_name, menu.price,
	CASE
		WHEN members.join_date<=sales.order_date=0 OR members.join_date<=sales.order_date IS NULL THEN 'N'
		ELSE 'Y'
	END AS members
	FROM sales
	LEFT JOIN menu
	ON sales.product_id = menu.product_id
	LEFT JOIN members
	ON sales.customer_id = members.customer_id
)
SELECT *, 
CASE
	WHEN members='N' THEN NULL
    ELSE DENSE_RANK() OVER (PARTITION BY customer_id, members='Y' ORDER BY product_name, order_date)
END AS ranking
FROM cte;