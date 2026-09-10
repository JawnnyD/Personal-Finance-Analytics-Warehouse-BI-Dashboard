-- summarizes expenses by month
CREATE OR REPLACE VIEW marts.monthly_expense_summary AS
SELECT date_trunc('month', dd.full_date)::date AS transaction_month
     , dd.calendar_year
     , dd.month_number
     , dd.month_name
     , COUNT(ft.transaction_id) AS transaction_count
     , SUM(ft.absolute_amount) AS total_expense
     , AVG(ft.absolute_amount) AS average_transaction_amount
  FROM marts.fct_transactions AS ft
  JOIN marts.dim_date AS dd
       ON ft.date_key = dd.date_key
 WHERE ft.is_expense
 -- group all transactions into monthly buckets
 GROUP BY date_trunc('month', dd.full_date)::date, dd.calendar_year, dd.month_number, dd.month_name;

-- summarizes expenses by category
CREATE OR REPLACE VIEW marts.category_spending_summary AS
  -- cte to build all spending totals by category
  WITH category_totals AS
       (
       SELECT dc.category
            , dc.expense_group
            , dc.is_fixed_expense
            , COUNT(ft.transaction_id) AS transaction_count
            , SUM(ft.absolute_amount) AS total_expense
            , AVG(ft.absolute_amount) AS average_transaction_amount
         FROM marts.fct_transactions AS ft
         JOIN marts.dim_category AS dc
              ON ft.category_key = dc.category_key
        WHERE ft.is_expense
        GROUP BY dc.category, dc.expense_group, dc.is_fixed_expense
       )
SELECT category
     , expense_group
     , is_fixed_expense
     , transaction_count
     , total_expense
     , average_transaction_amount
       -- each category's share of total spending
     , total_expense / NULLIF(SUM(total_expense) OVER (), 0) AS expense_share
  FROM category_totals;

-- summarizes merchant spending ranking
CREATE OR REPLACE VIEW marts.top_merchants AS
  -- ctw for total spnding by merchant
  WITH merchant_totals AS
       (
       SELECT dm.merchant_name
            , COUNT(ft.transaction_id) AS transaction_count
            , SUM(ft.absolute_amount) AS total_expense
            , AVG(ft.absolute_amount) AS average_transaction_amount
         FROM marts.fct_transactions AS ft
         JOIN marts.dim_merchant AS dm
              ON ft.merchant_key = dm.merchant_key
        WHERE ft.is_expense
        GROUP BY dm.merchant_name
       )
       -- ranks merchants by most spending
SELECT dense_rank() OVER(ORDER BY total_expense DESC, merchant_name) AS merchant_spend_rank
     , merchant_name
     , transaction_count
     , total_expense
     , average_transaction_amount
  FROM merchant_totals;

-- compare each category's spending month versus previous month
CREATE OR REPLACE VIEW marts.month_over_month_category_change AS
  -- build list of months from date dim
  WITH months AS
       (
       SELECT DISTINCT date_trunc('month', full_date)::date AS transaction_month
         FROM marts.dim_date
       ),
       -- create every combination of month and category (hence cross join)
       category_month_grid AS
       (
       SELECT m.transaction_month
            , dc.category_key
            , dc.category
            , dc.expense_group
         FROM months AS m
        CROSS JOIN marts.dim_category AS dc
       ),
       -- actual spnding by month and category
       monthly_category_spend AS
       (
       SELECT date_trunc('month', dd.full_date)::date AS transaction_month
            , ft.category_key
            , SUM(ft.absolute_amount) AS current_month_spend
         FROM marts.fct_transactions AS ft
         JOIN marts.dim_date AS dd
              ON ft.date_key = dd.date_key
        WHERE ft.is_expense
        GROUP BY date_trunc('month', dd.full_date)::date, ft.category_key
       ),
       -- joins full month grid with actual spending (left join keep every month/category pair)
       spend_with_prior AS
       (
       SELECT g.transaction_month
            , g.category
            , g.expense_group
            , COALESCE(s.current_month_spend, 0) AS current_month_spend
              -- find previous month spending by category
            , LAG(COALESCE(s.current_month_spend, 0)) OVER(PARTITION BY g.category_key ORDER BY g.transaction_month) AS prior_month_spend
         FROM category_month_grid AS g
         LEFT JOIN monthly_category_spend AS s
              ON g.transaction_month = s.transaction_month
              AND g.category_key = s.category_key
       )
SELECT transaction_month
     , category
     , expense_group
     , current_month_spend
     , prior_month_spend
     , current_month_spend - prior_month_spend AS month_over_month_change
     , CASE
       WHEN prior_month_spend IS NULL OR prior_month_spend = 0 THEN NULL
       ELSE (current_month_spend - prior_month_spend) / prior_month_spend
       END AS month_over_month_change_pct
  FROM spend_with_prior;

-- rolling 30-day expense view
CREATE OR REPLACE VIEW marts.rolling_30_day_spend AS
  -- produces a row per day
  WITH daily_spend AS
       (
       SELECT dd.full_date
            , COALESCE(SUM(ft.absolute_amount), 0) AS daily_expense
         FROM marts.dim_date AS dd
         LEFT JOIN marts.fct_transactions AS ft
              ON dd.date_key = ft.date_key
              AND ft.is_expense
        GROUP BY dd.full_date
       )
SELECT full_date
     , daily_expense
       -- rolling window calculation
     , SUM(daily_expense) OVER(ORDER BY full_date ROWS BETWEEN 29 PRECEDING AND CURRENT ROW) AS rolling_30_day_expense
  FROM daily_spend;

-- find recurring expense merchants
CREATE OR REPLACE VIEW marts.recurring_expense_candidates AS
SELECT dm.merchant_name
     , COUNT(ft.transaction_id) AS transaction_count
     , COUNT(DISTINCT date_trunc('month', dd.full_date)::date) AS active_month_count
     , MIN(dd.full_date) AS first_transaction_date
     , MAX(dd.full_date) AS last_transaction_date
     , SUM(ft.absolute_amount) AS total_expense
     , AVG(ft.absolute_amount) AS average_transaction_amount
       -- hard-coded flag for recurring candidate, is it needed? idk
     , TRUE AS is_recurring_candidate
  FROM marts.fct_transactions AS ft
  JOIN marts.dim_date AS dd
       ON ft.date_key = dd.date_key
  JOIN marts.dim_merchant AS dm
       ON ft.merchant_key = dm.merchant_key
 WHERE ft.is_expense
 GROUP BY dm.merchant_name
HAVING COUNT(DISTINCT date_trunc('month', dd.full_date)::date) >= 2;