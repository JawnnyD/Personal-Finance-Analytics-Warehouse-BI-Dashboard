-- rebuild V2 data quality views from the current staging table
DROP VIEW IF EXISTS quality.data_quality_check_summary;
DROP VIEW IF EXISTS quality.transaction_issues;
DROP VIEW IF EXISTS quality.unmapped_sources;
DROP VIEW IF EXISTS quality.unmapped_merchants;
DROP VIEW IF EXISTS quality.suspicious_duplicate_transaction_groups;

-- review groups of transactions that may be duplicates
CREATE VIEW quality.suspicious_duplicate_transaction_groups AS
SELECT st.source_clean
     , st.transaction_date
     , st.transaction_type
     , st.absolute_amount
     , count(*) AS transaction_count
     , array_agg(
           st.transaction_id
           ORDER BY st.transaction_id
       ) AS transaction_ids

  FROM staging.transactions AS st

 WHERE st.source_clean IS NOT NULL
   AND st.transaction_date IS NOT NULL
   AND st.transaction_type IS NOT NULL
   AND st.absolute_amount IS NOT NULL

 GROUP BY st.source_clean
        , st.transaction_date
        , st.transaction_type
        , st.absolute_amount

HAVING count(*) > 1;

-- work queue for source names that do not yet have a cleanup mapping
-- an unmapped source is not automatically invalid; it may already be clean
CREATE VIEW quality.unmapped_sources AS
SELECT st.source_match_key
     , array_agg(
           DISTINCT st.source_raw
           ORDER BY st.source_raw
       ) AS source_variants
     , min(st.source_clean) AS current_source_name
     , count(*) AS transaction_count

  FROM staging.transactions AS st

  LEFT JOIN reference.source_mappings AS sm
       ON st.source_match_key = sm.source_match_key

 WHERE st.source_match_key IS NOT NULL
   AND sm.source_match_key IS NULL

 GROUP BY st.source_match_key;

-- main audit view: one row for every detected transaction-level issue
CREATE VIEW quality.transaction_issues AS
  WITH refund_totals AS
       (
       SELECT st.related_transaction_id
            , sum(st.absolute_amount) AS total_refund_amount

         FROM staging.transactions AS st

        WHERE st.transaction_type = 'Refund'
          AND st.related_transaction_id IS NOT NULL

        GROUP BY st.related_transaction_id
       )
     , base AS
       (
       SELECT st.transaction_id
            , st.source_file
            , st.raw_row_number
            , st.transaction_date
            , st.source_raw
            , st.source_clean
            , st.category
            , st.subcategory
            , st.transaction_type
            , st.amount
            , st.signed_amount
            , st.absolute_amount
            , st.person
            , st.payment_method
            , st.account_name
            , st.related_transaction_id
            , st.notes
            , tt.transaction_type AS reference_transaction_type
            , cs.category AS reference_category
            , rp.person AS reference_person
            , pm.payment_method AS reference_payment_method
            , pa.account_name AS reference_account_name
            , original.transaction_id AS related_transaction_exists
            , original.transaction_type AS related_transaction_type
            , original.absolute_amount AS related_transaction_amount
            , rt.total_refund_amount

         FROM staging.transactions AS st

         LEFT JOIN reference.transaction_types AS tt
              ON st.transaction_type = tt.transaction_type

         LEFT JOIN reference.category_subcategories AS cs
              ON st.category = cs.category
             AND st.subcategory = cs.subcategory

         LEFT JOIN reference.people AS rp
              ON st.person = rp.person

         LEFT JOIN reference.payment_methods AS pm
              ON st.payment_method = pm.payment_method

         LEFT JOIN reference.person_payment_accounts AS pa
              ON st.person = pa.person
             AND st.payment_method = pa.payment_method
             AND st.account_name = pa.account_name

         LEFT JOIN staging.transactions AS original
              ON st.related_transaction_id = original.transaction_id

         LEFT JOIN refund_totals AS rt
              ON st.related_transaction_id = rt.related_transaction_id
       )

