DROP TABLE IF EXISTS marts.fct_transactions;
DROP TABLE IF EXISTS marts.dim_date;
DROP TABLE IF EXISTS marts.dim_category;
DROP TABLE IF EXISTS marts.dim_merchant;

CREATE TABLE marts.dim_date AS
  WITH date_range AS 
       (
       SELECT MIN(transaction_date) AS min_date
            , MAX(transaction_date) AS max_date
         FROM staging.transactions
       )
SELECT to_char(d.calendar_date, 'YYYYMMDD')::integer AS date_key
     , d.calendar_date::date AS full_date
     , extract(year FROM d.calendar_date)::integer AS calendar_year
     , extract(month FROM d.calendar_date)::integer AS month_number
     , to_char(d.calendar_date, 'FMMonth') AS month_name
     , concat(
            'Q',
            extract(quarter FROM d.calendar_date)::integer
       ) AS quarter_name
     , extract(isoyear FROM d.calendar_date)::integer AS iso_week_year
     , extract(week FROM d.calendar_date)::integer AS iso_week_number
  FROM date_range AS dr
 CROSS JOIN LATERAL generate_series(
       dr.min_date::timestamp,
       dr.max_date::timestamp,
       interval '1 day'
       ) AS d(calendar_date);

 ALTER TABLE marts.dim_date
       ADD CONSTRAINT dim_date_pkey PRIMARY KEY (date_key),
       ADD CONSTRAINT dim_date_full_date_key UNIQUE (full_date);

CREATE TABLE marts.dim_category AS
  WITH category_mapping (category, expense_group, is_fixed_expense) AS
       (
       VALUES ('Entertainment', 'Wants', FALSE)
            , ('Gas', 'Needs', FALSE)
            , ('Groceries', 'Needs', FALSE)
            , ('Other', 'Unclassified', NULL)
            , ('Pets', 'Needs', FALSE)
            , ('Rent', 'Needs', TRUE)
            , ('Restaurants', 'Wants', FALSE)
       ),
       distinct_categories AS
       (
       SELECT DISTINCT category
         FROM staging.transactions
        WHERE category IS NOT NULL
       )
SELECT (row_number() OVER (ORDER BY dc.category))::integer AS category_key
     , dc.category
     , NULL::text AS subcategory
     , cm.expense_group
     , cm.is_fixed_expense
  FROM distinct_categories AS dc
  LEFT JOIN category_mapping AS cm
       ON dc.category = cm.category;

 ALTER TABLE marts.dim_category
       ADD CONSTRAINT dim_category_pkey PRIMARY KEY (category_key),
       ADD CONSTRAINT dim_category_category_key UNIQUE (category);

CREATE TABLE marts.dim_merchant AS
  WITH distinct_merchants AS
       (
       SELECT DISTINCT merchant_clean
         FROM staging.transactions
        WHERE merchant_clean IS NOT NULL
       )
SELECT (row_number() OVER (ORDER BY merchant_clean))::integer AS merchant_key
     , merchant_clean AS merchant_name
  FROM distinct_merchants;

 ALTER TABLE marts.dim_merchant
       ADD CONSTRAINT dim_merchant_pkey PRIMARY KEY (merchant_key),
       ADD CONSTRAINT dim_merchant_name_key UNIQUE (merchant_name);

CREATE TABLE marts.fct_transactions AS
SELECT st.transaction_id
     , dd.date_key
     , dc.category_key
     , dm.merchant_key
     , st.amount
     , st.signed_amount
     , st.absolute_amount
     , st.transaction_type
     , st.is_income
     , st.is_expense
     , st.paid_by
     , st.payment_method
  FROM staging.transactions AS st
  JOIN marts.dim_date AS dd
       ON st.transaction_date = dd.full_date
  JOIN marts.dim_category AS dc
       ON st.category = dc.category
  JOIN marts.dim_merchant AS dm
       ON st.merchant_clean = dm.merchant_name;

 ALTER TABLE marts.fct_transactions
       ADD CONSTRAINT fct_transactions_pkey PRIMARY KEY (transaction_id),
       ADD CONSTRAINT fct_transactions_date_fkey
           FOREIGN KEY (date_key)
           REFERENCES marts.dim_date (date_key),
       ADD CONSTRAINT fct_transactions_category_fkey
           FOREIGN KEY (category_key)
           REFERENCES marts.dim_category (category_key),
       ADD CONSTRAINT fct_transactions_merchant_fkey
           FOREIGN KEY (merchant_key)
           REFERENCES marts.dim_merchant (merchant_key);