-- rebuild derived staging table from current V2 raw snapshot
DROP VIEW IF EXISTS quality.data_quality_check_summary;
DROP VIEW IF EXISTS quality.transaction_issues;
DROP VIEW IF EXISTS quality.unmapped_sources;
DROP VIEW IF EXISTS quality.unmapped_merchants;
DROP VIEW IF EXISTS quality.suspicious_duplicate_transaction_groups;

DROP TABLE IF EXISTS staging.transactions;

CREATE TABLE staging.transactions AS
  -- trim raw values before cleaning and conversion
  WITH source_values AS
       (
       SELECT nullif(btrim(r.source_transaction_id), '') AS source_transaction_id
            , r.source_file
            , r.raw_row_number
            , r.loaded_at AS raw_loaded_at
            , nullif(btrim(r.transaction_date), '') AS transaction_date_text
            , nullif(btrim(r.source), '') AS source_raw
            , nullif(btrim(r.description), '') AS description
            , nullif(btrim(r.category), '') AS category
            , nullif(btrim(r.subcategory), '') AS subcategory
            , nullif(btrim(r.transaction_type), '') AS transaction_type_raw
            , nullif(btrim(r.person), '') AS person
            , nullif(btrim(r.payment_method), '') AS payment_method_raw
            , nullif(btrim(r.account_name), '') AS account_name
            , nullif(btrim(r.related_transaction_id), '') AS related_transaction_id
            , nullif(btrim(r.notes), '') AS notes
              -- remove dollar signs, commas, and whitespace before amount conversion
            , nullif(
                regexp_replace(
                    btrim(r.amount),
                    '[$,[:space:]]',
                    '',
                    'g'
                ),
                ''
              ) AS amount_text

         FROM raw.transactions AS r
       ),

  -- parse dates and amounts, then standardize basic text fields
  cleaned_source AS
       (
       SELECT sv.source_transaction_id AS transaction_id
            , sv.source_transaction_id
            , sv.source_file
            , sv.raw_row_number
            , sv.raw_loaded_at

              -- supports both YYYY-MM-DD and M/D/YYYY CSV date formats
            , CASE
                WHEN sv.transaction_date_text ~ '^\d{4}-\d{2}-\d{2}$'
                  THEN to_date(
                      sv.transaction_date_text,
                      'YYYY-MM-DD'
                  )
                WHEN sv.transaction_date_text ~ '^\d{1,2}/\d{1,2}/\d{4}$'
                  THEN to_date(
                      sv.transaction_date_text,
                      'MM/DD/YYYY'
                  )
                ELSE NULL
              END AS transaction_date

            , sv.source_raw
              -- creates match key by removing spaces and special characters
            , nullif(
                regexp_replace(
                    lower(sv.source_raw),
                    '[^a-z0-9]+',
                    '',
                    'g'
                ),
                ''
              ) AS source_match_key

            , sv.description
            , sv.category
            , sv.subcategory

              -- changes values such as expense or EXPENSE to Expense
            , initcap(lower(sv.transaction_type_raw)) AS transaction_type

              -- only converts valid numeric amounts; invalid values become NULL
            , CASE
                WHEN sv.amount_text ~ '^-?[0-9]+(\.[0-9]{1,2})?$'
                  THEN sv.amount_text::numeric(12,2)
                ELSE NULL
              END AS amount

            , sv.person
            , initcap(lower(sv.payment_method_raw)) AS payment_method
            , sv.account_name
            , sv.related_transaction_id
            , sv.notes

         FROM source_values AS sv
       )

-- main staging query
SELECT cs.transaction_id
     , cs.source_transaction_id
     , cs.source_file
     , cs.raw_row_number
     , cs.raw_loaded_at
     , cs.transaction_date
       -- date_trunc returns first day of the transaction month
     , date_trunc(
         'month',
         cs.transaction_date
       )::date AS transaction_month
     , extract(
         year
         FROM cs.transaction_date
       )::integer AS transaction_year
     , cs.source_raw
     , cs.source_match_key
       -- use canonical source name when mapping exists, otherwise keep raw source
     , coalesce(
         sm.source_clean,
         cs.source_raw
       ) AS source_clean
     , cs.description
     , cs.category
     , cs.subcategory
     , cs.transaction_type
     , cs.amount
     , cs.person
     , cs.payment_method
     , cs.account_name
     , cs.related_transaction_id
     , cs.notes
       -- transaction type rules come from reference.transaction_types
     , tt.is_income
     , tt.is_expense
     , tt.is_refund
       -- Expenses become negative; Income and Refunds become positive
     , CASE
         WHEN cs.amount IS NOT NULL
          AND tt.signed_amount_multiplier IS NOT NULL
           THEN cs.amount * tt.signed_amount_multiplier
         ELSE NULL
       END AS signed_amount
     , abs(cs.amount) AS absolute_amount

  FROM cleaned_source AS cs
  -- source mapping is optional so unrecognized sources remain in staging
  LEFT JOIN reference.source_mappings AS sm
       ON cs.source_match_key = sm.source_match_key
  -- transaction type mapping derives reporting flags and amount signs
  LEFT JOIN reference.transaction_types AS tt
       ON cs.transaction_type = tt.transaction_type;

-- source_transaction_id is now the stable warehouse transaction ID
ALTER TABLE staging.transactions
  ADD CONSTRAINT staging_transactions_pkey
      PRIMARY KEY (transaction_id);