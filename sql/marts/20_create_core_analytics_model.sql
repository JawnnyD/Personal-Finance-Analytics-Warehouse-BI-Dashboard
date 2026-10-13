-- delete existing marts tables and dashboard views to rebuild from V2 staging data
DROP VIEW IF EXISTS marts.monthly_expense_summary;
DROP VIEW IF EXISTS marts.monthly_income_expense;
DROP VIEW IF EXISTS marts.monthly_savings_rate;
DROP VIEW IF EXISTS marts.category_spending_summary;
DROP VIEW IF EXISTS marts.budget_vs_actual;
DROP VIEW IF EXISTS marts.top_merchants;
DROP VIEW IF EXISTS marts.top_sources;
DROP VIEW IF EXISTS marts.month_over_month_category_change;
DROP VIEW IF EXISTS marts.rolling_30_day_spend;
DROP VIEW IF EXISTS marts.recurring_expense_candidates;

DROP TABLE IF EXISTS marts.fct_transactions;
DROP TABLE IF EXISTS marts.dim_account;
DROP TABLE IF EXISTS marts.dim_person;
DROP TABLE IF EXISTS marts.dim_source;
DROP TABLE IF EXISTS marts.dim_paid_by;
DROP TABLE IF EXISTS marts.dim_merchant;
DROP TABLE IF EXISTS marts.dim_date;
DROP TABLE IF EXISTS marts.dim_category;

-- create date dimension table
CREATE TABLE marts.dim_date AS
  -- finds earliest and latest valid transaction dates
  WITH date_range AS
       (
       SELECT min(transaction_date) AS min_date
            , max(transaction_date) AS max_date
         FROM staging.transactions
        WHERE transaction_date IS NOT NULL
       )
SELECT to_char(
         d.calendar_date,
         'YYYYMMDD'
       )::integer AS date_key
     , d.calendar_date::date AS full_date
     , extract(
         year
         FROM d.calendar_date
       )::integer AS calendar_year
     , extract(
         month
         FROM d.calendar_date
       )::integer AS month_number
     , to_char(
         d.calendar_date,
         'FMMonth'
       ) AS month_name
     , extract(
         quarter
         FROM d.calendar_date
       )::integer AS quarter_number
     , concat(
         'Q',
         extract(
           quarter
           FROM d.calendar_date
         )::integer
       ) AS quarter_name
     , extract(
         isoyear
         FROM d.calendar_date
       )::integer AS iso_week_year
     , extract(
         week
         FROM d.calendar_date
       )::integer AS iso_week_number
     , extract(
         isodow
         FROM d.calendar_date
       )::integer AS day_of_week_number
     , to_char(
         d.calendar_date,
         'FMDay'
       ) AS day_name

  FROM date_range AS dr
  -- generates one row for every day between first and last transaction date
 CROSS JOIN LATERAL generate_series(
       dr.min_date::timestamp,
       dr.max_date::timestamp,
       interval '1 day'
       ) AS d(calendar_date);

ALTER TABLE marts.dim_date
  ADD CONSTRAINT dim_date_pkey
      PRIMARY KEY (date_key),
  ADD CONSTRAINT dim_date_full_date_key
      UNIQUE (full_date);

-- create category and subcategory dimension table
CREATE TABLE marts.dim_category AS
  -- includes every approved pair plus any unexpected pair from staging
  WITH all_category_subcategories AS
       (
       SELECT category
            , subcategory
         FROM reference.category_subcategories

       UNION

       SELECT DISTINCT category
            , subcategory
         FROM staging.transactions
        WHERE category IS NOT NULL
          AND subcategory IS NOT NULL
       )
SELECT row_number() OVER(
         ORDER BY acs.category, acs.subcategory
       )::integer AS category_key
     , acs.category
     , acs.subcategory
     , rcs.expense_group
     , rcs.is_fixed_expense

  FROM all_category_subcategories AS acs
  -- invalid pairs remain in the dimension with NULL metadata for quality review
  LEFT JOIN reference.category_subcategories AS rcs
       ON acs.category = rcs.category
      AND acs.subcategory = rcs.subcategory;

ALTER TABLE marts.dim_category
  ADD CONSTRAINT dim_category_pkey
      PRIMARY KEY (category_key),
  ADD CONSTRAINT dim_category_category_subcategory_key
      UNIQUE (category, subcategory);

