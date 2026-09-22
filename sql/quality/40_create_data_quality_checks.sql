-- main audit view, returns one row for each detected problem, one transaction may appear multiple times if violates multiple rules
CREATE OR REPLACE VIEW quality.transaction_issues AS 
  -- hard coded list of categories for checks
  WITH allowed_categories (category) AS 
       (
       VALUES ('Entertainment')
            , ('Gas')
            , ('Groceries')
            , ('Other')
            , ('Pets')
            , ('Rent')
            , ('Restaurants')
       ),

       -- transaction_id should be unique, find the dupes
       duplicate_transaction_ids AS
       (
       SELECT transaction_id
         FROM staging.transactions
        GROUP BY transaction_id
       HAVING COUNT(*) > 1
       ),

       -- checks for sus transactions where merchant, date, and amount are all the same
       suspicious_duplicate_groups AS
       (
       SELECT merchant_clean
            , transaction_date
            , absolute_amount
         FROM staging.transactions
        WHERE merchant_clean IS NOT NULL
          AND transaction_date IS NOT NULL
          AND absolute_amount IS NOT NULL
        GROUP BY merchant_clean, transaction_date, absolute_amount
       HAVING COUNT(*) > 1
       )

-- check if transaction_date missing
SELECT 'missing_transaction_date' AS check_name
     , 'error' AS severity
     , st.transaction_id
     , st.source_file
     , st.raw_row_number
     , st.transaction_date
     , st.merchant_clean
     , st.category
     , st.amount
     , st.notes
     , 'Transaction date is NULL' AS issue_detail
  FROM staging.transactions AS st
 WHERE st.transaction_date IS NULL

 UNION ALL

-- check if amount is missing
SELECT 'missing_amount'
     , 'error'
     , st.transaction_id
     , st.source_file
     , st.raw_row_number
     , st.transaction_date
     , st.merchant_clean
     , st.category
     , st.amount
     , st.notes
     , 'Amount is NULL.'
  FROM staging.transactions AS st
 WHERE st.amount IS NULL

 UNION ALL

-- check if category is allowed
SELECT 'invalid_category'
     , 'error'
     , st.transaction_id
     , st.source_file
     , st.raw_row_number
     , st.transaction_date
     , st.merchant_clean
     , st.category
     , st.amount
     , st.notes
     , 'Category is not in the approved category list.'
  FROM staging.transactions AS st
  LEFT JOIN allowed_categories AS ac
       ON st.category = ac.category
 WHERE st.category IS NOT NULL
   AND ac.category IS NULL

 UNION ALL

-- check for non unique transaction_id
SELECT 'duplicate_transaction_id'
     , 'error'
     , st.transaction_id
     , st.source_file
     , st.raw_row_number
     , st.transaction_date
     , st.merchant_clean
     , st.category
     , st.amount
     , st.notes
     , 'Transaction ID appears more than once.'
  FROM staging.transactions AS st
  JOIN duplicate_transaction_ids AS d
       ON st.transaction_id = d.transaction_id

 UNION ALL

-- check for incorrect signed income
SELECT 'negative_income_amount'
     , 'error'
     , st.transaction_id
     , st.source_file
     , st.raw_row_number
     , st.transaction_date
     , st.merchant_clean
     , st.category
     , st.amount
     , st.notes
     , 'Income transaction has a negative signed amount.'
  FROM staging.transactions AS st
 WHERE st.is_income
   AND st.signed_amount < 0

 UNION ALL

-- check for incorrect signed expense
SELECT 'positive_expense_amount'
     , 'error'
     , st.transaction_id
     , st.source_file
     , st.raw_row_number
     , st.transaction_date
     , st.merchant_clean
     , st.category
     , st.amount
     , st.notes
     , 'Expense transaction has a positive signed amount.'
  FROM staging.transactions AS st
 WHERE st.is_expense
   AND st.signed_amount > 0

 UNION ALL

-- check for dupes for same merchant same day same amount, sus
SELECT 'suspicious_merchant_date_amount_duplicate'
     , 'warning'
     , st.transaction_id
     , st.source_file
     , st.raw_row_number
     , st.transaction_date
     , st.merchant_clean
     , st.category
     , st.amount
     , st.notes
     , 'Same merchant, date, and amount appears in another transaction.'
  FROM staging.transactions AS st
  JOIN suspicious_duplicate_groups AS sd
       ON st.merchant_clean = sd.merchant_clean
       AND st.transaction_date = sd.transaction_date
       AND st.absolute_amount = sd.absolute_amount

 UNION ALL

