-- monthly income, expense, refund, and net cash flow summary
CREATE OR REPLACE VIEW marts.monthly_income_expense AS
SELECT date_trunc(
         'month',
         dd.full_date
       )::date AS transaction_month
     , dd.calendar_year
     , dd.month_number
     , dd.month_name
     , count(ft.transaction_id)
         FILTER (
           WHERE ft.is_income
         ) AS income_transaction_count
     , coalesce(
         sum(ft.absolute_amount)
           FILTER (
             WHERE ft.is_income
           ),
         0
       ) AS total_income
     , count(ft.transaction_id)
         FILTER (
           WHERE ft.is_expense
         ) AS expense_transaction_count
     , coalesce(
         sum(ft.absolute_amount)
           FILTER (
             WHERE ft.is_expense
           ),
         0
       ) AS gross_expense
     , count(ft.transaction_id)
         FILTER (
           WHERE ft.is_refund
         ) AS refund_transaction_count
     , coalesce(
         sum(ft.absolute_amount)
           FILTER (
             WHERE ft.is_refund
           ),
         0
       ) AS total_refund
       -- refunds reduce the total amount spent
     , coalesce(
         sum(ft.absolute_amount)
           FILTER (
             WHERE ft.is_expense
           ),
         0
       )
       -
       coalesce(
         sum(ft.absolute_amount)
           FILTER (
             WHERE ft.is_refund
           ),
         0
       ) AS net_expense
       -- income and refunds are positive; expenses are negative
     , coalesce(
         sum(ft.signed_amount),
         0
       ) AS net_cash_flow

  FROM marts.dim_date AS dd
  -- left join keeps months with no activity visible for reporting
  LEFT JOIN marts.fct_transactions AS ft
       ON dd.date_key = ft.date_key
 GROUP BY date_trunc(
            'month',
            dd.full_date
          )::date
        , dd.calendar_year
        , dd.month_number
        , dd.month_name;

-- monthly savings summary and savings rate
CREATE OR REPLACE VIEW marts.monthly_savings_rate AS
SELECT transaction_month
     , calendar_year
     , month_number
     , month_name
     , total_income
     , gross_expense
     , total_refund
     , net_expense
     , total_income - net_expense AS net_savings
     , CASE
         WHEN total_income = 0 THEN NULL
         ELSE (
           total_income - net_expense
         ) / total_income
       END AS savings_rate

  FROM marts.monthly_income_expense;

-- spending by category and subcategory after refunds
CREATE OR REPLACE VIEW marts.category_spending_summary AS
  WITH category_totals AS
       (
       SELECT dc.category
            , dc.subcategory
            , dc.expense_group
            , dc.is_fixed_expense
            , count(ft.transaction_id)
                FILTER (
                  WHERE ft.is_expense
                ) AS expense_transaction_count
            , coalesce(
                sum(ft.absolute_amount)
                  FILTER (
                    WHERE ft.is_expense
                  ),
                0
              ) AS gross_expense
            , count(ft.transaction_id)
                FILTER (
                  WHERE ft.is_refund
                ) AS refund_transaction_count
            , coalesce(
                sum(ft.absolute_amount)
                  FILTER (
                    WHERE ft.is_refund
                  ),
                0
              ) AS total_refund

         FROM marts.fct_transactions AS ft
         JOIN marts.dim_category AS dc
              ON ft.category_key = dc.category_key
        WHERE ft.is_expense
           OR ft.is_refund
        GROUP BY dc.category
               , dc.subcategory
               , dc.expense_group
               , dc.is_fixed_expense
       )

SELECT category
     , subcategory
     , expense_group
     , is_fixed_expense
     , expense_transaction_count
     , gross_expense
     , refund_transaction_count
     , total_refund
     , gross_expense - total_refund AS net_expense
     , CASE
         WHEN sum(
           gross_expense - total_refund
         ) OVER () = 0 THEN NULL
         ELSE (
           gross_expense - total_refund
         ) / sum(
           gross_expense - total_refund
         ) OVER ()
       END AS net_expense_share

  FROM category_totals;

-- ranks spending sources after refunds
CREATE OR REPLACE VIEW marts.top_sources AS
  WITH source_totals AS
       (
       SELECT ds.source_name
            , count(ft.transaction_id)
                FILTER (
                  WHERE ft.is_expense
                ) AS expense_transaction_count
            , coalesce(
                sum(ft.absolute_amount)
                  FILTER (
                    WHERE ft.is_expense
                  ),
                0
              ) AS gross_expense
            , count(ft.transaction_id)
                FILTER (
                  WHERE ft.is_refund
                ) AS refund_transaction_count
            , coalesce(
                sum(ft.absolute_amount)
                  FILTER (
                    WHERE ft.is_refund
                  ),
                0
              ) AS total_refund

         FROM marts.fct_transactions AS ft
         JOIN marts.dim_source AS ds
              ON ft.source_key = ds.source_key
        WHERE ft.is_expense
           OR ft.is_refund
        GROUP BY ds.source_name
       )

SELECT dense_rank() OVER(
         ORDER BY gross_expense - total_refund DESC
                , source_name
       ) AS source_spend_rank
     , source_name
     , expense_transaction_count
     , gross_expense
     , refund_transaction_count
     , total_refund
     , gross_expense - total_refund AS net_expense

  FROM source_totals;