-- create source lookup table
CREATE TABLE marts.dim_source AS
  WITH distinct_sources AS
       (
       SELECT DISTINCT source_clean AS source_name
         FROM staging.transactions
        WHERE source_clean IS NOT NULL
       )
SELECT row_number() OVER(
         ORDER BY source_name
       )::integer AS source_key
     , source_name

  FROM distinct_sources;

ALTER TABLE marts.dim_source
  ADD CONSTRAINT dim_source_pkey
      PRIMARY KEY (source_key),
  ADD CONSTRAINT dim_source_name_key
      UNIQUE (source_name);

-- create person lookup table
CREATE TABLE marts.dim_person AS
  -- includes approved people plus any unexpected values from staging
  WITH all_people AS
       (
       SELECT person
         FROM reference.people

       UNION

       SELECT DISTINCT person
         FROM staging.transactions
        WHERE person IS NOT NULL
       )
SELECT row_number() OVER(
         ORDER BY person
       )::integer AS person_key
     , person

  FROM all_people;

ALTER TABLE marts.dim_person
  ADD CONSTRAINT dim_person_pkey
      PRIMARY KEY (person_key),
  ADD CONSTRAINT dim_person_name_key
      UNIQUE (person);

-- create account lookup table
CREATE TABLE marts.dim_account AS
  -- includes approved accounts plus unexpected combinations for quality review
  WITH all_accounts AS
       (
       SELECT person
            , payment_method
            , account_name
         FROM reference.person_payment_accounts

       UNION

       SELECT DISTINCT person
            , payment_method
            , account_name
         FROM staging.transactions
        WHERE person IS NOT NULL
          AND payment_method IS NOT NULL
          AND account_name IS NOT NULL
       )
SELECT row_number() OVER(
         ORDER BY person, payment_method, account_name
       )::integer AS account_key
     , person
     , payment_method
     , account_name

  FROM all_accounts;

ALTER TABLE marts.dim_account
  ADD CONSTRAINT dim_account_pkey
      PRIMARY KEY (account_key),
  ADD CONSTRAINT dim_account_person_payment_account_key
      UNIQUE (person, payment_method, account_name);

-- create main transaction fact table
CREATE TABLE marts.fct_transactions AS
SELECT st.transaction_id
     , st.source_transaction_id
     , dd.date_key
     , dc.category_key
     , ds.source_key
     , dp.person_key
     , da.account_key
     , st.amount
     , st.signed_amount
     , st.absolute_amount
     , st.transaction_type
     , st.is_income
     , st.is_expense
     , st.is_refund
     , st.payment_method
     , st.account_name
     , st.related_transaction_id
     , st.description
     , st.notes

  FROM staging.transactions AS st
  -- left joins preserve records even if quality issues exist
  LEFT JOIN marts.dim_date AS dd
       ON st.transaction_date = dd.full_date
  LEFT JOIN marts.dim_category AS dc
       ON st.category = dc.category
      AND st.subcategory = dc.subcategory
  LEFT JOIN marts.dim_source AS ds
       ON st.source_clean = ds.source_name
  LEFT JOIN marts.dim_person AS dp
       ON st.person = dp.person
  LEFT JOIN marts.dim_account AS da
       ON st.person = da.person
      AND st.payment_method = da.payment_method
      AND st.account_name = da.account_name;

ALTER TABLE marts.fct_transactions
  ADD CONSTRAINT fct_transactions_pkey
      PRIMARY KEY (transaction_id),
  ADD CONSTRAINT fct_transactions_date_fkey
      FOREIGN KEY (date_key)
      REFERENCES marts.dim_date (date_key),
  ADD CONSTRAINT fct_transactions_category_fkey
      FOREIGN KEY (category_key)
      REFERENCES marts.dim_category (category_key),
  ADD CONSTRAINT fct_transactions_source_fkey
      FOREIGN KEY (source_key)
      REFERENCES marts.dim_source (source_key),
  ADD CONSTRAINT fct_transactions_person_fkey
      FOREIGN KEY (person_key)
      REFERENCES marts.dim_person (person_key),
  ADD CONSTRAINT fct_transactions_account_fkey
      FOREIGN KEY (account_key)
      REFERENCES marts.dim_account (account_key);