SELECT rule.check_name
     , rule.severity
     , b.transaction_id
     , b.source_file
     , b.raw_row_number
     , b.transaction_date
     , b.source_clean
     , b.category
     , b.subcategory
     , b.transaction_type
     , b.amount
     , b.signed_amount
     , b.person
     , b.payment_method
     , b.account_name
     , b.related_transaction_id
     , b.notes
     , rule.issue_detail

  FROM base AS b

 CROSS JOIN LATERAL
       (
       VALUES
           (
             'missing_source'::text
           , 'error'::text
           , b.source_clean IS NULL
           , 'source is blank.'
           )
         , (
             'missing_transaction_date'
           , 'error'
           , b.transaction_date IS NULL
           , 'transaction_date could not be converted into a valid date.'
           )
         , (
             'missing_amount'
           , 'error'
           , b.amount IS NULL
           , 'amount is blank or could not be converted into a number.'
           )
         , (
             'negative_amount'
           , 'error'
           , b.amount < 0
           , concat('amount is negative: ', b.amount, '. Amount should be a positive magnitude.')
           )
         , (
             'zero_amount_transaction'
           , 'error'
           , b.amount = 0
           , 'amount is zero. A transaction should have a positive amount.'
           )
         , (
             'invalid_transaction_type'
           , 'error'
           , b.transaction_type IS NOT NULL
             AND b.reference_transaction_type IS NULL
           , concat(
               'transaction_type "',
               b.transaction_type,
               '" is not in reference.transaction_types.'
             )
           )
         , (
             'missing_category_or_subcategory'
           , 'error'
           , b.category IS NULL
             OR b.subcategory IS NULL
           , 'category or subcategory is blank.'
           )
         , (
             'invalid_category_subcategory'
           , 'error'
           , b.category IS NOT NULL
             AND b.subcategory IS NOT NULL
             AND b.reference_category IS NULL
           , concat(
               'The category/subcategory pair "',
               b.category,
               ' / ',
               b.subcategory,
               '" is not in reference.category_subcategories.'
             )
           )
         , (
             'missing_person'
           , 'error'
           , b.person IS NULL
           , 'person is blank.'
           )
         , (
             'invalid_person'
           , 'error'
           , b.person IS NOT NULL
             AND b.reference_person IS NULL
           , concat('person "', b.person, '" is not in reference.people.')
           )
         , (
             'missing_payment_method'
           , 'error'
           , b.payment_method IS NULL
           , 'payment_method is blank.'
           )
         , (
             'invalid_payment_method'
           , 'error'
           , b.payment_method IS NOT NULL
             AND b.reference_payment_method IS NULL
           , concat(
               'payment_method "',
               b.payment_method,
               '" is not in reference.payment_methods.'
             )
           )
         , (
             'missing_account_name'
           , 'warning'
           , b.account_name IS NULL
             AND b.payment_method IS NOT NULL
             AND NOT (
                 b.payment_method = 'Other'
                 AND b.notes IS NOT NULL
             )
           , 'account_name is blank without the documented Other-payment-method exception.'
           )
         , (
             'invalid_account_combination'
           , 'error'
           , b.account_name IS NOT NULL
             AND b.reference_person IS NOT NULL
             AND b.reference_payment_method IS NOT NULL
             AND b.reference_account_name IS NULL
           , concat(
               'The person, payment method, and account name combination is not in ',
               'reference.person_payment_accounts.'
             )
           )
         , (
             'income_not_in_income_category'
           , 'error'
           , b.transaction_type = 'Income'
             AND b.category IS DISTINCT FROM 'Income'
           , 'Income transactions must use the Income category.'
           )
         , (
             'non_income_in_income_category'
           , 'error'
           , b.transaction_type IN ('Expense', 'Refund')
             AND b.category = 'Income'
           , 'Expense and Refund transactions should not use the Income category.'
           )
         , (
             'expense_with_invalid_signed_amount'
           , 'error'
           , b.transaction_type = 'Expense'
             AND (
                 b.signed_amount IS NULL
                 OR b.signed_amount >= 0
             )
           , 'Expense signed_amount must be negative.'
           )
         , (
             'income_with_invalid_signed_amount'
           , 'error'
           , b.transaction_type = 'Income'
             AND (
                 b.signed_amount IS NULL
                 OR b.signed_amount <= 0
             )
           , 'Income signed_amount must be positive.'
           )
         , (
             'refund_with_invalid_signed_amount'
           , 'error'
           , b.transaction_type = 'Refund'
             AND (
                 b.signed_amount IS NULL
                 OR b.signed_amount <= 0
             )
           , 'Refund signed_amount must be positive.'
           )
         , (
             'refund_missing_related_transaction_id'
           , 'error'
           , b.transaction_type = 'Refund'
             AND b.related_transaction_id IS NULL
           , 'Refund transactions must identify the original expense transaction.'
           )
         , (
             'refund_related_transaction_not_found'
           , 'error'
           , b.transaction_type = 'Refund'
             AND b.related_transaction_id IS NOT NULL
             AND b.related_transaction_exists IS NULL
           , 'related_transaction_id does not match an existing transaction.'
           )
         , (
             'refund_related_transaction_not_expense'
           , 'error'
           , b.transaction_type = 'Refund'
             AND b.related_transaction_exists IS NOT NULL
             AND b.related_transaction_type <> 'Expense'
           , 'A refund must point to an Expense transaction.'
           )
         , (
             'refund_exceeds_original_amount'
           , 'error'
           , b.transaction_type = 'Refund'
             AND b.related_transaction_amount IS NOT NULL
             AND b.total_refund_amount > b.related_transaction_amount
           , concat(
               'Total refunds of ',
               b.total_refund_amount,
               ' exceed the original expense amount of ',
               b.related_transaction_amount,
               '.'
             )
           )
         , (
             'related_transaction_id_on_non_refund'
           , 'warning'
           , b.transaction_type IN ('Expense', 'Income')
             AND b.related_transaction_id IS NOT NULL
           , 'related_transaction_id is normally used only for Refund transactions.'
           )
         , (
             'unclassified_transaction'
           , 'warning'
           , b.category = 'Other'
             AND b.subcategory = 'To Review'
           , 'Transaction is still assigned to Other / To Review.'
           )
         , (
             'future_dated_transaction'
           , 'error'
           , b.transaction_date > current_date
           , 'transaction_date is in the future.'
           )
       ) AS rule (
           check_name
         , severity
         , has_issue
         , issue_detail
       )

 WHERE rule.has_issue