-- checked if transaction is unclassified
SELECT 'unclassified_transaction'
     , 'warning'
     , st.transaction_id
     , st.source_file
     , st.raw_row_number
     , st.transaction_date
     , st.merchant_clean
     , st.category
     , st.amount
     , st.notes
     , 'Category is missing or classified as Unclassified.'
  FROM staging.transactions AS st
  LEFT JOIN marts.dim_category AS dc
       ON st.category = dc.category
 WHERE st.category IS NULL
    OR dc.expense_group IS NULL
    OR dc.expense_group = 'Unclassified'

 UNION ALL

-- checks if any transaction is outside of scope
SELECT 'future_dated_transaction'
     , 'error'
     , st.transaction_id
     , st.source_file
     , st.raw_row_number
     , st.transaction_date
     , st.merchant_clean
     , st.category
     , st.amount
     , st.notes
     , 'Transaction date is later than the current database date.'
  FROM staging.transactions AS st
 WHERE st.transaction_date > CURRENT_DATE

 UNION ALL

-- checks if any transactions have an amount of 0
SELECT 'zero_amount_transaction'
     , 'warning'
     , st.transaction_id
     , st.source_file
     , st.raw_row_number
     , st.transaction_date
     , st.merchant_clean
     , st.category
     , st.amount
     , st.notes
     , 'Transaction amount is zero and should be reviewed.'
  FROM staging.transactions AS st
 WHERE st.amount = 0;

-- turn issues into dashboard-friendly summary
CREATE OR REPLACE VIEW quality.data_quality_check_summary AS
  -- complete list of every expected check and its intended severity. if no errors found, dashboard will return 0 properly
  WITH check_catalog (check_name, severity) AS
       (
       VALUES ('missing_transaction_date', 'error')
            , ('missing_amount', 'error')
            , ('invalid_category', 'error')
            , ('duplicate_transaction_id', 'error')
            , ('negative_income_amount', 'error')
            , ('positive_expense_amount', 'error')
            , ('future_dated_transaction', 'error')
            , ('suspicious_merchant_date_amount_duplicate', 'warning')
            , ('unclassified_transaction', 'warning')
            , ('zero_amount_transaction', 'warning')
       ),

       -- counts issues for each check
       issue_counts AS
       (
       SELECT check_name
            , COUNT(*) AS issue_count
         FROM quality.transaction_issues
        GROUP BY check_name
       )

-- issue count, coalesce for possible null issues
SELECT cc.check_name
     , cc.severity
     , COALESCE(ic.issue_count, 0) AS issue_count
  FROM check_catalog AS cc
  LEFT JOIN issue_counts AS ic
       ON cc.check_name = ic.check_name;

-- what merchants havent been properly mapped
CREATE OR REPLACE VIEW quality.unmapped_merchants AS
  WITH mapped_merchant_keys (merchant_match_key) AS
       (
       VALUES ('amazon')
            , ('samsclub')
            , ('samscllulb')
            , ('walmart')
       )

-- match merchants to their known mapping, keep rows with no mapping, count. array_agg combines all non-mapped raw values into a single array
SELECT st.merchant_match_key
     , st.merchant_clean
     , COUNT(*) AS transaction_count
     , ARRAY_AGG(DISTINCT st.merchant_raw ORDER BY st.merchant_raw) AS merchant_raw_values
  FROM staging.transactions AS st
  LEFT JOIN mapped_merchant_keys AS mm
       ON st.merchant_match_key = mm.merchant_match_key
 WHERE st.merchant_match_key IS NOT NULL
   AND mm.merchant_match_key IS NULL
 GROUP BY st.merchant_match_key, st.merchant_clean;

-- grouped version of dupe warning from transaction_issues. shows one row per sus group
CREATE OR REPLACE VIEW quality.suspicious_duplicate_transaction_groups AS
SELECT merchant_clean
     , transaction_date
     , absolute_amount
     , COUNT(*) AS transaction_count
     , ARRAY_AGG(transaction_id ORDER BY transaction_id) AS transaction_id
  FROM staging.transactions
 WHERE merchant_clean IS NOT NULL
   AND transaction_date IS NOT NULL
   AND absolute_amount IS NOT NULL
 GROUP BY merchant_clean, transaction_date, absolute_amount
HAVING COUNT(*) > 1;