-- month-over-month net spending by category and subcategory
CREATE OR REPLACE VIEW marts.month_over_month_category_change AS
  WITH months AS
       (
       SELECT DISTINCT date_trunc(
                'month',
                full_date
              )::date AS transaction_month
         FROM marts.dim_date
       ),

       -- creates every month and expense category/subcategory combination
       category_month_grid AS
       (
       SELECT m.transaction_month
            , dc.category_key
            , dc.category
            , dc.subcategory
            , dc.expense_group
            , dc.is_fixed_expense

         FROM months AS m
        CROSS JOIN marts.dim_category AS dc
        WHERE dc.expense_group IS DISTINCT FROM 'Income'
       ),

       -- calculates monthly expense after refunds
       monthly_category_spend AS
       (
       SELECT date_trunc(
                'month',
                dd.full_date
              )::date AS transaction_month
            , ft.category_key
            , sum(
                CASE
                  WHEN ft.is_expense
                    THEN ft.absolute_amount
                  WHEN ft.is_refund
                    THEN -ft.absolute_amount
                  ELSE 0
                END
              ) AS current_month_net_expense

         FROM marts.fct_transactions AS ft
         JOIN marts.dim_date AS dd
              ON ft.date_key = dd.date_key
        WHERE ft.is_expense
           OR ft.is_refund
        GROUP BY date_trunc(
                   'month',
                   dd.full_date
                 )::date
               , ft.category_key
       ),

       -- adds the prior month amount for each category/subcategory
       spend_with_prior AS
       (
       SELECT g.transaction_month
            , g.category
            , g.subcategory
            , g.expense_group
            , g.is_fixed_expense
            , coalesce(
                mcs.current_month_net_expense,
                0
              ) AS current_month_net_expense
            , lag(
                coalesce(
                  mcs.current_month_net_expense,
                  0
                )
              ) OVER(
                PARTITION BY g.category_key
                ORDER BY g.transaction_month
              ) AS prior_month_net_expense

         FROM category_month_grid AS g
         LEFT JOIN monthly_category_spend AS mcs
              ON g.transaction_month = mcs.transaction_month
             AND g.category_key = mcs.category_key
       )

SELECT transaction_month
     , category
     , subcategory
     , expense_group
     , is_fixed_expense
     , current_month_net_expense
     , prior_month_net_expense
     , current_month_net_expense
       -
       prior_month_net_expense AS month_over_month_change
     , CASE
         WHEN prior_month_net_expense IS NULL
           OR prior_month_net_expense = 0 THEN NULL
         ELSE (
           current_month_net_expense
           -
           prior_month_net_expense
         ) / prior_month_net_expense
       END AS month_over_month_change_pct

  FROM spend_with_prior;

-- daily and rolling 30-day net spend after refunds
CREATE OR REPLACE VIEW marts.rolling_30_day_spend AS
  WITH daily_spend AS
       (
       SELECT dd.full_date
            , coalesce(
                sum(
                  CASE
                    WHEN ft.is_expense
                      THEN ft.absolute_amount
                    WHEN ft.is_refund
                      THEN -ft.absolute_amount
                    ELSE 0
                  END
                ),
                0
              ) AS daily_net_expense

         FROM marts.dim_date AS dd
         LEFT JOIN marts.fct_transactions AS ft
              ON dd.date_key = ft.date_key
        GROUP BY dd.full_date
       )

SELECT full_date
     , daily_net_expense
     , sum(
         daily_net_expense
       ) OVER(
         ORDER BY full_date
         ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
       ) AS rolling_30_day_net_expense

  FROM daily_spend;

-- recurring expense candidates for review
CREATE OR REPLACE VIEW marts.recurring_expense_candidates AS
SELECT ds.source_name
     , dc.category
     , dc.subcategory
     , dc.expense_group
     , dc.is_fixed_expense
     , count(ft.transaction_id) AS expense_transaction_count
     , count(
         DISTINCT date_trunc(
           'month',
           dd.full_date
         )::date
       ) AS active_month_count
     , min(dd.full_date) AS first_transaction_date
     , max(dd.full_date) AS last_transaction_date
     , sum(ft.absolute_amount) AS total_expense
     , avg(ft.absolute_amount) AS average_transaction_amount
     , stddev_pop(ft.absolute_amount) AS amount_standard_deviation
     , CASE
         WHEN coalesce(
           stddev_pop(ft.absolute_amount),
           0
         ) <= avg(ft.absolute_amount) * 0.10
           THEN TRUE
         ELSE FALSE
       END AS is_low_variability_candidate
     , TRUE AS is_recurring_candidate

  FROM marts.fct_transactions AS ft
  JOIN marts.dim_date AS dd
       ON ft.date_key = dd.date_key
  JOIN marts.dim_source AS ds
       ON ft.source_key = ds.source_key
  JOIN marts.dim_category AS dc
       ON ft.category_key = dc.category_key
 WHERE ft.is_expense
 GROUP BY ds.source_name
        , dc.category
        , dc.subcategory
        , dc.expense_group
        , dc.is_fixed_expense
HAVING count(
         DISTINCT date_trunc(
           'month',
           dd.full_date
         )::date
       ) >= 3;