UNION ALL

SELECT 'suspicious_duplicate_source_date_amount' AS check_name
     , 'warning' AS severity
     , st.transaction_id
     , st.source_file
     , st.raw_row_number
     , st.transaction_date
     , st.source_clean
     , st.category
     , st.subcategory
     , st.transaction_type
     , st.amount
     , st.signed_amount
     , st.person
     , st.payment_method
     , st.account_name
     , st.related_transaction_id
     , st.notes
     , concat(
         'Found ',
         sd.transaction_count,
         ' transactions with the same source, date, transaction type, and amount.'
       ) AS issue_detail

  FROM staging.transactions AS st

 INNER JOIN quality.suspicious_duplicate_transaction_groups AS sd
       ON st.source_clean = sd.source_clean
      AND st.transaction_date = sd.transaction_date
      AND st.transaction_type = sd.transaction_type
      AND st.absolute_amount = sd.absolute_amount;

-- summary view: includes checks with zero issues so trends are easy to monitor
CREATE VIEW quality.data_quality_check_summary AS
  WITH expected_checks (check_name, severity) AS
       (
       VALUES
           ('missing_source'::text, 'error'::text)
         , ('missing_transaction_date', 'error')
         , ('missing_amount', 'error')
         , ('negative_amount', 'error')
         , ('zero_amount_transaction', 'error')
         , ('invalid_transaction_type', 'error')
         , ('missing_category_or_subcategory', 'error')
         , ('invalid_category_subcategory', 'error')
         , ('missing_person', 'error')
         , ('invalid_person', 'error')
         , ('missing_payment_method', 'error')
         , ('invalid_payment_method', 'error')
         , ('missing_account_name', 'warning')
         , ('invalid_account_combination', 'error')
         , ('income_not_in_income_category', 'error')
         , ('non_income_in_income_category', 'error')
         , ('expense_with_invalid_signed_amount', 'error')
         , ('income_with_invalid_signed_amount', 'error')
         , ('refund_with_invalid_signed_amount', 'error')
         , ('refund_missing_related_transaction_id', 'error')
         , ('refund_related_transaction_not_found', 'error')
         , ('refund_related_transaction_not_expense', 'error')
         , ('refund_exceeds_original_amount', 'error')
         , ('related_transaction_id_on_non_refund', 'warning')
         , ('suspicious_duplicate_source_date_amount', 'warning')
         , ('unclassified_transaction', 'warning')
         , ('future_dated_transaction', 'error')
       )

SELECT ec.check_name
     , ec.severity
     , count(ti.transaction_id)::bigint AS issue_count

  FROM expected_checks AS ec

  LEFT JOIN quality.transaction_issues AS ti
       ON ec.check_name = ti.check_name

 GROUP BY ec.check_name
        , ec.severity

 ORDER BY case
              when ec.severity = 'error' then 1
              else 2
          end
        , ec.check_name;