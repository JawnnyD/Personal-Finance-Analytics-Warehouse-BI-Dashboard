-- rebuild derived sraging table from current raw snapshot
DROP TABLE IF EXISTS staging.transactions;

CREATE TABLE staging.transactions AS
  -- temp set for common name mappings
  WITH merchant_mapping (merchant_match_key, merchant_clean) AS
       (
       VALUES ('amazon', 'Amazon')
            , ('samsclub', 'Sam''s Club')
            , ('samscllulb', 'Sam''s Club')
            , ('walmart', 'Walmart')
       ),
-- cte for cleaned results
cleaned_source AS
       (
              -- creates unique transaction id from source file and row number
       SELECT concat(r.source_file, ':', r.raw_row_number) AS transaction_id
            , r.source_file
            , r.raw_row_number
            , r.loaded_at AS raw_loaded_at
              -- converts string date to actual date
            , to_date(
                nullif(btrim(r.date), ''),
                'MM/DD/YYYY'
              ) AS transaction_date
            , nullif(btrim(r.merchant), '') AS merchant_raw
              -- create merchant match key-> trim whitespaces, all lowercase, remove non alphanumeric characters
            , nullif(
                regexp_replace(
                    lower(btrim(r.merchant)),
                    '[^a-z0-9]+',
                    '',
                    'g'
                ),
                ''
              ) AS merchant_match_key
            , nullif(btrim(r.description), '') AS description
            , nullif(btrim(r.category), '') AS category
            , nullif(btrim(r.paid_by), '') AS paid_by
            , nullif(btrim(r.payment_method), '') AS payment_method
            , nullif(btrim(r.notes), '') AS notes
              -- clean amount -> trim whitespace, remove dollar sign, remove commas
            , nullif(
                replace(
                    replace(btrim(r.amount), '$', ''),
                    ',',
                    ''
                ),
                ''
              )::numeric(12,2) AS amount

         FROM raw.transactions AS r
       )

-- main query
SELECT cs.transaction_id
     , cs.source_file
     , cs.raw_row_number
     , cs.raw_loaded_at
     , cs.transaction_date
       -- date_trunc returns start of the month, ::date turns into plain date
     , date_trunc('month', cs.transaction_date)::date AS transaction_month
       -- pulls year out of transaction date, convert to integer
     , extract(year FROM cs.transaction_date)::integer AS transaction_year
     , cs.merchant_raw
     , cs.merchant_match_key
       -- chooses best clean merchant name, if standardized name in mapping, else raw name
     , coalesce(mm.merchant_clean, cs.merchant_raw) AS merchant_clean
     , cs.description
     , cs.category
     , cs.paid_by
     , cs.payment_method
     , cs.notes
     , cs.amount
       -- currently only has expenses, so hardcoded as expense
     , 'expense'::text AS transaction_type
     , FALSE AS is_income
     , TRUE AS is_expense
     , -cs.amount AS signed_amount
     , abs(cs.amount) AS absolute_amount

  FROM cleaned_source AS cs
  -- left join on merchant match key so if no match is found, there is NULL, works for coalesce
  LEFT JOIN merchant_mapping AS mm
       ON cs.merchant_match_key = mm.merchant_match_key;

 -- add primary key to finished staging table, primary key is transaction_id
 ALTER TABLE staging.transactions
   ADD CONSTRAINT staging_transactions_pkey
       PRIMARY KEY (transaction_id);